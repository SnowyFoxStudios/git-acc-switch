import AppKit
import GhAccSwitchCore
import SwiftUI

struct GhAccSwitchApp: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        MenuBarExtra {
            MenuContent().environmentObject(state)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "person.crop.circle")
                Text(state.menuTitle)
            }
        }

        Window("GitHub Accounts", id: "manage") {
            ManageView()
                .environmentObject(state)
                .frame(minWidth: 680, minHeight: 440)
        }
        .windowResizability(.contentMinSize)
    }
}

struct MenuContent: View {
    @EnvironmentObject var state: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if state.config.accounts.isEmpty {
            Text("No accounts yet")
        } else {
            Text("Global account")
            ForEach(state.config.accounts) { account in
                Toggle(isOn: Binding(
                    get: { state.config.activeAccountId == account.id },
                    set: { if $0 { state.activate(account) } }
                )) {
                    Text("\(account.label)  ·  @\(account.login)")
                }
            }
        }

        if !state.config.rules.isEmpty {
            Divider()
            Text("\(state.config.rules.count) folder rule\(state.config.rules.count == 1 ? "" : "s") active")
        }
        if !state.gitInstalled {
            Divider()
            Text("Git integration isn't set up")
        }
        if let error = state.lastError {
            Divider()
            Text("⚠︎ \(error)").lineLimit(3)
        }

        Divider()
        Button("Manage Accounts & Folders…") { showManage() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private func showManage() {
        openWindow(id: "manage")
        NSApp.activate()
    }
}
