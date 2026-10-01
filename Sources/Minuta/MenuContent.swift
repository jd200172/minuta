import AppKit
import SwiftUI

struct MenuContent: View {
    @ObservedObject var model: AppModel

    var body: some View {
        if model.recordingStart != nil {
            Button("Parar gravação") { model.stopRecording() }
        } else {
            Button("Iniciar gravação") { model.startRecording() }
        }

        Divider()
        Button("Abrir pasta de atas") { model.openOutputFolder() }
        Button("Configurações…") { SettingsOpener.open() }
            .keyboardShortcut(",")

        Divider()
        Button("Sair do minuta") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
