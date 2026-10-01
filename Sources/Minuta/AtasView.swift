import AppKit
import SwiftUI

/// The "Atas…" window: recordings still being processed on top, then a table of the minutes with sortable
/// columns (data, título, resumo, duração). Double click or Return opens an ata; the pencil renames it in place.
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
    @ObservedObject private var summaries = SummaryService.shared
    @State private var sortOrder = [KeyPathComparator(\Ata.start, order: .reverse)]
    @State private var selection: Ata.ID?
    @State private var renamingID: Ata.ID?
    @State private var draft = ""
    @FocusState private var focusedID: Ata.ID?

    private var rows: [Ata] { library.atas.sorted(using: sortOrder) }

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
                if !library.pending.isEmpty { pendingBlock }
                if !library.atas.isEmpty {
                    if !library.pending.isEmpty {
                        Text("Atas").font(.subheadline).foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
                    }
                    table
                } else {
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(minWidth: 560, minHeight: 280)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            library.refresh()
        }
    }

    // MARK: Pending

    private var pendingBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Em andamento").font(.subheadline).foregroundStyle(.secondary)
                .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 4)
            ForEach(library.pending) { job in
                PendingRow(job: job, running: model.runningJobs.contains(job.id))
                    .padding(.horizontal, 16)
            }
        }
    }

    // MARK: Table

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Data", value: \.start) { ata in
                Text(Fmt.listDate(ata.start)).foregroundStyle(.secondary)
            }
            .width(min: 110, ideal: 124, max: 150)
            TableColumn("Título", value: \.title) { ata in
                titleCell(ata)
            }
            .width(min: 160, ideal: 280)
            TableColumn("Resumo", value: \.summaryLabel) { ata in
                SummaryCell(ata: ata, generating: summaries.running[ata.url])
            }
            .width(min: 110, ideal: 140, max: 190)
            TableColumn("Duração", value: \.durationSeconds) { ata in
                Text(ata.duration.map(Fmt.shortDuration) ?? "—").foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 56, ideal: 64, max: 80)
            TableColumn("") { ata in
                actions(ata)
            }
            .width(52)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: Ata.ID.self) { ids in
            if let ata = rows.first(where: { ids.contains($0.id) }) { menu(for: ata) }
        } primaryAction: { ids in
            if let ata = rows.first(where: { ids.contains($0.id) }) { open(ata) }
        }
    }

    @ViewBuilder private func titleCell(_ ata: Ata) -> some View {
        if renamingID == ata.id {
            TextField("Título da reunião", text: $draft)
                .textFieldStyle(.roundedBorder)
                .focused($focusedID, equals: ata.id)
                .onSubmit { commitRename(ata) }
                .onExitCommand { renamingID = nil }
                .onChange(of: focusedID) { focus in
                    if focus != ata.id, renamingID == ata.id { commitRename(ata) }
                }
        } else {
            HStack(spacing: 6) {
                if ata.problem != nil {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
                }
                Text(ata.title).lineLimit(1).truncationMode(.tail)
            }
        }
    }

    @ViewBuilder private func actions(_ ata: Ata) -> some View {
        if renamingID == ata.id {
            EmptyView()
        } else {
            HStack(spacing: 10) {
                if ata.problem == nil {
                    let busy = summaries.running[ata.url] != nil
                    Button {
                        beginRename(ata)
                    } label: {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)
                    .disabled(busy)
                    .help(busy ? "Aguarde o resumo terminar" : "Renomear")
                    .accessibilityLabel("Renomear ata")
                } else if !(ata.problem?.canOpen ?? true) {
                    Button {
                        reveal(ata)
                    } label: {
                        Image(systemName: "folder")
                    }
                    .buttonStyle(.borderless)
                    .help("Mostrar no Finder")
                    .accessibilityLabel("Mostrar no Finder")
                }
                Button {
                    trash(ata)
                } label: {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help("Mover para a Lixeira")
                .accessibilityLabel("Mover a ata para a Lixeira")
            }
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
    }

    @ViewBuilder private func menu(for ata: Ata) -> some View {
        Button("Abrir") { open(ata) }.disabled(!(ata.problem?.canOpen ?? true))
        Button("Renomear") { beginRename(ata) }
            .disabled(ata.problem != nil || summaries.running[ata.url] != nil)
        Divider()
        Button("Mostrar no Finder") { reveal(ata) }
        Divider()
        Button("Mover para a Lixeira") { trash(ata) }
    }

    // MARK: Actions

    private func open(_ ata: Ata) {
        guard ata.problem?.canOpen ?? true else { return }
        AtaViewerController.shared.open(ata.url)
    }

    private func reveal(_ ata: Ata) {
        NSWorkspace.shared.activateFileViewerSelecting([ata.url])
    }

    private func beginRename(_ ata: Ata) {
        guard ata.problem == nil, summaries.running[ata.url] == nil else { return }
        selection = ata.id
        draft = ata.title == MinutesRenderer.untitled ? "" : ata.title
        renamingID = ata.id
        DispatchQueue.main.async { focusedID = ata.id }
    }

    private func commitRename(_ ata: Ata) {
        guard renamingID == ata.id else { return }
        renamingID = nil
        let title = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        let current = ata.title == MinutesRenderer.untitled ? "" : ata.title
        guard title != current else { return }
        guard title.count <= TitleRename.maxLength else {
            Alerts.show(
                title: "Título longo demais", message: "Use no máximo \(TitleRename.maxLength) caracteres.",
                buttons: ["OK"])
            return
        }
        do {
            try library.rename(ata, to: title)
        } catch {
            Alerts.show(
                title: "Não foi possível renomear", message: AppError.from(error).message, buttons: ["OK"])
        }
    }

    private func trash(_ ata: Ata) {
        let choice = Alerts.show(
            title: "Mover a ata para a Lixeira?",
            message: "“\(ata.title)” será movida para a Lixeira. Você pode recuperá-la de lá.",
            buttons: ["Cancelar", "Mover para a Lixeira"], destructive: 1)
        guard choice == 1 else { return }
        do {
            try library.trash(ata)
            AtaViewerController.shared.close(ata.url)
        } catch {
            Alerts.show(
                title: "Não foi possível mover a ata", message: AppError.from(error).message, buttons: ["OK"])
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

/// The "Resumo" column: the model, "Sem resumo", a generation in progress or what is wrong with the file.
private struct SummaryCell: View {
    let ata: Ata
    let generating: SummaryModel?

    var body: some View {
        if generating != nil {
            HStack(spacing: 5) {
                ProgressView().controlSize(.small)
                Text("Gerando resumo…").font(.caption).foregroundStyle(.secondary)
            }
        } else if let problem = ata.problem {
            Text(problem.label).font(.caption).foregroundStyle(.red)
        } else if let model = ata.model {
            tag(model.title, model.tint)
        } else if ata.noSummary {
            tag("Sem resumo", .orange)
        }
    }

    private func tag(_ text: String, _ color: Color) -> some View {
        Text(text).font(.caption).padding(.horizontal, 7).padding(.vertical, 2)
            .background(color.opacity(0.15), in: Capsule())
            .foregroundStyle(color)
    }
}

private struct PendingRow: View {
    let job: Job
    let running: Bool

    var body: some View {
        HStack(spacing: 12) {
            Text(Fmt.listDate(job.startedAt)).foregroundStyle(.secondary).frame(width: 124, alignment: .leading)
            status
            Spacer(minLength: 8)
            Text(Fmt.shortDuration(job.durationSeconds)).foregroundStyle(.secondary)
                .frame(width: 64, alignment: .trailing)
            HStack(spacing: 10) {
                if !running {
                    Button {
                        AppModel.shared.run(job)
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .help("Tentar de novo")
                    .accessibilityLabel("Tentar de novo")
                    Button {
                        discard()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Descartar a gravação")
                    .accessibilityLabel("Descartar a gravação")
                }
            }
            .foregroundStyle(.secondary)
            .frame(width: 52, alignment: .trailing)
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder private var status: some View {
        if running {
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(job.stage == .minuting ? "Classificando a reunião…" : "Transcrevendo…").foregroundStyle(.secondary)
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

extension SummaryModel {
    /// The color of the model's tag in the list. The tag always carries the name too.
    var tint: Color {
        switch self {
        case .decisao: .blue
        case .acompanhamento: .green
        case .problemas: .purple
        case .informativa, .geral: .gray
        }
    }
}
