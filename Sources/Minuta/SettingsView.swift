import AVFoundation
import AppKit
import CoreGraphics
import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @AppStorage(Config.userNameKey) private var userName = ""
    @AppStorage(Config.outputDirKey) private var outputDir = ""
    @State private var googleKey = ""
    @State private var anthropicKey = ""
    @State private var googleSaved = false
    @State private var anthropicSaved = false
    @State private var saveMessage: String?
    @State private var micStatus = AVAuthorizationStatus.notDetermined
    @State private var screenAllowed = false
    @State private var hasMic = true
    @State private var testing = false
    @State private var testMessage: String?

    var body: some View {
        Form {
            Section("Chaves de API") {
                SecureField("Google (transcrição)", text: $googleKey)
                status(googleSaved)
                SecureField("Anthropic (ata)", text: $anthropicKey)
                status(anthropicSaved)
                HStack {
                    Button("Salvar chaves") { saveKeys() }
                    if let saveMessage { Text(saveMessage).font(.caption).foregroundStyle(.secondary) }
                }
            }

            Section("Preferências") {
                TextField("Seu nome", text: $userName, prompt: Text("Eu"))
                HStack {
                    TextField("Pasta das atas", text: $outputDir, prompt: Text(Config.outputDir.path))
                    Button("Escolher") { chooseFolder() }
                    Button("Abrir") { model.openOutputFolder() }
                }
            }

            Section("Permissões do macOS") {
                LabeledContent("Microfone") {
                    if !hasMic {
                        Text("Nenhum microfone conectado")
                    } else {
                        Text(micStatus == .authorized ? "Permitido" : "Não permitido")
                        if micStatus != .authorized { Button("Permitir") { requestMic() } }
                    }
                }
                LabeledContent("Gravação de tela e áudio do sistema") {
                    Text(screenAllowed ? "Permitido" : "Não permitido")
                    if !screenAllowed { Button("Permitir") { requestScreen() } }
                }
                Text("Depois de permitir a gravação de tela, o macOS pede para reabrir o app.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Reabrir o minuta") { relaunch() }
            }

            Section("Teste de captura") {
                HStack {
                    Button(testing ? "Gravando 5 s..." : "Testar captura") { runTest() }
                        .disabled(testing || model.recordingStart != nil)
                    if let testMessage { Text(testMessage).font(.caption) }
                }
                Text("Toque um som no Mac e fale durante o teste. Nada é enviado nem salvo.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .onAppear { reload() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refreshPermissions()
        }
    }

    private func status(_ saved: Bool) -> some View {
        Text(saved ? "Salva no Keychain." : "Não salva.")
            .font(.caption)
            .foregroundStyle(saved ? Color.green : Color.secondary)
    }

    private func reload() {
        googleKey = Keychain.get(Config.googleAccount) ?? ""
        anthropicKey = Keychain.get(Config.anthropicAccount) ?? ""
        googleSaved = !googleKey.isEmpty
        anthropicSaved = !anthropicKey.isEmpty
        refreshPermissions()
    }

    private func refreshPermissions() {
        hasMic = Recorder.hasMicrophone
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        screenAllowed = CGPreflightScreenCaptureAccess()
    }

    private func saveKeys() {
        let google = googleKey.trimmingCharacters(in: .whitespacesAndNewlines)
        let anthropic = anthropicKey.trimmingCharacters(in: .whitespacesAndNewlines)
        googleKey = google
        anthropicKey = anthropic
        let a = Keychain.set(google, account: Config.googleAccount)
        let b = Keychain.set(anthropic, account: Config.anthropicAccount)
        googleSaved = Keychain.get(Config.googleAccount) != nil
        anthropicSaved = Keychain.get(Config.anthropicAccount) != nil
        if a == errSecSuccess && b == errSecSuccess {
            saveMessage = "Chaves salvas."
        } else {
            saveMessage = "Não foi possível salvar: \(Keychain.message(a == errSecSuccess ? b : a))"
        }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { outputDir = url.path }
    }

    private func requestMic() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                refreshPermissions()
            }
        } else {
            openPane("Privacy_Microphone")
        }
    }

    /// The app only shows up in the Screen Recording list after it asks for access.
    private func requestScreen() {
        CGRequestScreenCaptureAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            refreshPermissions()
            openPane("Privacy_ScreenCapture")
        }
    }

    private func openPane(_ pane: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)") {
            NSWorkspace.shared.open(url)
        }
    }

    private func relaunch() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        task.arguments = ["-n", Bundle.main.bundlePath]
        try? task.run()
        NSApplication.shared.terminate(nil)
    }

    private func runTest() {
        testing = true
        testMessage = nil
        Task {
            do {
                let result = try await CaptureTest.run()
                let mic = !result.hasMicrophone ? "microfone: nenhum encontrado"
                    : (result.micHasSignal ? "microfone: som detectado" : "microfone: silêncio")
                let system = result.systemHasSignal ? "áudio do sistema: som detectado" : "áudio do sistema: silêncio"
                testMessage = "\(mic); \(system)"
            } catch {
                testMessage = error.localizedDescription
            }
            testing = false
            refreshPermissions()
        }
    }
}
