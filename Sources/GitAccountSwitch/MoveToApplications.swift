import AppKit
import GitAccountSwitchCore

/// A downloaded app opened outside Applications runs from a temporary, read-only copy
/// (App Translocation) that disappears on quit. git's credential helper can't point there,
/// so offer to move the app into Applications and relaunch it from there.
@MainActor
enum MoveToApplications {
    static var isTranslocated: Bool { Bundle.main.bundlePath.contains("/AppTranslocation/") }

    /// Replaces an existing install wherever it is; otherwise /Applications, or ~/Applications
    /// when /Applications isn't writable.
    static var destination: URL {
        let name = Bundle.main.bundleURL.lastPathComponent
        let system = URL(fileURLWithPath: "/Applications").appendingPathComponent(name)
        let user = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Applications").appendingPathComponent(name)
        let fm = FileManager.default
        if fm.fileExists(atPath: system.path) { return system }
        if fm.fileExists(atPath: user.path) { return user }
        return fm.isWritableFile(atPath: "/Applications") ? system : user
    }

    static func offer(onDecline: () -> Void) {
        let dest = destination
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = "Move GitAccountSwitch to Applications?"
        alert.informativeText = """
            It's running from a temporary location macOS uses for downloaded apps. Git can only \
            use it from a permanent place, so it needs to be in \
            \((dest.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath).

            You can delete the copy in Downloads afterwards.
            """
        alert.addButton(withTitle: "Move to Applications")
        alert.addButton(withTitle: "Not Now")
        guard alert.runModal() == .alertFirstButtonReturn else { return onDecline() }

        do {
            try install(at: dest)
        } catch {
            let failed = NSAlert()
            failed.messageText = "Couldn't move the app"
            failed.informativeText = "\(error.localizedDescription)\n\nDrag GitAccountSwitch into your Applications folder in Finder, then open it from there."
            failed.runModal()
            return onDecline()
        }

        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: dest, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private static func install(at dest: URL) throws {
        let fm = FileManager.default
        // An older copy may be running from the destination; it has to go before it's replaced.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        where app != NSRunningApplication.current {
            app.terminate()
        }
        try fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
        try fm.copyItem(at: Bundle.main.bundleURL, to: dest)
        // The user already approved this download; without the quarantine flag the copy isn't
        // translocated again.
        Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dest.path])
    }
}
