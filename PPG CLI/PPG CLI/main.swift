import AppKit

let config = LaunchConfig.parse(CommandLine.arguments)
LaunchConfig.shared = config
ProjectState.shared.loadFromLaunchConfig(config)

let app = NSApplication.shared
let delegate = AppDelegate()
MainActor.assumeIsolated {
    app.delegate = delegate
}
app.run()
