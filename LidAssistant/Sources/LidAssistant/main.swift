import AppKit

let dryRun = CommandLine.arguments.contains("--dry-run")

let app = NSApplication.shared
let delegate = AppDelegate(dryRun: dryRun)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
