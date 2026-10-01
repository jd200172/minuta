import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Opening the app again while it is running (Spotlight, Applications) shows the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        Task { @MainActor in SettingsOpener.open() }
        return true
    }
}

@main
struct MinutaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel.shared

    init() {
        if CLI.requested() {
            Task {
                let code = await CLI.run()
                exit(code)
            }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.iconName)
        }
    }
}
