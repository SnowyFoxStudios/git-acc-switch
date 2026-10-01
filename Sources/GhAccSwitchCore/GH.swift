import Foundation

public struct GhLogin: Hashable {
    public let host: String
    public let login: String
    public let active: Bool

    public init(host: String, login: String, active: Bool) {
        self.host = host
        self.login = login
        self.active = active
    }
}

public struct GhUser {
    public let id: Int
    public let login: String
    public let name: String?
    public let email: String?

    /// GitHub's private commit email, used when the account hides its real one.
    public var noreplyEmail: String { "\(id)+\(login)@users.noreply.github.com" }
}

public struct GHError: LocalizedError {
    public let message: String
    public init(_ message: String) { self.message = message }
    public var errorDescription: String? { message }
}

/// Thin wrapper over the `gh` CLI. Tokens stay in gh's keychain; we only ask for them on demand.
public struct GH {
    public let path: String

    public init(path: String) { self.path = path }

    public static func locate(preferred: String?) -> GH? {
        var candidates: [String] = []
        if let preferred, !preferred.isEmpty { candidates.append(preferred) }
        candidates += ["/opt/homebrew/bin/gh", "/usr/local/bin/gh", "/usr/bin/gh"]
        return Shell.which(candidates).map(GH.init(path:))
    }

    public func switchTo(host: String, login: String) throws {
        let r = Shell.run(path, ["auth", "switch", "--hostname", host, "--user", login])
        if !r.ok { throw GHError(r.err.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    public func token(host: String, login: String) -> String? {
        let r = Shell.run(path, ["auth", "token", "--hostname", host, "--user", login])
        let token = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return r.ok && !token.isEmpty ? token : nil
    }

    public func logout(host: String, login: String) throws {
        let r = Shell.run(path, ["auth", "logout", "--hostname", host, "--user", login])
        if !r.ok { throw GHError(r.err.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    /// Profile of `login`, used to prefill the git name and email.
    public func user(host: String, login: String) -> GhUser? {
        guard let token = token(host: host, login: login) else { return nil }
        let r = Shell.run(
            path, ["api", "user", "--hostname", host],
            env: ["GH_TOKEN": token, "GH_ENTERPRISE_TOKEN": token]
        )
        guard r.ok,
              let obj = try? JSONSerialization.jsonObject(with: Data(r.out.utf8)) as? [String: Any],
              let id = obj["id"] as? Int, let login = obj["login"] as? String
        else { return nil }
        return GhUser(id: id, login: login, name: obj["name"] as? String, email: obj["email"] as? String)
    }

    /// Restores gh as the git credential helper (used when uninstalling).
    public func setupGit() {
        Shell.run(path, ["auth", "setup-git"])
    }

    public static func deviceURL(host: String) -> URL {
        URL(string: "https://\(host)/login/device")!
    }
}

/// Reads gh's hosts.yml directly: offline, instant, and enough to know who is logged in and active.
public enum HostsFile {
    public static func read(_ paths: Paths) -> [GhLogin] {
        guard let text = try? String(contentsOf: paths.ghHostsFile, encoding: .utf8) else { return [] }
        return parse(text)
    }

    public static func parse(_ text: String) -> [GhLogin] {
        var result: [GhLogin] = []
        var host: String?
        var users: [String] = []
        var active: String?
        var inUsers = false

        func flush() {
            guard let host else { return }
            var all = users
            if let active, !all.contains(active) { all.append(active) }
            result += all.map { GhLogin(host: host, login: $0, active: $0 == active) }
        }

        for raw in text.components(separatedBy: .newlines) {
            guard !raw.trimmingCharacters(in: .whitespaces).isEmpty,
                  !raw.trimmingCharacters(in: .whitespaces).hasPrefix("#")
            else { continue }
            let indent = raw.prefix { $0 == " " }.count
            let line = raw.trimmingCharacters(in: .whitespaces)
            let (key, value) = splitKey(line)

            if indent == 0 {
                flush()
                host = key
                users = []
                active = nil
                inUsers = false
            } else if inUsers && indent > 4 {
                users.append(key)
            } else {
                inUsers = key == "users"
                if key == "user", !value.isEmpty { active = value }
            }
        }
        flush()
        return result
    }

    private static func splitKey(_ line: String) -> (String, String) {
        guard let colon = line.firstIndex(of: ":") else { return (unquote(line), "") }
        let key = String(line[..<colon])
        let value = String(line[line.index(after: colon)...]).trimmingCharacters(in: .whitespaces)
        return (unquote(key), unquote(value))
    }

    private static func unquote(_ s: String) -> String {
        var s = s
        if s.count >= 2, let f = s.first, let l = s.last, f == l, f == "\"" || f == "'" {
            s = String(s.dropFirst().dropLast())
        }
        return s
    }
}
