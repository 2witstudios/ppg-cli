import AppKit

let config = LaunchConfig.parse(CommandLine.arguments)
LaunchConfig.shared = config

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
