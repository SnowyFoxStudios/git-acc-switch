import Foundation

/// Hooks the managed gitconfig into ~/.gitconfig, and takes it out again.
public struct GitIntegration {
    public let paths: Paths

    public init(paths: Paths) { self.paths = paths }

    public var isInstalled: Bool {
        guard let text = try? String(contentsOf: paths.globalGitconfig, encoding: .utf8) else { return false }
        return text.contains(paths.managedGitconfig.path)
    }

    /// The [user] currently hard-coded in ~/.gitconfig (it would override the app, so install removes it).
    public func hardcodedUser() -> (name: String, email: String)? {
        let file = paths.globalGitconfig.path
        let name = Shell.run(Shell.gitPath, ["config", "-f", file, "--get", "user.name"])
        let email = Shell.run(Shell.gitPath, ["config", "-f", file, "--get", "user.email"])
        guard name.ok || email.ok else { return nil }
        return (
            name.out.trimmingCharacters(in: .whitespacesAndNewlines),
            email.out.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }

    /// Backs up ~/.gitconfig, removes the hard-coded [user] and gh's credential helper sections,
    /// and adds an [include] of the managed file at the very top. Returns the backup's location.
    @discardableResult
    public func install(_ config: AppConfig) throws -> URL? {
        let fm = FileManager.default
        var backup: URL?
        if fm.fileExists(atPath: paths.globalGitconfig.path) {
            let stamp = Self.timestamp()
            let url = paths.home.appendingPathComponent(".gitconfig.gh-acc-switch-backup-\(stamp)")
            try fm.copyItem(at: paths.globalGitconfig, to: url)
            backup = url
        }

        removeOverridingSections(config)

        if !isInstalled {
            let existing = (try? String(contentsOf: paths.globalGitconfig, encoding: .utf8)) ?? ""
            let block = "[include]\n\tpath = \(GitConfigText.quote(paths.managedGitconfig.path))\n"
            try (block + existing).write(to: paths.globalGitconfig, atomically: true, encoding: .utf8)
        }
        return backup
    }

    /// gh re-adds its credential helper to ~/.gitconfig on some logins; call after each login.
    public func repair(_ config: AppConfig) {
        guard isInstalled else { return }
        removeOverridingSections(config)
    }

    /// Removes the include and puts a plain [user] and gh's credential helper back.
    public func uninstall(restoring account: Account?, gh: GH?) throws {
        let text = (try? String(contentsOf: paths.globalGitconfig, encoding: .utf8)) ?? ""
        var lines = text.components(separatedBy: "\n").filter { !$0.contains(paths.managedGitconfig.path) }
        // Drop [include] headers left empty by the removal.
        var i = 0
        while i < lines.count {
            let isInclude = lines[i].trimmingCharacters(in: .whitespaces) == "[include]"
            let next = i + 1 < lines.count ? lines[i + 1].trimmingCharacters(in: .whitespaces) : ""
            if isInclude && (next.isEmpty || next.hasPrefix("[")) {
                lines.remove(at: i)
            } else {
                i += 1
            }
        }
        try lines.joined(separator: "\n").write(to: paths.globalGitconfig, atomically: true, encoding: .utf8)

        let file = paths.globalGitconfig.path
        if let account {
            Shell.run(Shell.gitPath, ["config", "-f", file, "user.name", account.gitName])
            Shell.run(Shell.gitPath, ["config", "-f", file, "user.email", account.gitEmail])
        }
        gh?.setupGit()
    }

    private func removeOverridingSections(_ config: AppConfig) {
        let file = paths.globalGitconfig.path
        for section in ["user"] + GitConfigText.ghCredentialSections(config) {
            Shell.run(Shell.gitPath, ["config", "-f", file, "--remove-section", section])
        }
    }

    static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: Date())
    }
}

/// Sources init.sh from ~/.zshenv so `gh` picks the folder's account in every zsh, not just terminal tabs.
public struct ShellIntegration {
    public static let marker = "# gh-acc-switch"
    public let paths: Paths

    public init(paths: Paths) { self.paths = paths }

    public var sourceLine: String {
        let p = paths.shellInit.path
        return "[ -f \"\(p)\" ] && source \"\(p)\"  \(Self.marker)"
    }

    public var isInstalled: Bool { Self.hasMarker(paths.zshenv) }

    /// Installed by an older version, which only reached interactive shells.
    public var isInLegacyLocation: Bool { Self.hasMarker(paths.zshrc) }

    public func install() throws {
        if isInLegacyLocation { try Self.removeMarker(from: paths.zshrc) }
        guard !isInstalled else { return }
        var text = (try? String(contentsOf: paths.zshenv, encoding: .utf8)) ?? ""
        if !text.isEmpty && !text.hasSuffix("\n") { text += "\n" }
        text += "\n" + sourceLine + "\n"
        try text.write(to: paths.zshenv, atomically: true, encoding: .utf8)
    }

    public func uninstall() throws {
        try Self.removeMarker(from: paths.zshenv)
        try Self.removeMarker(from: paths.zshrc)
    }

    private static func hasMarker(_ file: URL) -> Bool {
        ((try? String(contentsOf: file, encoding: .utf8)) ?? "").contains(marker)
    }

    private static func removeMarker(from file: URL) throws {
        guard let text = try? String(contentsOf: file, encoding: .utf8), text.contains(marker) else { return }
        let kept = text.components(separatedBy: "\n").filter { !$0.contains(marker) }
        try kept.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
    }

    /// Wraps `gh` so it uses the folder's account (via GH_TOKEN) when that differs from the global one.
    /// `gh auth ...` is left alone so logging in and switching keep working normally.
    public static func initScript(paths: Paths) -> String {
        """
        # Managed by gh-acc-switch. Changes here are overwritten.
        export PATH="\(paths.binDir.path):$PATH"

        gh() {
          if [ -z "$GH_TOKEN" ] && [ "$1" != "auth" ]; then
            local _ghas_token
            _ghas_token="$(gh-acc-switch token-for-cwd 2>/dev/null)"
            if [ -n "$_ghas_token" ]; then
              GH_TOKEN="$_ghas_token" command gh "$@"
              return $?
            fi
          fi
          command gh "$@"
        }

        """
    }
}

/// Writes config.json and every generated file from it.
public enum Writer {
    public static func apply(_ config: AppConfig, paths: Paths) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.accountsDir, withIntermediateDirectories: true)
        try ConfigStore.save(config, paths)
        try GitConfigText.managed(config, paths: paths)
            .write(to: paths.managedGitconfig, atomically: true, encoding: .utf8)

        let wanted = Set(config.accounts.map { paths.accountGitconfig($0.id).lastPathComponent })
        for account in config.accounts {
            try GitConfigText.account(account)
                .write(to: paths.accountGitconfig(account.id), atomically: true, encoding: .utf8)
        }
        for name in (try? fm.contentsOfDirectory(atPath: paths.accountsDir.path)) ?? []
        where name.hasSuffix(".gitconfig") && !wanted.contains(name) {
            try? fm.removeItem(at: paths.accountsDir.appendingPathComponent(name))
        }

        try ShellIntegration.initScript(paths: paths)
            .write(to: paths.shellInit, atomically: true, encoding: .utf8)
    }

    /// Points ~/.config/gh-acc-switch/bin/gh-acc-switch at the running app binary.
    public static func linkCLI(executable: String, paths: Paths) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: paths.binDir, withIntermediateDirectories: true)
        let link = paths.cliLink.path
        if let current = try? fm.destinationOfSymbolicLink(atPath: link), current == executable { return }
        try? fm.removeItem(atPath: link)
        try fm.createSymbolicLink(atPath: link, withDestinationPath: executable)
    }
}
