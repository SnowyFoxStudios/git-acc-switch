import Foundation

/// Which account applies where. Folder rules beat the global account.
public struct Resolver {
    public let config: AppConfig
    public let paths: Paths

    public init(config: AppConfig, paths: Paths) {
        self.config = config
        self.paths = paths
    }

    /// The folder rule for `cwd`: first from git config (inside a repo, includeIf already applied it),
    /// then from the rule list by path, which also covers folders that aren't git repos.
    public func folderLogin(cwd: String) -> GhLogin? {
        let git = Shell.gitPath
        let user = Shell.run(git, ["config", "--get", "ghswitch.folderuser"], cwd: cwd)
        let login = user.out.trimmingCharacters(in: .whitespacesAndNewlines)
        if user.ok, !login.isEmpty {
            let hostResult = Shell.run(git, ["config", "--get", "ghswitch.folderhost"], cwd: cwd)
            let host = hostResult.out.trimmingCharacters(in: .whitespacesAndNewlines)
            return GhLogin(host: host.isEmpty ? "github.com" : host, login: login, active: false)
        }
        if let rule = config.rule(forPath: cwd), let account = config.account(rule.accountId) {
            return GhLogin(host: account.host, login: account.login, active: false)
        }
        return nil
    }

    public func globalLogin(host: String) -> String? {
        if let active = config.activeAccount, active.host == host { return active.login }
        return HostsFile.read(paths).first { $0.host == host && $0.active }?.login
    }
}

public enum CLI {
    public static let commands: Set<String> = [
        "credential", "token-for-cwd", "status", "list", "switch", "help", "--help", "-h",
    ]

    public static func run(_ args: [String]) -> Int32 {
        let paths = Paths()
        let config = ConfigStore.load(paths)
        let command = args.first ?? "help"

        if command == "help" || command == "--help" || command == "-h" {
            print(usage)
            return 0
        }
        guard let gh = GH.locate(preferred: config.ghPath) else {
            FileHandle.standardError.write(Data("gh-acc-switch: gh CLI not found (brew install gh)\n".utf8))
            return 1
        }
        let resolver = Resolver(config: config, paths: paths)
        let cwd = FileManager.default.currentDirectoryPath

        switch command {
        case "credential":
            return credential(op: args.dropFirst().first ?? "", resolver: resolver, gh: gh, paths: paths)

        case "token-for-cwd":
            // Only prints when the folder's account differs from the global one, so the
            // shell wrapper leaves gh alone in the common case.
            guard let folder = resolver.folderLogin(cwd: cwd),
                  folder.login.caseInsensitiveCompare(resolver.globalLogin(host: folder.host) ?? "") != .orderedSame,
                  let token = gh.token(host: folder.host, login: folder.login)
            else { return 0 }
            print(token)
            return 0

        case "list":
            for account in config.accounts {
                let mark = account.id == config.activeAccountId ? "*" : " "
                print("\(mark) \(account.label)\t@\(account.login)\t\(account.gitName) <\(account.gitEmail)>")
            }
            return 0

        case "status":
            let global = config.activeAccount
            print("Global:  \(global.map { "\($0.label) (@\($0.login))" } ?? "none")")
            if let folder = resolver.folderLogin(cwd: cwd) {
                let label = config.accounts.first { $0.login == folder.login && $0.host == folder.host }?.label
                print("Folder:  \(label ?? folder.login) (@\(folder.login)) for \(cwd)")
            } else {
                print("Folder:  no rule for \(cwd), using global")
            }
            let name = Shell.run(Shell.gitPath, ["config", "--get", "user.name"], cwd: cwd).out
            let email = Shell.run(Shell.gitPath, ["config", "--get", "user.email"], cwd: cwd).out
            print("Commits: \(name.trimmingCharacters(in: .newlines)) <\(email.trimmingCharacters(in: .newlines))>")
            return 0

        case "switch":
            guard let query = args.dropFirst().first,
                  let account = config.accounts.first(where: {
                      $0.label.caseInsensitiveCompare(query) == .orderedSame
                          || $0.login.caseInsensitiveCompare(query) == .orderedSame
                  })
            else {
                FileHandle.standardError.write(Data("usage: gh-acc-switch switch <label|login>\n".utf8))
                return 2
            }
            do {
                try gh.switchTo(host: account.host, login: account.login)
                var updated = config
                updated.activeAccountId = account.id
                try Writer.apply(updated, paths: paths)
                print("Switched to \(account.label) (@\(account.login))")
                return 0
            } catch {
                FileHandle.standardError.write(Data("gh-acc-switch: \(error.localizedDescription)\n".utf8))
                return 1
            }

        default:
            print(usage)
            return 2
        }
    }

    /// git credential helper protocol: https://git-scm.com/docs/gitcredentials
    /// Picks the account from, in order: the username in the remote URL, the folder rule, the global account.
    static func credential(op: String, resolver: Resolver, gh: GH, paths: Paths) -> Int32 {
        let input = parseCredentialInput(readStdin())
        guard op == "get", input["protocol"] == "https", let host = input["host"] else { return 0 }

        // Gists authenticate with the github.com account.
        let authHost = host == "gist.github.com" ? "github.com" : host
        let known = HostsFile.read(paths).filter { $0.host == authHost }
        let cwd = FileManager.default.currentDirectoryPath

        var login: String?
        if let fromURL = input["username"], !fromURL.isEmpty {
            login = known.first { $0.login.caseInsensitiveCompare(fromURL) == .orderedSame }?.login ?? fromURL
        } else if let folder = resolver.folderLogin(cwd: cwd), folder.host == authHost {
            login = folder.login
        } else {
            login = resolver.globalLogin(host: authHost)
        }

        guard let login, let token = gh.token(host: authHost, login: login) else { return 0 }
        print("protocol=https\nhost=\(host)\nusername=\(login)\npassword=\(token)\n", terminator: "")
        return 0
    }

    public static func parseCredentialInput(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        for line in text.components(separatedBy: "\n") {
            guard let eq = line.firstIndex(of: "=") else { continue }
            result[String(line[..<eq])] = String(line[line.index(after: eq)...])
        }
        return result
    }

    private static func readStdin() -> String {
        String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)
    }

    static let usage = """
        gh-acc-switch: switch GitHub accounts for git and gh

        Usage:
          gh-acc-switch status            global account, folder override and commit identity here
          gh-acc-switch list              configured accounts (* = global)
          gh-acc-switch switch <name>     make an account global (label or GitHub login)
          gh-acc-switch credential get    git credential helper (configured automatically)
          gh-acc-switch token-for-cwd     token for this folder's account, if it overrides the global one

        Add accounts and folder rules in the menu bar app.
        """
}
