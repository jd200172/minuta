import AppKit

@MainActor
enum Alerts {
    /// Shows a modal alert and returns the index of the button the user pressed.
    /// Esc answers with the button at `escape` (the safe one), since NSAlert only maps Esc to a button named "Cancel".
    @discardableResult
    static func show(
        title: String, message: String, buttons: [String], destructive: Int? = nil, escape: Int = 0
    ) -> Int {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = title
        alert.informativeText = message
        for (index, name) in buttons.enumerated() {
            let button = alert.addButton(withTitle: name)
            if index == destructive { button.hasDestructiveAction = true }
        }
        let first = NSApplication.ModalResponse.alertFirstButtonReturn.rawValue
        let monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard event.keyCode == 53 else { return event }
            NSApp.stopModal(withCode: NSApplication.ModalResponse(rawValue: first + escape))
            return nil
        }
        defer { if let monitor { NSEvent.removeMonitor(monitor) } }
        return alert.runModal().rawValue - first
    }
}

enum SettingsOpener {
    @MainActor
    static func open() {
        SettingsWindowController.shared.show()
    }
}
