import AppKit
import SwiftUI

struct MenuContent: View {
    @ObservedObject var model: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let start = model.recordingStart {
            Text("Gravando desde \(start.formatted(date: .omitted, time: .shortened))")
            Text("Limite: \(Int(Config.maxRecordingSeconds / 60)) min")
            Button("Parar gravação") { model.stopRecording() }
        } else {
            Text("Pronto para gravar")
            Button("Iniciar gravação") { model.startRecording() }
        }

        ForEach(model.jobs) { state in
            Divider()
            if state.running {
                Text(state.job.stage == .transcribing ? "Transcrevendo" : "Gerando a ata")
            } else {
                Text(state.job.stage == .transcribing ? "Falha ao transcrever" : "Falha ao gerar a ata")
                Text(state.job.lastError ?? "")
                Button("Tentar novamente") { model.run(state.job) }
                Button("Descartar gravação") { model.discard(state.job) }
            }
        }

        Divider()
        Button("Abrir pasta de atas") { model.openOutputFolder() }
        Button("Configurações") {
            openWindow(id: "settings")
            NSApp.activate(ignoringOtherApps: true)
        }
        .keyboardShortcut(",")
        Divider()
        Button("Sair do minuta") { NSApplication.shared.terminate(nil) }
            .keyboardShortcut("q")
    }
}
