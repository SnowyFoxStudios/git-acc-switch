import Foundation

/// Renders the gitconfig files the tool owns. Pure functions, so they're easy to test.
public enum GitConfigText {
    public static let header = "# Managed by gh-acc-switch. Changes here are overwritten; use the menu bar app."

    /// Quotes a gitconfig value or subsection name.
    public static func quote(_ s: String) -> String {
        let escaped = s
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    /// ~/.config/gh-acc-switch/gitconfig, included at the top of ~/.gitconfig.
    ///
    /// Order matters, because later git config entries win:
    /// 1. global [user] for the active account,
    /// 2. our credential helper (the empty `helper =` resets helpers inherited from system config),
    /// 3. folder rules, shortest path first so nested folders override their parents.
    /// Anything in ~/.gitconfig after the include (e.g. hand-written includeIf blocks) still wins.
    public static func managed(_ config: AppConfig, paths: Paths) -> String {
        var lines = [header, ""]

        if let active = config.activeAccount {
            lines += ["[user]", "\tname = \(quote(active.gitName))", "\temail = \(quote(active.gitEmail))", ""]
        }

        let helper = "!'\(paths.cliLink.path)' credential"
        for url in credentialURLs(config) {
            lines += ["[credential \(quote(url))]", "\thelper =", "\thelper = \(quote(helper))", ""]
        }

        let rules = config.rules
            .filter { config.account($0.accountId) != nil }
            .sorted { AppConfig.normalize($0.path).count < AppConfig.normalize($1.path).count }
        for rule in rules {
            let dir = AppConfig.normalize(rule.path)
            let pattern = "gitdir/i:" + (dir.hasSuffix("/") ? dir : dir + "/")
            lines += [
                "[includeIf \(quote(pattern))]",
                "\tpath = \(quote(paths.accountGitconfig(rule.accountId).path))",
                "",
            ]
        }

        return lines.joined(separator: "\n")
    }

    /// accounts/<id>.gitconfig, included for folders assigned to that account.
    public static func account(_ account: Account) -> String {
        [
            header,
            "",
            "[user]",
            "\tname = \(quote(account.gitName))",
            "\temail = \(quote(account.gitEmail))",
            "[ghswitch]",
            "\tfolderUser = \(quote(account.login))",
            "\tfolderHost = \(quote(account.host))",
            "",
        ].joined(separator: "\n")
    }

    public static func credentialURLs(_ config: AppConfig) -> [String] {
        var hosts = Set(config.accounts.map(\.host))
        hosts.insert("github.com")
        var urls: [String] = []
        for host in hosts.sorted() {
            urls.append("https://\(host)")
            if host == "github.com" { urls.append("https://gist.github.com") }
        }
        return urls
    }

    /// Credential sections gh writes into ~/.gitconfig, which would override ours if left in place.
    public static func ghCredentialSections(_ config: AppConfig) -> [String] {
        credentialURLs(config).map { "credential.\($0)" }
    }
}
