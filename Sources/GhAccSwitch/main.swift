import Foundation
import GhAccSwitchCore

// One binary, two modes: given a CLI command (or run through the `gh-acc-switch` symlink),
// it acts as the CLI and git credential helper; otherwise it launches the menu bar app.
let args = Array(CommandLine.arguments.dropFirst())
let invokedAs = URL(fileURLWithPath: CommandLine.arguments[0]).lastPathComponent

if invokedAs == "gh-acc-switch" || args.first.map(CLI.commands.contains) == true {
    exit(CLI.run(args))
}

GhAccSwitchApp.main()
