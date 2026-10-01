import Foundation

public struct RunResult {
    public let status: Int32
    public let out: String
    public let err: String
    public var ok: Bool { status == 0 }
}

public enum Shell {
    /// Runs a program and waits for it. GH_TOKEN / GITHUB_TOKEN are stripped so `gh` always uses
    /// its stored accounts, unless `env` sets them on purpose.
    @discardableResult
    public static func run(
        _ executable: String, _ args: [String], stdin: String? = nil, cwd: String? = nil,
        env: [String: String] = [:]
    ) -> RunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = args
        if let cwd { process.currentDirectoryURL = URL(fileURLWithPath: cwd) }

        var environment = ProcessInfo.processInfo.environment
        for key in ["GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN"] {
            environment.removeValue(forKey: key)
        }
        environment.merge(env) { $1 }
        process.environment = environment

        let outPipe = Pipe(), errPipe = Pipe(), inPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe
        process.standardInput = inPipe

        do {
            try process.run()
        } catch {
            return RunResult(status: -1, out: "", err: "\(executable): \(error.localizedDescription)")
        }
        if let stdin { inPipe.fileHandleForWriting.write(Data(stdin.utf8)) }
        try? inPipe.fileHandleForWriting.close()

        // Drain both pipes concurrently so a chatty stderr can't block stdout.
        var outData = Data(), errData = Data()
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            outData = outPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errData = errPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.wait()
        process.waitUntilExit()

        return RunResult(
            status: process.terminationStatus,
            out: String(decoding: outData, as: UTF8.self),
            err: String(decoding: errData, as: UTF8.self)
        )
    }

    public static func which(_ candidates: [String]) -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    public static var gitPath: String {
        which(["/opt/homebrew/bin/git", "/usr/local/bin/git", "/usr/bin/git"]) ?? "/usr/bin/git"
    }
}
