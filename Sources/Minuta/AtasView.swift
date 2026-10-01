import AppKit
import SwiftUI

/// The "Atas…" window: recordings still being processed on top, then the minutes by date and title.
@MainActor
final class AtasWindowController {
    static let shared = AtasWindowController()
    private var window: NSWindow?

    func show() {
        AtaLibrary.shared.refresh()
        if window == nil { window = makeWindow() }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        let host = NSHostingController(rootView: AtasView())
        host.sizingOptions = []
        let window = ClosableWindow(contentViewController: host)
        window.title = "Atas"
        window.styleMask = [.titled, .closable, .resizable]
        window.setContentSize(NSSize(width: 680, height: 440))
        window.contentMinSize = NSSize(width: 560, height: 280)
        window.isReleasedWhenClosed = false
        window.center()
        window.setFrameAutosaveName("AtasWindow")
        return window
    }
}

struct AtasView: View {
    @ObservedObject private var library = AtaLibrary.shared
    @ObservedObject private var model = AppModel.shared

    var body: some View {
        VStack(spacing: 0) {
            if library.folder != .ok { FolderBanner(state: library.folder) }
            if library.atas.isEmpty && library.pending.isEmpty {
                VStack(spacing: 6) {
                    Text("Nenhuma ata ainda").font(.headline)
                    Text("Grave uma reunião e a ata aparece aqui.").foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    if !library.pending.isEmpty {
                        Section("Em andamento") {
                            ForEach(library.pending) { job in
                                PendingRow(job: job, running: model.runningJobs.contains(job.id))
                            }
                        }
                    }
                    if library.pending.isEmpty {
                        ForEach(library.atas) { ata in AtaRow(ata: ata) }
                    } else if !library.atas.isEmpty {
                        Section("Atas") {
                            ForEach(library.atas) { ata in AtaRow(ata: ata) }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .frame(minWidth: 560, minHeight: 280)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            library.refresh()
        }
    }
}

/// Shown above the list when the output folder is gone or cannot be read.
private struct FolderBanner: View {
    let state: FolderState

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle").font(.title3).foregroundStyle(.red)
            VStack(alignment: .leading, spacing: 2) {
                Text(state == .missing ? "A pasta de atas não foi encontrada" : "Não foi possível ler a pasta de atas")
                    .fontWeight(.medium)
                Text((Config.outputDir.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 8)
            Button("Escolher outra pasta…") {
                if Config.chooseOutputFolder() { AtaLibrary.shared.refresh() }
            }
            .controlSize(.small)
            if state == .missing {
                Button("Recriar pasta") { AtaLibrary.shared.recreateFolder() }.controlSize(.small)
            } else {
                Button("Tentar de novo") { AtaLibrary.shared.refresh() }.controlSize(.small)
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.red.opacity(0.35), lineWidth: 0.5))
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct AtaRow: View {
    let ata: Ata

    var body: some View {
        HStack(spacing: 10) {
            Text(Fmt.listDate(ata.start)).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            HStack(spacing: 6) {
                if ata.problem != nil {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                }
                Text(ata.title).lineLimit(1).truncationMode(.tail)
            }
            Spacer(minLength: 8)
            if let problem = ata.problem {
                Text(problem.label).font(.caption).foregroundStyle(.red)
            } else {
                Text(ata.duration.map(Fmt.shortDuration) ?? "").foregroundStyle(.secondary)
                    .frame(width: 56, alignment: .trailing)
            }
            if ata.problem?.canOpen ?? true {
                Button("Abrir") { AtaViewerController.shared.open(ata.url) }.controlSize(.small)
            } else {
                Button("Mostrar no Finder") { NSWorkspace.shared.activateFileViewerSelecting([ata.url]) }
                    .controlSize(.small)
            }
            Button {
                trash()
            } label: {
                Image(systemName: "trash")
            }
            .controlSize(.small)
            .help("Apagar")
            .accessibilityLabel("Apagar ata")
        }
        .padding(.vertical, 3)
    }

    private func trash() {
        let choice = Alerts.show(
            title: "Mover a ata para a Lixeira?",
            message: "“\(ata.title)” será movida para a Lixeira. Você pode recuperá-la de lá.",
            buttons: ["Cancelar", "Mover para a Lixeira"], destructive: 1)
        guard choice == 1 else { return }
        do {
            try AtaLibrary.shared.trash(ata)
            AtaViewerController.shared.close(ata.url)
        } catch {
            Alerts.show(
                title: "Não foi possível mover a ata", message: AppError.from(error).message, buttons: ["OK"])
        }
    }
}

private struct PendingRow: View {
    let job: Job
    let running: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(Fmt.listDate(job.startedAt)).foregroundStyle(.secondary).frame(width: 120, alignment: .leading)
            status
            Spacer(minLength: 8)
            Text(Fmt.shortDuration(job.durationSeconds)).foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            if !running {
                Button("Tentar de novo") { AppModel.shared.run(job) }.controlSize(.small)
                Button("Descartar") { discard() }.controlSize(.small)
            }
        }
        .padding(.vertical, 3)
    }

    @ViewBuilder private var status: some View {
        if running {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(job.stage == .minuting ? "Gerando a ata…" : "Transcrevendo…").foregroundStyle(.secondary)
            }
        } else if let error = job.lastError {
            Text("Falhou: \(error)").foregroundStyle(.red).lineLimit(1).truncationMode(.tail).help(error)
        } else {
            Text("Interrompida").foregroundStyle(.secondary)
        }
    }

    private func discard() {
        let choice = Alerts.show(
            title: "Descartar a gravação?",
            message: "A gravação de \(Fmt.listDate(job.startedAt)) será apagada e não poderá ser recuperada.",
            buttons: ["Cancelar", "Descartar"], destructive: 1)
        if choice == 1 { AtaLibrary.shared.discard(job) }
    }
}
