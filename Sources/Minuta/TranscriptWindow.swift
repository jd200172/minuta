import AVFoundation
import AppKit
import Combine
import SwiftUI

/// The window that corrects the transcript of a meeting (ADR 0025): every segment with its time, speaker and text,
/// the recording played from any segment, and the summaries marked as outdated after a correction. Corrections go
/// to the sidecar through `AtaStore`, which renders the `.md` again; the reading window reloads on `.ataChanged`.
@MainActor
final class TranscriptWindowController: NSObject, NSWindowDelegate {
    static let shared = TranscriptWindowController()
    /// One window per meeting, by `inicio` (the file name changes with the title).
    private var windows: [String: (window: NSWindow, model: TranscriptEditor)] = [:]
    private var keyMonitor: Any?

    func open(_ url: URL) {
        guard let text = try? String(contentsOf: url, encoding: .utf8),
            let (sidecar, _) = AtaStore.sidecar(forMarkdown: text, in: url.deletingLastPathComponent())
        else {
            Alerts.show(
                title: "Não foi possível abrir a transcrição",
                message: "Esta ata não tem o arquivo de resumos e transcrição ao lado dela.", buttons: ["OK"])
            return
        }
        if let open = windows[sidecar.inicio] {
            NSApp.activate(ignoringOtherApps: true)
            open.window.makeKeyAndOrderFront(nil)
            return
        }
        let model = TranscriptEditor(inicio: sidecar.inicio, dir: url.deletingLastPathComponent())
        let window = ClosableWindow(contentViewController: NSHostingController(rootView: TranscriptView(model: model)))
        window.title = "Transcrição · " + (AtaStore.title(in: text) ?? MinutesRenderer.untitled)
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(NSSize(width: 760, height: 780))
        window.contentMinSize = NSSize(width: 520, height: 360)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        windows[sidecar.inicio] = (window, model)
        watchSpace()
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Space plays and pauses, unless a text is being edited (then it is a space in the text).
    private func watchSpace() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == 49,
                event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
                let window = event.window, !(window.firstResponder is NSText),
                let model = self.windows.values.first(where: { $0.window === window })?.model,
                model.player.available
            else { return event }
            model.player.toggle()
            return nil
        }
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
            let key = windows.first(where: { $0.value.window === window })?.key
        else { return }
        windows[key]?.model.player.stop()
        windows[key] = nil
    }
}

// MARK: - Player

/// Plays the two recordings of a meeting together, from any moment of the meeting's clock. Each channel can be
/// muted; the speed applies to both.
@MainActor
final class TranscriptPlayer: ObservableObject {
    static let speeds: [Float] = [0.75, 1, 1.25, 1.5]

    @Published private(set) var playing = false
    /// The current moment, in the meeting's clock (the segments' times).
    @Published private(set) var time: Double = 0
    @Published var rate: Float = 1 {
        didSet { for player in players { player.rate = rate } }
    }
    @Published var micOn = true {
        didSet { mic?.volume = micOn ? 1 : 0 }
    }
    @Published var systemOn = true {
        didSet { system?.volume = systemOn ? 1 : 0 }
    }

    private var mic: AVAudioPlayer?
    private var system: AVAudioPlayer?
    private var offsets = Sidecar.AudioOffsets(mic: 0, system: 0)
    private var timer: Timer?

    var available: Bool { mic != nil || system != nil }
    private var players: [AVAudioPlayer] { [mic, system].compactMap { $0 } }

    /// The longest of the two recordings, in the meeting's clock.
    var duration: Double {
        max((mic?.duration ?? 0) + offsets.mic, (system?.duration ?? 0) + offsets.system)
    }

    func load(files: [URL], offsets: Sidecar.AudioOffsets?) {
        stop()
        self.offsets = offsets ?? .init(mic: 0, system: 0)
        func player(_ suffix: String) -> AVAudioPlayer? {
            guard let url = files.first(where: { $0.lastPathComponent.hasSuffix(suffix) }),
                let player = try? AVAudioPlayer(contentsOf: url)
            else { return nil }
            player.enableRate = true
            player.prepareToPlay()
            return player
        }
        mic = player(".\(AudioArchive.micSuffix)")
        system = player(".\(AudioArchive.systemSuffix)")
        mic?.volume = micOn ? 1 : 0
        system?.volume = systemOn ? 1 : 0
    }

    func play(from moment: Double) {
        let start = mic?.deviceCurrentTime ?? system?.deviceCurrentTime ?? 0
        for (player, offset) in [(mic, offsets.mic), (system, offsets.system)] {
            guard let player else { continue }
            player.pause()
            player.rate = rate
            player.currentTime = max(0, min(player.duration, moment - offset))
            // A channel that starts later waits for its own beginning.
            player.play(atTime: start + 0.05 + max(0, offset - moment) / Double(rate))
        }
        time = moment
        playing = true
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func toggle() {
        if playing { pause() } else { play(from: time) }
    }

    func pause() {
        for player in players { player.pause() }
        playing = false
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        pause()
        mic = nil
        system = nil
    }

    func seek(_ moment: Double) {
        if playing { play(from: moment) } else { time = moment }
    }

    private func tick() {
        let times = [(mic, offsets.mic), (system, offsets.system)].compactMap { player, offset in
            player.map { $0.currentTime + offset }
        }
        time = times.max() ?? time
        if !players.contains(where: \.isPlaying), time >= duration - 0.3 { pause() }
    }
}

// MARK: - Model

/// The state of one transcript window. It always reads the sidecar again after a change, so what it shows is what
/// the files hold.
@MainActor
final class TranscriptEditor: ObservableObject {
    struct Row: Identifiable, Equatable {
        var segment: Segment
        var system: Bool
        var corrected: Bool
        var id: String { segment.id }
    }

    let inicio: String
    let dir: URL
    let player = TranscriptPlayer()
    @Published private(set) var rows: [Row] = []
    @Published private(set) var speakers: [String] = []
    @Published private(set) var names: [String: String] = [:]
    @Published private(set) var outdated: SummaryModel?
    @Published private(set) var busy = false
    @Published private(set) var failure: String?
    private var subscriptions: [AnyCancellable] = []

    init(inicio: String, dir: URL) {
        self.inicio = inicio
        self.dir = dir
        reload()
        if let url = markdownURL {
            player.load(files: AtaStore.audioFiles(forMarkdown: url), offsets: sidecar()?.audioOffsets)
        }
        SummaryService.shared.$running.receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.reload()
        }.store(in: &subscriptions)
        NotificationCenter.default.publisher(for: .ataChanged).receive(on: DispatchQueue.main).sink { [weak self] _ in
            self?.reload()
        }.store(in: &subscriptions)
        // The player publishes on its own; repeat it so the rows follow the playing segment.
        player.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &subscriptions)
    }

    var markdownURL: URL? { AtaStore.markdown(inicio: inicio, in: dir) }

    private func sidecar() -> Sidecar? {
        guard let url = markdownURL, let text = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return AtaStore.sidecar(forMarkdown: text, in: dir)?.sidecar
    }

    func reload() {
        guard let url = markdownURL, let text = try? String(contentsOf: url, encoding: .utf8),
            let sidecar = AtaStore.sidecar(forMarkdown: text, in: dir)?.sidecar
        else {
            failure = "A ata desta transcrição não foi encontrada na pasta de atas."
            return
        }
        failure = nil
        rows = sidecar.segments.map {
            Row(segment: $0, system: sidecar.isSystem($0), corrected: sidecar.original($0.id) != nil)
        }
        var labels: [String] = []
        for segment in sidecar.segments + Array((sidecar.originals ?? [:]).values)
        where !labels.contains(segment.speaker) {
            labels.append(segment.speaker)
        }
        speakers = labels.sorted { a, b in
            let pa = a.hasPrefix("Participante ")
            let pb = b.hasPrefix("Participante ")
            return pa == pb ? a.localizedStandardCompare(b) == .orderedAscending : !pa
        }
        names = ParticipantEditor.names(in: text)
        outdated = AtaStore.model(in: text).flatMap { sidecar.isOutdated($0) ? $0 : nil }
        busy = SummaryService.shared.running[url] != nil
    }

    /// The name shown for a label: the one the user gave, or the label.
    func display(_ label: String) -> String {
        names[label] ?? label.trimmingCharacters(in: .whitespaces)
    }

    /// The segment being played, while the player runs.
    var current: String? {
        guard player.playing else { return nil }
        return rows.last { $0.segment.start <= player.time + 0.05 }?.id
    }

    private func perform(_ change: (URL) throws -> Void) {
        guard let url = markdownURL else { return }
        do {
            try change(url)
            NotificationCenter.default.post(name: .ataChanged, object: url)
            AtaLibrary.shared.refresh()
        } catch {
            Alerts.show(
                title: "Não foi possível corrigir a transcrição", message: AppError.from(error).message,
                buttons: ["OK"])
        }
        reload()
    }

    func save(_ row: Row, text: String) {
        perform { try AtaStore.updateSegment(row.id, text: text, speaker: row.segment.speaker, in: $0) }
    }

    func setSpeaker(_ row: Row, to label: String) {
        perform { try AtaStore.updateSegment(row.id, text: row.segment.text, speaker: label, in: $0) }
    }

    func restore(_ row: Row) {
        perform { try AtaStore.restoreSegment(row.id, in: $0) }
    }

    func delete(_ row: Row) {
        let choice = Alerts.show(
            title: "Apagar esta fala?",
            message: "Ela sai da transcrição e da ata. O texto original fica guardado no arquivo de resumos.",
            buttons: ["Cancelar", "Apagar"], destructive: 1, escape: 0)
        guard choice == 1 else { return }
        perform { try AtaStore.deleteSegment(row.id, in: $0) }
    }

    /// Generates the summary shown in the ata again, from the corrected transcript.
    func redoSummary() {
        guard let url = markdownURL, let model = outdated else { return }
        Task {
            do {
                try await SummaryService.shared.show(model, for: url, force: true)
            } catch {
                Alerts.show(
                    title: "Não foi possível gerar o resumo", message: AppError.from(error).message, buttons: ["OK"])
            }
            reload()
        }
    }
}

// MARK: - Views

struct TranscriptView: View {
    @ObservedObject var model: TranscriptEditor
    @State private var onlyCorrected = false

    private var visible: [TranscriptEditor.Row] {
        onlyCorrected ? model.rows.filter(\.corrected) : model.rows
    }

    var body: some View {
        VStack(spacing: 0) {
            if let failure = model.failure {
                Text(failure).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                header
                Divider()
                if let outdated = model.outdated { banner(outdated) }
                ScrollViewReader { proxy in
                    // A plain stack, not a List: a List row takes the click that should start editing the text.
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(visible) { row in
                                TranscriptRow(model: model, row: row, playing: model.current == row.id)
                                    .id(row.id)
                                Divider().padding(.leading, 16)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                    .onChange(of: model.current) { id in
                        if let id { withAnimation { proxy.scrollTo(id, anchor: .center) } }
                    }
                }
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button {
                    model.player.toggle()
                } label: {
                    Image(systemName: model.player.playing ? "pause.fill" : "play.fill").frame(width: 16)
                }
                .disabled(!model.player.available)
                .help(model.player.playing ? "Pausar" : "Tocar")
                .accessibilityLabel(model.player.playing ? "Pausar" : "Tocar")
                Text(Fmt.clock(model.player.time)).monospacedDigit().foregroundStyle(.secondary)
                Slider(
                    value: Binding(get: { model.player.time }, set: { model.player.seek($0) }),
                    in: 0...max(1, model.player.duration)
                )
                .disabled(!model.player.available)
                Text(Fmt.clock(model.player.duration)).monospacedDigit().foregroundStyle(.secondary)
                Picker("Velocidade", selection: Binding(get: { model.player.rate }, set: { model.player.rate = $0 })) {
                    ForEach(TranscriptPlayer.speeds, id: \.self) { speed in
                        Text(speed == 1 ? "1x" : String(format: "%gx", speed)).tag(speed)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .disabled(!model.player.available)
            }
            HStack(spacing: 12) {
                Toggle(isOn: Binding(get: { model.player.micOn }, set: { model.player.micOn = $0 })) {
                    Label("Microfone", systemImage: "mic")
                }
                Toggle(isOn: Binding(get: { model.player.systemOn }, set: { model.player.systemOn = $0 })) {
                    Label("Sistema", systemImage: "laptopcomputer")
                }
                Spacer()
                Picker("Mostrar", selection: $onlyCorrected) {
                    Text("Todas").tag(false)
                    Text("Corrigidas").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .toggleStyle(.button)
            if !model.player.available {
                Text("Esta reunião não tem áudio guardado. Dá para corrigir o texto, mas não para ouvir.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            Text(summaryLine).font(.callout).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var summaryLine: String {
        let total = model.rows.count
        let fixed = model.rows.filter(\.corrected).count
        return "\(total) \(total == 1 ? "fala" : "falas") · \(fixed) \(fixed == 1 ? "corrigida" : "corrigidas")"
            + " · Clique no horário para ouvir; edite o texto no lugar e tecle Return para salvar."
    }

    private func banner(_ outdated: SummaryModel) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle").foregroundStyle(.secondary)
            Text("A transcrição mudou depois do resumo \(outdated.title). O resumo ainda reflete a versão anterior.")
                .font(.callout)
            Spacer()
            Button(model.busy ? "Gerando…" : "Refazer resumo") { model.redoSummary() }
                .disabled(model.busy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.06))
    }
}

/// One segment: the time (plays from it), the speaker (a menu to change it), the text (edited in place) and its
/// actions. Return or leaving the field saves; Esc gives the text back.
struct TranscriptRow: View {
    @ObservedObject var model: TranscriptEditor
    let row: TranscriptEditor.Row
    let playing: Bool
    @State private var draft = ""
    @FocusState private var editing: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Button {
                model.player.play(from: row.segment.start)
            } label: {
                Text(Fmt.clock(row.segment.start))
                    .font(.system(size: BalloonStyle.chipFontSize).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .background(
                        Color.primary.opacity(BalloonStyle.chipTint),
                        in: RoundedRectangle(cornerRadius: BalloonStyle.chipRadius))
            }
            .buttonStyle(.plain)
            .disabled(!model.player.available)
            .help("Ouvir a partir daqui")
            .accessibilityLabel("Ouvir a partir de \(Fmt.clock(row.segment.start))")

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Menu {
                        ForEach(model.speakers, id: \.self) { label in
                            Button(model.display(label)) { model.setSpeaker(row, to: label) }
                                .disabled(label == row.segment.speaker)
                        }
                    } label: {
                        Text(model.display(row.segment.speaker)).fontWeight(.semibold)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(model.busy)
                    .help("Trocar o falante")
                    Image(systemName: row.system ? "laptopcomputer" : "mic")
                        .foregroundStyle(.tertiary)
                        .help(row.system ? "Gravado pelo áudio do sistema" : "Gravado pelo microfone")
                        .accessibilityLabel(row.system ? "Áudio do sistema" : "Microfone")
                    if row.corrected {
                        Text("Corrigida").font(.caption).foregroundStyle(.secondary)
                    }
                }
                TextField("Texto da fala", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($editing)
                    .disabled(model.busy)
                    .onSubmit { commit() }
                    .onExitCommand {
                        draft = row.segment.text
                        editing = false
                    }
            }

            Spacer(minLength: 0)
            Menu {
                if row.corrected {
                    Button("Restaurar original") { model.restore(row) }
                }
                Button("Apagar fala", role: .destructive) { model.delete(row) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .disabled(model.busy)
            .help("Mais ações")
            .accessibilityLabel("Mais ações")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 16)
        .background(playing ? Color.primary.opacity(BalloonStyle.rowTint) : Color.clear)
        .onAppear { draft = row.segment.text }
        .onChange(of: row.segment.text) { draft = $0 }
        .onChange(of: editing) { focused in
            if !focused { commit() }
        }
    }

    private func commit() {
        guard draft != row.segment.text else { return }
        model.save(row, text: draft)
    }
}
