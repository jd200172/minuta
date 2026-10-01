import AppKit

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
if CLI.requested() {
    Task { exit(await CLI.run()) }
}
app.run()
