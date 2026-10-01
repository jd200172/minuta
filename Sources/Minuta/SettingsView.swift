import AVFoundation
import AppKit
import CoreGraphics
import ServiceManagement
import SwiftUI

// MARK: - Window

/// The settings window: one page with three blocks (keys, permissions, preferences).
@MainActor
final class SettingsWindowController {
    static let shared = SettingsWindowController()
    private var window: NSWindow?

    func show() {
        if window == nil { window = makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let window = ClosableWindow(contentViewController: NSHostingController(rootView: SettingsView()))
        window.title = "Configurações"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }
}

private let pageWidth: CGFloat = 640
private let pageHeight: CGFloat = 490

// MARK: - Page

struct SettingsView: View {
    @ObservedObject private var model = AppModel.shared
    @AppStorage(Config.userNameKey) private var userName = ""
    @AppStorage(Config.outputDirKey) private var outputDir = ""
    @State private var launchAtLogin = false
    @State private var loginMessage: String?
    @State private var hasMic = true
    @State private var micStatus = AVAuthorizationStatus.notDetermined
    @State private var screenAllowed = false
    @State private var startedWithoutScreen: Bool?
    @State private var testing = false
    @State private var testMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Chaves e modelos de IA") {
                    LabeledContent("Arquivo de chaves") {
                        Button("Abrir arquivo…") { Env.open() }
                    }
                }

                Section("Permissões") {
                    LabeledContent("Microfone") { microphoneStatus }
                    LabeledContent("Gravação de tela e áudio do sistema") {
                        HStack {
                            if screenAllowed {
                                Text("Permitido").foregroundStyle(.secondary)
                            } else {
                                Text("Não permitido").foregroundStyle(.red)
                                Button("Permitir") { requestScreen() }.buttonStyle(.borderedProminent)
                            }
                        }
                    }
                    if screenAllowed, startedWithoutScreen == true {
                        LabeledContent("Reabrir o minuta") {
                            Button("Reabrir") { relaunch() }
                        }
                    }
                    LabeledContent("Teste de captura") {
                        Button(testing ? "Gravando 5 s…" : "Testar captura") { runTest() }
                            .disabled(testing || model.recordingStart != nil)
                    }
                    if let testMessage {
                        Text(testMessage).font(.callout).foregroundStyle(.secondary)
                    }
                }

                Section("Preferências") {
                    TextField("Seu nome", text: $userName, prompt: Text("Eu"))
                        .multilineTextAlignment(.trailing)
                    LabeledContent("Pasta das atas") {
                        HStack {
                            Text(
                                ((outputDir.isEmpty ? Config.outputDir.path : outputDir) as NSString)
                                    .abbreviatingWithTildeInPath
                            )
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                            .frame(maxWidth: 280, alignment: .trailing)
                            Button("Escolher…") { chooseFolder() }
                        }
                    }
                    Toggle("Abrir ao iniciar o Mac", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                    if let loginMessage {
                        Text(loginMessage).font(.callout).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)

            Text(AppVersion.text)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 20)
                .padding(.top, 4)
                .padding(.bottom, 12)
        }
        .frame(width: pageWidth, height: pageHeight)
        .onAppear {
            refresh()
            refreshLogin()
            if startedWithoutScreen == nil { startedWithoutScreen = !screenAllowed }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    @ViewBuilder private var microphoneStatus: some View {
        if !hasMic {
            Text("Nenhum microfone conectado").foregroundStyle(.secondary)
        } else if micStatus == .authorized {
            Text("Permitido").foregroundStyle(.secondary)
        } else {
            HStack {
                Text("Não permitido").foregroundStyle(.red)
                Button("Permitir") { requestMic() }.buttonStyle(.borderedProminent)
            }
        }
    }

    // MARK: Actions

    private func refresh() {
        hasMic = Recorder.hasMicrophone
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        screenAllowed = CGPreflightScreenCaptureAccess()
    }

    private func refreshLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        loginMessage =
            SMAppService.mainApp.status == .requiresApproval
            ? "Aprove o minuta em Ajustes do Sistema > Geral > Itens de Início." : nil
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            refreshLogin()
        } catch {
            refreshLogin()
            loginMessage = "Não foi possível alterar: \(error.localizedDescription)"
        }
    }

    private func chooseFolder() {
        if Config.chooseOutputFolder() { AtaLibrary.shared.refresh() }
    }

    private func requestMic() {
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            Task {
                _ = await AVCaptureDevice.requestAccess(for: .audio)
                refresh()
            }
        } else {
            openPane("Privacy_Microphone")
        }
    }

    /// The app only shows up in the Screen Recording list after it asks for access.
    private func requestScreen() {
        CGRequestScreenCaptureAccess()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
            refresh()
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
                let mic =
                    !result.hasMicrophone
                    ? "microfone: nenhum encontrado"
                    : (result.micHasSignal ? "microfone: som detectado" : "microfone: silêncio")
                let system = result.systemHasSignal ? "áudio do sistema: som detectado" : "áudio do sistema: silêncio"
                testMessage = "\(mic); \(system)"
            } catch {
                testMessage = AppError.from(error).message
            }
            testing = false
            refresh()
        }
    }
}
