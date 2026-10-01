import AVFoundation
import AppKit
import CoreGraphics
import ServiceManagement
import SwiftUI

// MARK: - Window

/// The settings window: a standard macOS preferences window with toolbar tabs.
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
        let tabs = PreferencesTabController()
        tabs.tabStyle = .toolbar
        tabs.addTabViewItem(item("Geral", "gearshape", GeneralPane(model: AppModel.shared)))
        tabs.addTabViewItem(item("Chaves de API", "key", KeysPane()))
        tabs.addTabViewItem(item("Permissões", "lock.shield", PermissionsPane(model: AppModel.shared)))
        let window = NSWindow(contentViewController: tabs)
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        return window
    }

    private func item<V: View>(_ label: String, _ symbol: String, _ view: V) -> NSTabViewItem {
        let host = NSHostingController(rootView: view)
        host.sizingOptions = [.preferredContentSize]
        let item = NSTabViewItem(viewController: host)
        item.label = label
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)
        return item
    }
}

/// Keeps the window title in sync with the selected tab, as macOS preferences windows do.
private final class PreferencesTabController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        view.window?.title = tabViewItem?.label ?? ""
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        view.window?.title = tabViewItems[selectedTabViewItemIndex].label
    }
}

private let paneWidth: CGFloat = 640

private func statusLabel(_ text: String, ok: Bool?) -> some View {
    Group {
        switch ok {
        case .some(true):
            Label(text, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
        case .some(false):
            Label(text, systemImage: "xmark.circle.fill").foregroundStyle(.red)
        case .none:
            Label(text, systemImage: "minus.circle").foregroundStyle(.secondary)
        }
    }
}

// MARK: - Geral

struct GeneralPane: View {
    @ObservedObject var model: AppModel
    @AppStorage(Config.userNameKey) private var userName = ""
    @AppStorage(Config.outputDirKey) private var outputDir = ""
    @State private var launchAtLogin = false
    @State private var loginMessage: String?

    var body: some View {
        Form {
            Section {
                TextField("Seu nome", text: $userName, prompt: Text("Eu"))
            } footer: {
                Text("Aparece na ata e na transcrição no lugar de “Eu”.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Section {
                LabeledContent("Pasta das atas") {
                    HStack {
                        Text(outputDir.isEmpty ? Config.outputDir.path : outputDir)
                            .lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                        Button("Escolher…") { chooseFolder() }
                        Button("Abrir") { model.openOutputFolder() }
                    }
                }
            }

            Section {
                Toggle("Abrir ao iniciar o Mac", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
            } footer: {
                if let loginMessage { Text(loginMessage).frame(maxWidth: .infinity, alignment: .leading) }
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth, height: 300)
        .onAppear { refreshLogin() }
    }

    private func refreshLogin() {
        launchAtLogin = SMAppService.mainApp.status == .enabled
        loginMessage = SMAppService.mainApp.status == .requiresApproval
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
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url { outputDir = url.path }
    }
}

// MARK: - Chaves de API

struct KeysPane: View {
    var body: some View {
        Form {
            KeySection(title: "Google (transcrição)", account: Config.googleAccount,
                       linkTitle: "Criar uma chave no Google AI Studio",
                       link: "https://aistudio.google.com/apikey", check: KeyCheck.google)
            KeySection(title: "Anthropic (ata)", account: Config.anthropicAccount,
                       linkTitle: "Criar uma chave no Claude Console",
                       link: "https://platform.claude.com/settings/keys", check: KeyCheck.anthropic)
        }
        .formStyle(.grouped)
        .frame(width: paneWidth, height: 380)
    }
}

private struct KeySection: View {
    let title: String
    let account: String
    let linkTitle: String
    let link: String
    let check: (String) async -> AppError?

    @State private var key = ""
    @State private var saved = false
    @State private var checking = false
    @State private var result: AppError?
    @State private var verified = false
    @State private var saveError: String?

    var body: some View {
        Section {
            SecureField("Chave", text: $key)
                .onSubmit { save() }
            HStack {
                if let saveError {
                    statusLabel(saveError, ok: false)
                } else if checking {
                    Label("Verificando…", systemImage: "hourglass").foregroundStyle(.secondary)
                } else if let result {
                    statusLabel(result.message, ok: false)
                } else if verified {
                    statusLabel("Chave válida", ok: true)
                } else {
                    statusLabel(saved ? "Salva no Keychain" : "Sem chave", ok: saved ? true : nil)
                }
                Spacer()
                Button("Verificar") { verify() }
            }
            .font(.callout)
        } header: {
            Text(title)
        } footer: {
            Link(linkTitle, destination: URL(string: link)!)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear {
            key = Keychain.get(account) ?? ""
            saved = !key.isEmpty
        }
        .onDisappear { save() }
    }

    private func save() {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        key = trimmed
        let status = Keychain.set(trimmed, account: account)
        saveError = status == errSecSuccess ? nil : "Não foi possível salvar: \(Keychain.message(status))"
        saved = Keychain.get(account) != nil
        verified = false
        result = nil
    }

    private func verify() {
        save()
        guard saved else {
            result = AppError("Cole a chave antes de verificar.")
            return
        }
        checking = true
        Task {
            let outcome = await check(key)
            checking = false
            result = outcome
            verified = outcome == nil
        }
    }
}

// MARK: - Permissões

struct PermissionsPane: View {
    @ObservedObject var model: AppModel
    @State private var hasMic = true
    @State private var micStatus = AVAuthorizationStatus.notDetermined
    @State private var screenAllowed = false
    @State private var testing = false
    @State private var testMessage: String?

    var body: some View {
        Form {
            Section {
                LabeledContent("Microfone") {
                    HStack {
                        if !hasMic {
                            Label("Nenhum microfone conectado", systemImage: "mic.slash").foregroundStyle(.secondary)
                        } else {
                            statusLabel(micStatus == .authorized ? "Permitido" : "Não permitido",
                                        ok: micStatus == .authorized)
                            if micStatus != .authorized { Button("Permitir") { requestMic() } }
                        }
                    }
                }
                LabeledContent("Gravação de tela e áudio do sistema") {
                    HStack {
                        statusLabel(screenAllowed ? "Permitido" : "Não permitido", ok: screenAllowed)
                        if !screenAllowed { Button("Permitir") { requestScreen() } }
                    }
                }
            } header: {
                Text("Permissões do macOS")
            } footer: {
                HStack {
                    Text("Depois de permitir a gravação de tela, o macOS pede para reabrir o app.")
                    Spacer()
                    Button("Reabrir o minuta") { relaunch() }
                }
            }

            Section {
                HStack {
                    Button(testing ? "Gravando 5 s…" : "Testar captura") { runTest() }
                        .disabled(testing || model.recordingStart != nil)
                    if let testMessage { Text(testMessage).font(.callout).foregroundStyle(.secondary) }
                }
            } header: {
                Text("Teste de captura")
            } footer: {
                Text("Toque um som no Mac e fale durante o teste. Nada é enviado nem salvo.")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .formStyle(.grouped)
        .frame(width: paneWidth, height: 360)
        .onAppear { refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private func refresh() {
        hasMic = Recorder.hasMicrophone
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        screenAllowed = CGPreflightScreenCaptureAccess()
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
                let mic = !result.hasMicrophone ? "microfone: nenhum encontrado"
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
