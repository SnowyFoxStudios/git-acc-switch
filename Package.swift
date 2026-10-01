// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "GhAccSwitch",
    platforms: [.macOS(.v14)],
    targets: [
        // Everything that isn't UI: config, gh/git plumbing, the CLI and the git credential helper.
        .target(name: "GhAccSwitchCore", path: "Sources/GhAccSwitchCore"),
        // The menu bar app. The same binary also runs as the CLI when given a command.
        .executableTarget(
            name: "GhAccSwitch",
            dependencies: ["GhAccSwitchCore"],
            path: "Sources/GhAccSwitch"
        ),
    ]
)
