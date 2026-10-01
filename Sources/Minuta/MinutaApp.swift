import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    /// Quitting during a recording (running or paused) loses it, so ask first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        MainActor.assumeIsolated {
            guard AppModel.shared.recordingStart != nil else { return .terminateNow }
            let choice = Alerts.show(
                title: "Sair e perder a gravação?",
                message:
                    "Há uma gravação em andamento. Ao sair, ela será perdida. Para guardá-la, encerre a gravação pelo menu.",
                buttons: ["Continuar no minuta", "Sair e perder"], destructive: 1)
            return choice == 1 ? .terminateNow : .terminateCancel
        }
    }

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
            HStack(spacing: 4) {
                Image(systemName: model.iconName)
                if let text = model.elapsedText { Text(text).monospacedDigit() }
            }
        }
    }
}
