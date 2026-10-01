import Foundation

/// A GitHub login (authenticated once through `gh`) plus the git identity to commit with.
public struct Account: Codable, Identifiable, Hashable {
    public var id: UUID
    /// Display name in the menu bar, e.g. "Personal" or "Work".
    public var label: String
    /// GitHub username, exactly as `gh` knows it.
    public var login: String
    public var host: String
    public var gitName: String
    public var gitEmail: String

    public init(
        id: UUID = UUID(), label: String, login: String, host: String = "github.com",
        gitName: String, gitEmail: String
    ) {
        self.id = id
        self.label = label
        self.login = login
        self.host = host
        self.gitName = gitName
        self.gitEmail = gitEmail
    }
}

/// Everything under `path` uses `accountId`, whatever the global account is.
public struct FolderRule: Codable, Identifiable, Hashable {
    public var id: UUID
    public var path: String
    public var accountId: UUID

    public init(id: UUID = UUID(), path: String, accountId: UUID) {
        self.id = id
        self.path = path
        self.accountId = accountId
    }
}

public struct AppConfig: Codable, Equatable {
    public var accounts: [Account] = []
    public var rules: [FolderRule] = []
    public var activeAccountId: UUID?
    /// Overrides gh auto-detection.
    public var ghPath: String?
    /// Set when the user turns the shell integration off, so folder rules don't turn it back on.
    /// Optional so config files written before this existed still decode.
    public var shellIntegrationDisabled: Bool?

    public init() {}

    public var activeAccount: Account? { activeAccountId.flatMap(account) }

    public func account(_ id: UUID) -> Account? {
        accounts.first { $0.id == id }
    }

    /// The most specific rule containing `path` (case-insensitive, like the macOS file system).
    public func rule(forPath path: String) -> FolderRule? {
        let target = Self.normalize(path).lowercased()
        return rules
            .filter { account($0.accountId) != nil }
            .filter { rule in
                let base = Self.normalize(rule.path).lowercased()
                return target == base || target.hasPrefix(base == "/" ? "/" : base + "/")
            }
            .max { Self.normalize($0.path).count < Self.normalize($1.path).count }
    }

    public static func normalize(_ path: String) -> String {
        var p = (path as NSString).expandingTildeInPath
        p = (p as NSString).standardizingPath
        while p.count > 1 && p.hasSuffix("/") { p.removeLast() }
        return p
    }
}

public enum ConfigStore {
    public static func load(_ paths: Paths) -> AppConfig {
        guard let data = try? Data(contentsOf: paths.config),
              let config = try? JSONDecoder().decode(AppConfig.self, from: data)
        else { return AppConfig() }
        return config
    }

    public static func save(_ config: AppConfig, _ paths: Paths) throws {
        try FileManager.default.createDirectory(at: paths.dir, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: paths.config, options: .atomic)
    }
}
