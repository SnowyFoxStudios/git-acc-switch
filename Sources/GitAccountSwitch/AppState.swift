import AppKit
import Foundation
import GitAccountSwitchCore
import ServiceManagement

@MainActor
final class AppState: ObservableObject {
    let paths = Paths()
    @Published private(set) var config = AppConfig()
    @Published private(set) var ghLogins: [GhLogin] = []
    @Published private(set) var gitInstalled = false
    @Published private(set) var shellInstalled = false
    @Published var lastError: String?

    private var timer: Timer?

    var gh: GH? { GH.locate(preferred: config.ghPath) }
    var git: GitIntegration { GitIntegration(paths: paths) }
    var shell: ShellIntegration { ShellIntegration(paths: paths) }

    init() {
        config = ConfigStore.load(paths)
        if let exe = Bundle.main.executablePath {
            attempt { try Writer.linkCLI(executable: exe, paths: paths) }
        }
        attempt { try Writer.apply(config, paths: paths) }
        if shell.isInLegacyLocation { attempt { try shell.install() } }
        enableShellForFolderRules()
        refresh()
        // Cheap local file reads: picks up `gh auth switch` and `gh-acc-switch switch` run from a terminal.
        timer = Timer.scheduledTimer(withTimeInterval: 3, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    var menuTitle: String { config.activeAccount?.label ?? "GitHub" }

    /// Logins gh knows about that aren't set up as accounts yet.
    var importableLogins: [GhLogin] {
        ghLogins.filter { login in
            !config.accounts.contains { $0.login.caseInsensitiveCompare(login.login) == .orderedSame && $0.host == login.host }
        }
    }

    func isLoggedIn(_ account: Account) -> Bool {
        ghLogins.contains { $0.host == account.host && $0.login.caseInsensitiveCompare(account.login) == .orderedSame }
    }

    func refresh() {
        let loaded = ConfigStore.load(paths)
        let logins = HostsFile.read(paths)
        if loaded != config { config = loaded }
        if logins != ghLogins { ghLogins = logins }
        let gitNow = git.isInstalled, shellNow = shell.isInstalled
        if gitNow != gitInstalled { gitInstalled = gitNow }
        if shellNow != shellInstalled { shellInstalled = shellNow }
        adoptGhActiveAccount()
    }

    /// If someone ran `gh auth switch` elsewhere, follow it so git and gh agree.
    private func adoptGhActiveAccount() {
        let host = config.activeAccount?.host ?? "github.com"
        guard let ghActive = ghLogins.first(where: { $0.host == host && $0.active }),
              let match = config.accounts.first(where: {
                  $0.host == host && $0.login.caseInsensitiveCompare(ghActive.login) == .orderedSame
              }),
              match.id != config.activeAccountId
        else { return }
        var updated = config
        updated.activeAccountId = match.id
        save(updated)
    }

    // MARK: - Accounts

    func activate(_ account: Account) {
        guard let gh else { return fail("gh CLI not found. Install it with: brew install gh") }
        do {
            try gh.switchTo(host: account.host, login: account.login)
        } catch {
            return fail("Couldn't switch gh to @\(account.login): \(error.localizedDescription)")
        }
        var updated = config
        updated.activeAccountId = account.id
        save(updated)
    }

    func upsert(_ account: Account) {
        var updated = config
        if let i = updated.accounts.firstIndex(where: { $0.id == account.id }) {
            updated.accounts[i] = account
        } else {
            updated.accounts.append(account)
        }
        save(updated)
        if updated.activeAccountId == nil { activate(account) }
    }

    func remove(_ account: Account, logOut: Bool) {
        if logOut, let gh {
            do { try gh.logout(host: account.host, login: account.login) } catch {
                fail("Couldn't log @\(account.login) out of gh: \(error.localizedDescription)")
            }
        }
        var updated = config
        updated.accounts.removeAll { $0.id == account.id }
        updated.rules.removeAll { $0.accountId == account.id }
        let wasActive = updated.activeAccountId == account.id
        if wasActive { updated.activeAccountId = nil }
        save(updated)
        if wasActive, let next = updated.accounts.first { activate(next) }
    }

    // MARK: - Folder rules

    func addRule(path: String, accountId: UUID) {
        var updated = config
        let normalized = AppConfig.normalize(path)
        if let i = updated.rules.firstIndex(where: { AppConfig.normalize($0.path) == normalized }) {
            updated.rules[i].accountId = accountId
        } else {
            updated.rules.append(FolderRule(path: normalized, accountId: accountId))
        }
        save(updated)
        enableShellForFolderRules()
        refresh()
    }

    func setRule(_ rule: FolderRule, accountId: UUID) {
        var updated = config
        guard let i = updated.rules.firstIndex(where: { $0.id == rule.id }) else { return }
        updated.rules[i].accountId = accountId
        save(updated)
    }

    func removeRule(_ rule: FolderRule) {
        var updated = config
        updated.rules.removeAll { $0.id == rule.id }
        save(updated)
    }

    // MARK: - Integrations

    func installGit() -> URL? {
        var backup: URL?
        attempt { backup = try git.install(config) }
        refresh()
        return backup
    }

    func uninstallGit() {
        attempt { try git.uninstall(restoring: config.activeAccount, gh: gh) }
        refresh()
    }

    func setShellIntegration(_ on: Bool) {
        attempt { on ? try shell.install() : try shell.uninstall() }
        var updated = config
        updated.shellIntegrationDisabled = on ? nil : true
        save(updated)
        refresh()
    }

    /// Folder rules only reach `gh` through the shell wrapper, so turn it on with the first rule
    /// unless the user switched it off.
    private func enableShellForFolderRules() {
        guard !config.rules.isEmpty, config.shellIntegrationDisabled != true, !shell.isInstalled else { return }
        attempt { try shell.install() }
    }

    func afterLogin() {
        git.repair(config)
        refresh()
    }

    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            attempt { newValue ? try SMAppService.mainApp.register() : try SMAppService.mainApp.unregister() }
            objectWillChange.send()
        }
    }

    // MARK: - Helpers

    private func save(_ updated: AppConfig) {
        attempt { try Writer.apply(updated, paths: paths) }
        config = updated
    }

    private func attempt(_ body: () throws -> Void) {
        do { try body() } catch { fail(error.localizedDescription) }
    }

    private func fail(_ message: String) {
        lastError = message
    }
}
