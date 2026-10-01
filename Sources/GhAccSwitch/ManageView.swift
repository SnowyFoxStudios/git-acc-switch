import AppKit
import GhAccSwitchCore
import SwiftUI

struct ManageView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        TabView {
            AccountsTab().tabItem { Label("Accounts", systemImage: "person.2") }
            FoldersTab().tabItem { Label("Folders", systemImage: "folder") }
            SetupTab().tabItem { Label("Setup", systemImage: "gearshape") }
        }
        .padding()
        .alert(
            "Something went wrong",
            isPresented: Binding(get: { state.lastError != nil }, set: { if !$0 { state.lastError = nil } })
        ) {
            Button("OK") { state.lastError = nil }
        } message: {
            Text(state.lastError ?? "")
        }
    }
}

// MARK: - Accounts

private struct AccountsTab: View {
    @EnvironmentObject var state: AppState
    @State private var editing: Account?
    @State private var adding = false
    @State private var removing: Account?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if state.config.accounts.isEmpty {
                ContentUnavailableView(
                    "No accounts yet",
                    systemImage: "person.crop.circle.badge.plus",
                    description: Text("Add a GitHub account: sign in once in the browser, then switch with one click.")
                )
            } else {
                List {
                    ForEach(state.config.accounts) { account in
                        AccountRow(account: account, onEdit: { editing = account }, onRemove: { removing = account })
                    }
                }
            }
            HStack {
                Button {
                    adding = true
                } label: {
                    Label("Add Account…", systemImage: "plus")
                }
                Spacer()
                if !state.importableLogins.isEmpty {
                    Text("\(state.importableLogins.count) gh login(s) not added yet")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .sheet(isPresented: $adding) { AddAccountSheet() }
        .sheet(item: $editing) { account in AccountEditor(account: account, isNew: false) }
        .confirmationDialog(
            "Remove \(removing?.label ?? "account")?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            presenting: removing
        ) { account in
            Button("Remove from this app") { state.remove(account, logOut: false) }
            Button("Remove and log out of gh", role: .destructive) { state.remove(account, logOut: true) }
        } message: { account in
            Text("Folder rules that use @\(account.login) are removed too.")
        }
    }
}

private struct AccountRow: View {
    @EnvironmentObject var state: AppState
    let account: Account
    let onEdit: () -> Void
    let onRemove: () -> Void

    var body: some View {
        let isActive = state.config.activeAccountId == account.id
        HStack(spacing: 12) {
            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(isActive ? Color.accentColor : .secondary)
                .font(.title3)
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(account.label).font(.headline)
                    Text("@\(account.login)").foregroundStyle(.secondary)
                    if account.host != "github.com" {
                        Text(account.host).font(.caption).foregroundStyle(.secondary)
                    }
                }
                Text("\(account.gitName) <\(account.gitEmail)>")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                if !state.isLoggedIn(account) {
                    Label("Not logged in to gh. Remove and add it again to log in.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer()
            if !isActive {
                Button("Make Global") { state.activate(account) }
            }
            Button("Edit", action: onEdit)
            Button(role: .destructive, action: onRemove) { Image(systemName: "trash") }
                .help("Remove account")
        }
        .padding(.vertical, 4)
    }
}

/// Step 1: pick a login (sign in via the browser, or import one gh already has). Step 2: the editor.
private struct AddAccountSheet: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @StateObject private var session = LoginSession()
    @State private var host = "github.com"
    @State private var draft: Account?

    var body: some View {
        if let draft {
            // Re-created when the profile prefill replaces the draft.
            AccountEditor(account: draft, isNew: true, onClose: { dismiss() })
                .id(draft)
        } else {
            VStack(alignment: .leading, spacing: 16) {
                Text("Add a GitHub account").font(.title2.bold())

                if !state.importableLogins.isEmpty {
                    GroupBox("Already logged in to gh") {
                        VStack(alignment: .leading) {
                            ForEach(state.importableLogins, id: \.self) { login in
                                HStack {
                                    Text("@\(login.login)")
                                    Text(login.host).foregroundStyle(.secondary)
                                    Spacer()
                                    Button("Add") { prepare(login: login.login, host: login.host) }
                                }
                            }
                        }
                        .padding(4)
                    }
                }

                GroupBox("Sign in to another account") {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Text("Host")
                            TextField("github.com", text: $host).frame(width: 200)
                        }
                        loginStatus
                        Text("Your browser signs in as whichever GitHub account it's logged in to. To add a different one, switch accounts on github.com first (avatar menu → Switch account) or use a private window.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(4)
                }

                HStack {
                    Spacer()
                    Button("Cancel") {
                        session.cancel()
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
            .frame(width: 520)
            .onChange(of: session.phase) { _, phase in
                if case .done(let login) = phase {
                    state.afterLogin()
                    prepare(login: login, host: host)
                }
            }
        }
    }

    @ViewBuilder private var loginStatus: some View {
        switch session.phase {
        case .idle, .failed:
            if case .failed(let message) = session.phase {
                Text(message).foregroundStyle(.red).font(.callout).textSelection(.enabled)
            }
            Button {
                guard let gh = state.gh else { return state.lastError = "gh CLI not found. Install it with: brew install gh" }
                session.start(gh: gh, host: host.trimmingCharacters(in: .whitespaces), paths: state.paths)
            } label: {
                Label("Sign in with Browser", systemImage: "safari")
            }
        case .starting:
            HStack { ProgressView().controlSize(.small); Text("Starting gh…") }
        case .waiting(let code):
            VStack(alignment: .leading, spacing: 6) {
                Text("Enter this code in the browser (it's on your clipboard):")
                Text(code).font(.system(.title, design: .monospaced).bold()).textSelection(.enabled)
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Waiting for approval…").foregroundStyle(.secondary)
                    Spacer()
                    Button("Open Browser Again") { session.openBrowser() }
                    Button("Cancel") { session.cancel() }
                }
            }
        case .done(let login):
            Text("Signed in as @\(login)")
        }
    }

    private func prepare(login: String, host: String) {
        var account = Account(label: login, login: login, host: host, gitName: login, gitEmail: "")
        draft = account
        guard let gh = state.gh else { return }
        // Prefill name and email from the GitHub profile without blocking the UI.
        Task.detached {
            let user = gh.user(host: host, login: login)
            await MainActor.run {
                guard let user, draft?.id == account.id else { return }
                account.gitName = user.name ?? user.login
                account.gitEmail = user.email ?? user.noreplyEmail
                draft = account
            }
        }
    }
}

private struct AccountEditor: View {
    @EnvironmentObject var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State var account: Account
    let isNew: Bool
    var onClose: (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "Account details" : "Edit \(account.label)").font(.title2.bold())
            Form {
                LabeledContent("GitHub login", value: "@\(account.login) on \(account.host)")
                TextField("Label", text: $account.label, prompt: Text("Personal, Work…"))
                TextField("Commit name", text: $account.gitName)
                TextField("Commit email", text: $account.gitEmail)
            }
            Text("The commit name and email are what git writes into your commits. Leave the email as the noreply address to keep your real one private.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel") { close() }.keyboardShortcut(.cancelAction)
                Button(isNew ? "Add Account" : "Save") {
                    state.upsert(account)
                    close()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(account.label.isEmpty || account.gitName.isEmpty || account.gitEmail.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 520)
    }

    private func close() {
        if let onClose { onClose() } else { dismiss() }
    }
}

// MARK: - Folders

private struct FoldersTab: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Repos inside these folders commit and push as the chosen account, whatever the global account is. Nested folders override their parents.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if state.config.rules.isEmpty {
                ContentUnavailableView("No folder rules", systemImage: "folder.badge.person.crop")
            } else {
                List {
                    ForEach(state.config.rules.sorted { $0.path < $1.path }) { rule in
                        HStack {
                            Image(systemName: "folder")
                            Text((rule.path as NSString).abbreviatingWithTildeInPath)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer()
                            Picker("", selection: Binding(
                                get: { rule.accountId },
                                set: { state.setRule(rule, accountId: $0) }
                            )) {
                                ForEach(state.config.accounts) { account in
                                    Text("\(account.label) (@\(account.login))").tag(account.id)
                                }
                            }
                            .frame(width: 240)
                            Button(role: .destructive) { state.removeRule(rule) } label: { Image(systemName: "trash") }
                        }
                    }
                }
            }

            HStack {
                Button {
                    chooseFolder()
                } label: {
                    Label("Add Folder…", systemImage: "plus")
                }
                .disabled(state.config.accounts.isEmpty)
                Spacer()
                if !state.gitInstalled {
                    Label("Folder rules need git integration (Setup tab).", systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.orange)
                }
            }
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Use Folder"
        panel.message = "Choose a folder. Every git repo inside it uses the account you pick."
        guard panel.runModal() == .OK, let url = panel.url,
              let account = state.config.activeAccount ?? state.config.accounts.first
        else { return }
        state.addRule(path: url.path, accountId: account.id)
    }
}

// MARK: - Setup

private struct SetupTab: View {
    @EnvironmentObject var state: AppState
    @State private var confirmGit = false
    @State private var backupNote: String?

    var body: some View {
        Form {
            Section("GitHub CLI") {
                if let gh = state.gh {
                    LabeledContent("gh", value: gh.path)
                    LabeledContent("Logged-in accounts", value: state.ghLogins.map { "@\($0.login)" }.joined(separator: ", "))
                } else {
                    Text("gh isn't installed. Run `brew install gh`, then reopen this window.")
                        .foregroundStyle(.red)
                }
            }

            Section("Git") {
                LabeledContent("Status", value: state.gitInstalled ? "Installed" : "Not installed")
                Text("Adds an include of ~/.config/gh-acc-switch/gitconfig at the top of ~/.gitconfig. That file sets the global commit identity, makes this app git's credential helper for GitHub, and applies the folder rules. Installing removes the [user] block and gh's credential helper from ~/.gitconfig, after saving a backup next to it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let backupNote {
                    Text(backupNote).font(.callout).textSelection(.enabled)
                }
                if state.gitInstalled {
                    Button("Uninstall Git Integration") { state.uninstallGit() }
                } else {
                    Button("Install Git Integration…") { confirmGit = true }
                        .disabled(state.config.accounts.isEmpty)
                }
            }

            Section("Shell (gh commands per folder)") {
                LabeledContent("Status", value: state.shellInstalled ? "Installed in ~/.zshrc" : "Not installed")
                Text("Adds one line to ~/.zshrc that wraps `gh`, so inside a folder with a rule it runs as that folder's account. It also puts the `gh-acc-switch` command on your PATH. Open a new terminal tab afterwards.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Toggle("Enable shell integration", isOn: Binding(
                    get: { state.shellInstalled },
                    set: { state.setShellIntegration($0) }
                ))
            }

            Section("App") {
                Toggle("Launch at login", isOn: Binding(
                    get: { state.launchAtLogin },
                    set: { state.launchAtLogin = $0 }
                ))
                LabeledContent("Command-line tool", value: state.paths.cliLink.path)
            }
        }
        .formStyle(.grouped)
        .alert("Install git integration?", isPresented: $confirmGit) {
            Button("Install") {
                let backup = state.installGit()
                backupNote = backup.map { "Backup saved to \($0.path)" }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(installMessage)
        }
    }

    private var installMessage: String {
        var text = "~/.gitconfig is backed up first."
        if let user = state.git.hardcodedUser() {
            text += " Its hard-coded user \(user.name) <\(user.email)> will be removed; the global account in this app takes over."
        }
        return text
    }
}
