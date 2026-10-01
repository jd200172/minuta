import AppKit

@MainActor
enum Alerts {
    /// Shows a modal alert and returns the index of the button the user pressed.
    static func show(title: String, message: String, buttons: [String], destructive: Int? = nil) -> Int {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        for (index, name) in buttons.enumerated() {
            let button = alert.addButton(withTitle: name)
            if index == destructive { button.hasDestructiveAction = true }
        }
        return alert.runModal().rawValue - NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
    }
}

enum SettingsOpener {
    @MainActor
    static func open() {
        SettingsWindowController.shared.show()
    }
}
