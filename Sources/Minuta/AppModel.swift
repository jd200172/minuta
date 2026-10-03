import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    /// Non-nil while a recording session is open, running or paused.
    @Published var recordingStart: Date?
    @Published private(set) var isPaused = false
    @Published private(set) var elapsedText: String?
    @Published private(set) var processing = 0
    /// IDs of the jobs being transcribed or turned into minutes right now.
    @Published private(set) var runningJobs: Set<String> = []

    private let store = JobStore()
    private let recorder = Recorder()
    private var currentJob: Job?
    private var ticker: Timer?
    private var runningSince: Date?
    private var elapsedBefore: TimeInterval = 0
    private var pausedAt: Date?
    private var nextReminder = Config.pauseReminderSeconds

    init() {
        Env.prepare()
        // A recording cut off mid-capture leaves an unreadable .m4a: nothing to recover.
        for job in store.load() where job.stage == .recording { store.delete(job.id) }
        recorder.onInterrupted = { [weak self] in
            Task { @MainActor in self?.endRecording() }
        }
        Task { await reviewPendingJobs() }
    }

    // MARK: Recording

    func startRecording() {
        guard recordingStart == nil else { return }
        do {
            _ = try Providers.transcriber()
            _ = try Providers.minuter()
        } catch {
            fail(AppError.from(error), title: "Falta configurar os provedores de IA")
            return
        }
        Task {
            let now = Date()
            let job = Job(
                id: Fmt.jobID(now), startedAt: now, durationSeconds: 0, stage: .recording,
                micOffset: 0, systemOffset: 0, lastError: nil)
            do {
                try await recorder.ensurePermissions()
                try store.makeDir(job.id)
                store.save(job)
                let dir = store.dir(job.id)
                try await recorder.start(
                    micURL: dir.appendingPathComponent("mic.m4a"),
                    systemURL: dir.appendingPathComponent("system.m4a"))
                currentJob = job
                recordingStart = now
                elapsedBefore = 0
                runningSince = now
                pausedAt = nil
                isPaused = false
                startTicker()
                if !recorder.micActive {
                    Notifier.post("Sem microfone", "Nenhum microfone encontrado. Gravando só o áudio do sistema.")
                }
            } catch {
                store.delete(job.id)
                fail(AppError.from(error), title: "Não foi possível gravar")
            }
        }
    }

    func pauseRecording() {
        guard recordingStart != nil, !isPaused else { return }
        let now = Date()
        elapsedBefore = elapsed(now)
        runningSince = nil
        pausedAt = now
        nextReminder = Config.pauseReminderSeconds
        recorder.paused = true
        isPaused = true
        refreshClock(now)
    }

    func resumeRecording() {
        guard isPaused else { return }
        runningSince = Date()
        pausedAt = nil
        recorder.paused = false
        isPaused = false
    }

    /// Ends the recording and starts processing it right away.
    func endRecording() {
        guard recordingStart != nil, var job = currentJob else { return }
        let duration = elapsed(Date())
        recordingStart = nil
        currentJob = nil
        isPaused = false
        pausedAt = nil
        runningSince = nil
        elapsedBefore = 0
        ticker?.invalidate()
        ticker = nil
        elapsedText = nil
        Task {
            let offsets = await recorder.stop()
            job.durationSeconds = duration
            job.micOffset = offsets.mic
            job.systemOffset = offsets.system
            job.stage = .transcribing
            store.save(job)
            run(job)
        }
    }

    /// Recorded time so far, pauses excluded.
    private func elapsed(_ now: Date) -> TimeInterval {
        elapsedBefore + (runningSince.map { now.timeIntervalSince($0) } ?? 0)
    }

    private func refreshClock(_ now: Date = Date()) {
        elapsedText = Fmt.elapsed(elapsed(now))
    }

    private func startTicker() {
        refreshClock()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common)
        ticker = timer
    }

    /// Once a second: updates the clock, enforces the time limit and reminds about a long pause.
    private func tick() {
        guard recordingStart != nil else { return }
        let now = Date()
        refreshClock(now)
        if elapsed(now) >= Config.maxRecordingSeconds {
            Notifier.post(
                "Gravação encerrada",
                "O limite de \(Int(Config.maxRecordingSeconds / 60)) minutos foi atingido. Processando a gravação.")
            endRecording()
        } else if let pausedAt, now.timeIntervalSince(pausedAt) >= nextReminder {
            nextReminder += Config.pauseReminderSeconds
            let minutes = Int(now.timeIntervalSince(pausedAt) / 60)
            Notifier.post("Gravação pausada", "Pausada há \(minutes) minutos. Continue ou encerre pelo menu.")
        }
    }

    // MARK: Processing

    func run(_ job: Job) {
        processing += 1
        runningJobs.insert(job.id)
        AtaLibrary.shared.refresh()
        Task {
            let failure = await process(job)
            processing -= 1
            runningJobs.remove(job.id)
            AtaLibrary.shared.refresh()
            if let (failed, error) = failure { askWhatToDo(with: failed, after: error) }
        }
    }

    /// Runs the pipeline from the job's current stage. Returns the job and the error when it fails.
    private func process(_ job: Job) async -> (Job, AppError)? {
        var job = job
        do {
            if job.stage == .transcribing {
                let dir = store.dir(job.id)
                let transcript = try await Pipeline.transcribe(job: job, dir: dir)
                try store.saveTranscript(transcript, job: job)
                job.stage = .minuting
                store.save(job)
                AtaLibrary.shared.refresh()
            }
            let transcript = try store.loadTranscript(job: job)
            // A failed classification does not block: the meeting is saved without title or suggestion.
            let classification = try? await Providers.minuter().classify(transcript: transcript)
            let url = try AtaStore.create(
                meta: MeetingMeta(start: job.startedAt, duration: job.durationSeconds), transcript: transcript,
                classification: classification, in: Config.outputDir)
            // The recordings stay (ADR 0022), under the name of the meeting's sidecar. If they cannot be moved, the
            // job folder keeps them and says so.
            let dir = store.dir(job.id)
            let mic = dir.appendingPathComponent("mic.m4a")
            let system = dir.appendingPathComponent("system.m4a")
            let expected = [mic, system].filter { FileManager.default.fileExists(atPath: $0.path) }.count
            let offsets = Sidecar.AudioOffsets(mic: job.micOffset, system: job.systemOffset)
            if AtaStore.keepAudio(mic: mic, system: system, offsets: offsets, forMarkdown: url) == expected {
                store.delete(job.id)
            } else {
                Notifier.post(
                    "Áudio não guardado", "A ata foi criada, mas o áudio continua na pasta de gravações pendentes.")
            }
            AtaLibrary.shared.refresh()
            summarizeSuggested(url, classification: classification)
            return nil
        } catch is NoSpeechError {
            store.delete(job.id)
            Alerts.show(
                title: "Sem fala suficiente",
                message:
                    "A gravação de \(Fmt.listDate(job.startedAt)) não tinha fala suficiente para virar uma ata. Ela foi descartada.",
                buttons: ["OK"])
            return nil
        } catch {
            let error = AppError.from(error)
            job.lastError = error.message
            store.save(job)
            return (job, error)
        }
    }

    /// Generates the summary in the suggested model right away (ADR 0017); without a suggestion, only says
    /// the transcript is saved.
    private func summarizeSuggested(_ url: URL, classification: Classification?) {
        let name = url.deletingPathExtension().lastPathComponent
        guard let model = classification?.suggestion else {
            Notifier.post("Transcrição salva", "Abra a reunião e escolha um modelo de resumo.")
            return
        }
        Task {
            do {
                try await SummaryService.shared.show(model, for: url)
                Notifier.post("Resumo salvo", name)
            } catch {
                Notifier.post("Não foi possível gerar o resumo", AppError.from(error).message)
            }
        }
    }

    private func askWhatToDo(with job: Job, after error: AppError) {
        let kept = job.stage == .transcribing ? "O áudio ficou guardado." : "A transcrição ficou guardada."
        let title =
            job.stage == .transcribing
            ? "Não foi possível transcrever a gravação"
            : "Não foi possível salvar a reunião"
        let choice = Alerts.show(
            title: title, message: "\(error.message)\n\n\(kept)",
            buttons: ["Tentar de novo", "Depois", "Descartar"], destructive: 2, escape: 1)
        switch choice {
        case 0: run(job)
        case 2: store.delete(job.id)
        default: break
        }
    }

    private func reviewPendingJobs() async {
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        for job in store.load() where job.id != currentJob?.id && job.stage != .recording {
            let when = job.startedAt.formatted(date: .abbreviated, time: .shortened)
            let minutes = max(1, Int((job.durationSeconds / 60).rounded()))
            let choice = Alerts.show(
                title: "Há uma gravação sem processar",
                message: "Gravação de \(when), com \(minutes) min. O processamento não terminou.",
                buttons: ["Processar", "Depois", "Descartar"], destructive: 2, escape: 1)
            switch choice {
            case 0: run(job)
            case 2: store.delete(job.id)
            default: break
            }
        }
    }

    private func fail(_ error: AppError, title: String) {
        let action: String?
        switch error.fix {
        case .none: action = nil
        case .settings: action = "Abrir Configurações"
        case .keys: action = "Abrir arquivo de chaves"
        }
        let buttons = action.map { ["OK", $0] } ?? ["OK"]
        if Alerts.show(title: title, message: error.message, buttons: buttons) == 1 {
            if error.fix == .keys { Env.open() } else { SettingsOpener.open() }
        }
    }

}

enum Pipeline {
    static func transcribe(job: Job, dir: URL) async throws -> Transcript {
        try await transcribe(
            mic: dir.appendingPathComponent("mic.m4a"), system: dir.appendingPathComponent("system.m4a"),
            micOffset: job.micOffset, systemOffset: job.systemOffset)
    }

    /// A channel whose file does not exist is left out (a Mac with no microphone records only the system).
    static func transcribe(mic micURL: URL, system systemURL: URL, micOffset: Double, systemOffset: Double)
        async throws -> Transcript
    {
        let stt = try Providers.transcriber()
        let none: (text: String, words: [Word]) = ("", [])
        let fm = FileManager.default
        async let mic = fm.fileExists(atPath: micURL.path) ? stt.transcribe(file: micURL, diarize: false) : none
        async let system =
            fm.fileExists(atPath: systemURL.path) ? stt.transcribe(file: systemURL, diarize: true) : none
        let transcript = TranscriptBuilder.build(
            mic: try await mic, system: try await system, micOffset: micOffset, systemOffset: systemOffset)
        let words = transcript.segments.reduce(0) { $0 + $1.text.split(whereSeparator: \.isWhitespace).count }
        guard words >= Config.minWords else { throw NoSpeechError() }
        return transcript
    }
}

/// The recording has too little speech to be worth minutes.
struct NoSpeechError: LocalizedError {
    var errorDescription: String? { "Não havia fala suficiente para gerar a ata." }
}
