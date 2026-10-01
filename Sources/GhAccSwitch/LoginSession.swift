import AppKit
import Foundation
import GhAccSwitchCore

/// Runs `gh auth login --web` in the background: shows the one-time code, copies it,
/// opens the browser, and waits for the user to approve. The token lands in gh's keychain.
@MainActor
final class LoginSession: ObservableObject {
    enum Phase: Equatable {
        case idle
        case starting
        case waiting(code: String)
        case done(login: String)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    private var process: Process?
    private var output = ""
    private var deviceURL: URL?

    func start(gh: GH, host: String, paths: Paths) {
        cancel()
        output = ""
        phase = .starting
        // gh makes the new account active; remember who was active so we can switch back.
        let previous = HostsFile.read(paths).first { $0.host == host && $0.active }?.login

        let p = Process()
        p.executableURL = URL(fileURLWithPath: gh.path)
        p.arguments = ["auth", "login", "--hostname", host, "--git-protocol", "https", "--web", "--skip-ssh-key"]
        var env = ProcessInfo.processInfo.environment
        for key in ["GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"] {
            env.removeValue(forKey: key)
        }
        env["BROWSER"] = "true"  // we open the browser ourselves, after copying the code
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        p.standardInput = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let text = String(decoding: data, as: UTF8.self)
            Task { @MainActor in self?.received(text, host: host) }
        }
        p.terminationHandler = { [weak self] proc in
            pipe.fileHandleForReading.readabilityHandler = nil
            let status = proc.terminationStatus
            Task { @MainActor in self?.finished(status: status, gh: gh, host: host, previous: previous, paths: paths) }
        }

        do {
            try p.run()
            process = p
        } catch {
            phase = .failed("Couldn't run gh: \(error.localizedDescription)")
        }
    }

    func cancel() {
        if let process, process.isRunning { process.terminate() }
        process = nil
        phase = .idle
    }

    func openBrowser() {
        if let deviceURL { NSWorkspace.shared.open(deviceURL) }
    }

    private func received(_ text: String, host: String) {
        output += text
        guard case .starting = phase,
              let code = output.firstMatch(of: #/one-time code: ([A-Z0-9]{4}-[A-Z0-9]{4})/#)?.1
        else { return }
        let url = output.firstMatch(of: #/https://\S+/login/device/#).map { String($0.0) }
        deviceURL = url.flatMap(URL.init(string:)) ?? GH.deviceURL(host: host)

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(String(code), forType: .string)
        phase = .waiting(code: String(code))
        openBrowser()
    }

    private func finished(status: Int32, gh: GH, host: String, previous: String?, paths: Paths) {
        process = nil
        guard phase != .idle else { return }  // cancelled
        guard status == 0, let login = HostsFile.read(paths).first(where: { $0.host == host && $0.active })?.login
        else {
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            phase = .failed(detail.isEmpty ? "gh auth login exited with status \(status)" : detail)
            return
        }
        if let previous, previous != login {
            try? gh.switchTo(host: host, login: previous)
        }
        phase = .done(login: login)
    }
}
