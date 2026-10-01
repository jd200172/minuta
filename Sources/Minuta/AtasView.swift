import AppKit
import SwiftUI

/// The "Atas…" window, a table in the style of the Finder's list view: sortable columns (data, título,
/// resumo, duração), no buttons in the rows, every action in the context menu. Recordings still being
/// processed are rows of the same table. Return renames, ⌘O, ⌘↓ or a double click opens, ⌘⌫ moves to the Trash.
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

/// One row of the table: an ata, or a recording still being processed.
struct ListRow: Identifiable {
    enum Kind {
        case ata(Ata)
        case job(Job, running: Bool)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .ata(let ata): ata.url.absoluteString
        case .job(let job, _): "job-" + job.id
        }
    }

    var start: Date {
        switch kind {
        case .ata(let ata): ata.start
        case .job(let job, _): job.startedAt
        }
    }

    var title: String {
        switch kind {
        case .ata(let ata): ata.title
        case .job(_, let running): running ? "Gravação em processamento" : "Gravação não processada"
        }
    }

    var summaryLabel: String {
        switch kind {
        case .ata(let ata): ata.summaryLabel
        case .job(let job, let running):
            running
                ? (job.stage == .minuting ? "Classificando a reunião…" : "Transcrevendo…")
                : (job.lastError.map { "Falhou: \($0)" } ?? "Interrompida")
        }
    }

    var durationSeconds: TimeInterval {
        switch kind {
        case .ata(let ata): ata.durationSeconds
        case .job(let job, _): job.durationSeconds
        }
    }
}

struct AtasView: View {
    @ObservedObject private var library = AtaLibrary.shared
    @ObservedObject private var model = AppModel.shared
    @ObservedObject private var summaries = SummaryService.shared
    @State private var sortOrder = [KeyPathComparator(\ListRow.start, order: .reverse)]
    @State private var selection: ListRow.ID?
    @State private var renamingID: ListRow.ID?
    @State private var draft = ""
    @FocusState private var focusedID: ListRow.ID?

    private var rows: [ListRow] {
        let jobs = library.pending.map { ListRow(kind: .job($0, running: model.runningJobs.contains($0.id))) }
        let atas = library.atas.map { ListRow(kind: .ata($0)) }
        return (jobs + atas).sorted(using: sortOrder)
    }

    private var selected: ListRow? { rows.first { $0.id == selection } }

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
                table
            }
        }
        .frame(minWidth: 560, minHeight: 280)
        .background(shortcuts)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            library.refresh()
        }
    }

    // MARK: Table

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Data", value: \.start) { row in
                Text(Fmt.finderDate(row.start)).foregroundStyle(.secondary)
            }
            .width(min: 150, ideal: 185)
            TableColumn("Título", value: \.title) { row in
                titleCell(row)
            }
            .width(min: 140)
            TableColumn("Resumo", value: \.summaryLabel) { row in
                SummaryCell(row: row, generating: ataURL(row).flatMap { summaries.running[$0] })
            }
            .width(min: 110, ideal: 150, max: 200)
            TableColumn("Duração", value: \.durationSeconds) { row in
                if case .ata(let ata) = row.kind, ata.duration == nil {
                    Text("—").foregroundStyle(.secondary)
                } else {
                    Text(Fmt.shortDuration(row.durationSeconds)).foregroundStyle(.secondary)
                }
            }
            .width(70)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .contextMenu(forSelectionType: ListRow.ID.self) { ids in
            if let row = rows.first(where: { ids.contains($0.id) }) { menu(for: row) }
        } primaryAction: { ids in
            if let row = rows.first(where: { ids.contains($0.id) }), case .ata(let ata) = row.kind { open(ata) }
        }
    }

    private func ataURL(_ row: ListRow) -> URL? {
        if case .ata(let ata) = row.kind { ata.url } else { nil }
    }

    @ViewBuilder private func titleCell(_ row: ListRow) -> some View {
        HStack(spacing: 7) {
            icon(row)
            if renamingID == row.id {
                TextField("Título da reunião", text: $draft)
                    .textFieldStyle(.roundedBorder)
                    .focused($focusedID, equals: row.id)
                    .onSubmit { commitRename() }
                    .onExitCommand { renamingID = nil }
                    .onChange(of: focusedID) { focus in
                        if focus != row.id, renamingID == row.id { commitRename() }
                    }
            } else {
                Text(row.title).lineLimit(1).truncationMode(.tail)
                    .foregroundStyle(isJob(row) || row.title == MinutesRenderer.untitled ? .secondary : .primary)
            }
        }
    }

    @ViewBuilder private func icon(_ row: ListRow) -> some View {
        if case .ata(let ata) = row.kind, ata.problem != nil {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.red)
        } else {
            Image(systemName: "doc.text").foregroundStyle(.secondary)
        }
    }

    private func isJob(_ row: ListRow) -> Bool {
        if case .job = row.kind { true } else { false }
    }

    // MARK: Menu

    @ViewBuilder private func menu(for row: ListRow) -> some View {
        switch row.kind {
        case .ata(let ata):
            let busy = summaries.running[ata.url] != nil
            Button("Abrir") { open(ata) }.disabled(!(ata.problem?.canOpen ?? true))
            Button("Mostrar no Finder") { reveal(ata) }
            Divider()
            if ata.model != nil || ata.noSummary { summaryMenu(ata, busy: busy) }
            Divider()
            Button("Mover para a Lixeira") { trash(ata) }
            Divider()
            Button("Renomear") { beginRename(row) }.disabled(ata.problem != nil || busy)
        case .job(let job, let running):
            Button("Tentar de novo") { AppModel.shared.run(job) }.disabled(running)
            Divider()
            Button("Descartar…") { discard(job) }
        }
    }

    /// The five models, with a check on the one shown. Choosing one shows it, generating it first if needed.
    @ViewBuilder private func summaryMenu(_ ata: Ata, busy: Bool) -> some View {
        let suggestion = suggestion(for: ata)
        Menu("Resumo") {
            Picker(
                "Resumo",
                selection: Binding<SummaryModel?>(
                    get: { ata.model },
                    set: { if let chosen = $0, chosen != ata.model { generate(chosen, for: ata) } })
            ) {
                ForEach(SummaryModel.allCases) { model in
                    Text(model == suggestion ? "\(model.title) (sugerido)" : model.title).tag(Optional(model))
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        .disabled(busy || ata.problem != nil)
    }

    private func suggestion(for ata: Ata) -> SummaryModel? {
        guard let text = try? String(contentsOf: ata.url, encoding: .utf8) else { return nil }
        return AtaStore.sidecar(forMarkdown: text, in: ata.url.deletingLastPathComponent())?.sidecar
            .classification?.suggestion
    }

    // MARK: Keyboard

    /// Finder keys, as hidden buttons: Return renames, ⌘O and ⌘↓ open, ⌘⌫ moves to the Trash.
    private var shortcuts: some View {
        ZStack {
            Button("Renomear") { if let row = selected { beginRename(row) } }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(renamingID != nil || selected == nil)
            Button("Abrir") { if case .ata(let ata)? = selected?.kind { open(ata) } }
                .keyboardShortcut("o", modifiers: .command)
            Button("Abrir") { if case .ata(let ata)? = selected?.kind { open(ata) } }
                .keyboardShortcut(.downArrow, modifiers: .command)
            Button("Mover para a Lixeira") { if case .ata(let ata)? = selected?.kind { trash(ata) } }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(renamingID != nil)
        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
    }

    // MARK: Actions

    private func open(_ ata: Ata) {
        guard ata.problem?.canOpen ?? true else { return }
        AtaViewerController.shared.open(ata.url)
    }

    private func reveal(_ ata: Ata) {
        NSWorkspace.shared.activateFileViewerSelecting([ata.url])
    }

    private func beginRename(_ row: ListRow) {
        guard case .ata(let ata) = row.kind, ata.problem == nil, summaries.running[ata.url] == nil else { return }
        selection = row.id
        draft = ata.title == MinutesRenderer.untitled ? "" : ata.title
        renamingID = row.id
        DispatchQueue.main.async { focusedID = row.id }
    }

    private func commitRename() {
        guard let id = renamingID, let row = rows.first(where: { $0.id == id }), case .ata(let ata) = row.kind
        else {
            renamingID = nil
            return
        }
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

    private func generate(_ model: SummaryModel, for ata: Ata) {
        Task {
            do {
                try await SummaryService.shared.show(model, for: ata.url)
            } catch {
                Alerts.show(
                    title: "Não foi possível gerar o resumo", message: AppError.from(error).message, buttons: ["OK"])
            }
        }
    }

    /// The Trash is reversible, so there is no question, like the Finder.
    private func trash(_ ata: Ata) {
        do {
            try library.trash(ata)
            AtaViewerController.shared.close(ata.url)
        } catch {
            Alerts.show(
                title: "Não foi possível mover a ata", message: AppError.from(error).message, buttons: ["OK"])
        }
    }

    private func discard(_ job: Job) {
        let choice = Alerts.show(
            title: "Descartar a gravação?",
            message: "A gravação de \(Fmt.listDate(job.startedAt)) será apagada e não poderá ser recuperada.",
            buttons: ["Cancelar", "Descartar"], destructive: 1)
        if choice == 1 { library.discard(job) }
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

/// The "Resumo" column: a colored dot and the model, "Sem resumo", a generation in progress, the state of a
/// recording, or what is wrong with the file. Plain text, like the Finder's Tags column.
private struct SummaryCell: View {
    let row: ListRow
    let generating: SummaryModel?

    var body: some View {
        switch row.kind {
        case .ata(let ata):
            if generating != nil {
                busy("Gerando resumo…")
            } else if let problem = ata.problem {
                Text(problem.label).foregroundStyle(.red)
            } else if let model = ata.model {
                labeled(model.title, model.tint)
            } else if ata.noSummary {
                labeled("Sem resumo", .orange)
            }
        case .job(let job, let running):
            if running {
                busy(row.summaryLabel)
            } else if let error = job.lastError {
                Text("Falhou: \(error)").foregroundStyle(.red).lineLimit(1).truncationMode(.tail).help(error)
            } else {
                Text("Interrompida").foregroundStyle(.secondary)
            }
        }
    }

    private func busy(_ text: String) -> some View {
        HStack(spacing: 6) {
            ProgressView().controlSize(.small)
            Text(text).foregroundStyle(.secondary).lineLimit(1)
        }
    }

    private func labeled(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 7) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).lineLimit(1)
        }
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
