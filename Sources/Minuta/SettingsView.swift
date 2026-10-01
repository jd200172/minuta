import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI

struct SettingsView: View {
    @AppStorage(Config.userNameKey) private var userName = ""
    @AppStorage(Config.outputDirKey) private var outputDir = ""
    @State private var googleKey = ""
    @State private var anthropicKey = ""
    @State private var micAllowed = false
    @State private var screenAllowed = false

    var body: some View {
        Form {
            TextField("Seu nome", text: $userName, prompt: Text("Eu"))
            SecureField("Chave da API do Google (transcrição)", text: $googleKey)
            SecureField("Chave da API da Anthropic (ata)", text: $anthropicKey)
            Text("As chaves ficam no Keychain do macOS.").font(.caption).foregroundStyle(.secondary)

            HStack {
                TextField("Pasta das atas", text: $outputDir, prompt: Text(Config.outputDir.path))
                Button("Escolher") { chooseFolder() }
            }

            Divider()
            LabeledContent("Microfone") {
                Text(micAllowed ? "Permitido" : "Não permitido")
                if !micAllowed { Button("Abrir Ajustes") { open("Privacy_Microphone") } }
            }
            LabeledContent("Gravação de tela e áudio do sistema") {
                Text(screenAllowed ? "Permitido" : "Não permitido")
                if !screenAllowed { Button("Abrir Ajustes") { open("Privacy_ScreenCapture") } }
            }

            HStack {
                Spacer()
                Button("Salvar") {
                    Keychain.set(googleKey, account: Config.googleAccount)
                    Keychain.set(anthropicKey, account: Config.anthropicAccount)
                }
            }
        }
        .padding(20)
        .frame(width: 520)
        .onAppear {
            googleKey = Keychain.get(Config.googleAccount) ?? ""
            anthropicKey = Keychain.get(Config.anthropicAccount) ?? ""
            micAllowed = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
            screenAllowed = CGPreflightScreenCaptureAccess()
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { outputDir = url.path }
    }

    private func open(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }
}
