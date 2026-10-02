import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The developer CLI mode runs headless: no status item, no pending-recording prompts.
        guard !CLI.requested() else { return }
        MainActor.assumeIsolated {
            statusItem = StatusItemController(model: AppModel.shared)
            AudioArchive.migrateLegacy(from: Config.legacyAudioDir, to: Config.audioDir)
            AtaLibrary.shared.refresh()
        }
    }

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
