import Foundation

/// Every file the tool reads or writes. `home` is injectable so tests never touch the real home folder.
public struct Paths {
    public let home: URL

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser) {
        self.home = home
    }

    public var dir: URL { home.appendingPathComponent(".config/gh-acc-switch") }
    public var config: URL { dir.appendingPathComponent("config.json") }
    /// Included at the top of ~/.gitconfig: global identity, credential helper, per-folder includeIf rules.
    public var managedGitconfig: URL { dir.appendingPathComponent("gitconfig") }
    public var accountsDir: URL { dir.appendingPathComponent("accounts") }
    public var shellInit: URL { dir.appendingPathComponent("init.sh") }
    public var binDir: URL { dir.appendingPathComponent("bin") }
    /// Stable path to the app binary, used by git as the credential helper and by the shell wrapper.
    public var cliLink: URL { binDir.appendingPathComponent("gh-acc-switch") }

    public var globalGitconfig: URL { home.appendingPathComponent(".gitconfig") }
    public var zshrc: URL { home.appendingPathComponent(".zshrc") }

    public var ghHostsFile: URL {
        if let dir = ProcessInfo.processInfo.environment["GH_CONFIG_DIR"], !dir.isEmpty {
            return URL(fileURLWithPath: dir).appendingPathComponent("hosts.yml")
        }
        return home.appendingPathComponent(".config/gh/hosts.yml")
    }

    public func accountGitconfig(_ id: UUID) -> URL {
        accountsDir.appendingPathComponent("\(id.uuidString).gitconfig")
    }
}
