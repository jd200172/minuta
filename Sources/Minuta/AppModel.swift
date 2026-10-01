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

    private let store = JobStore()
    private let recorder = Recorder()
    private var currentJob: Job?
    private var ticker: Timer?
    private var runningSince: Date?
    private var elapsedBefore: TimeInterval = 0
    private var pausedAt: Date?
    private var nextReminder = Config.pauseReminderSeconds

    var iconName: String {
        if recordingStart != nil { return isPaused ? "pause.circle.fill" : "record.circle.fill" }
        if processing > 0 { return "arrow.triangle.2.circlepath" }
        return "mic"
    }

    init() {
        Notifier.requestAuthorization()
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
            let job = Job(id: Fmt.jobID(now), startedAt: now, durationSeconds: 0, stage: .recording,
                          micOffset: 0, systemOffset: 0, lastError: nil)
            do {
                try await recorder.ensurePermissions()
                try store.makeDir(job.id)
                store.save(job)
                let dir = store.dir(job.id)
                try await recorder.start(micURL: dir.appendingPathComponent("mic.m4a"),
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
            Notifier.post("Gravação encerrada", "O limite de \(Int(Config.maxRecordingSeconds / 60)) minutos foi atingido. Gerando a ata.")
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
        Task {
            let failure = await process(job)
            processing -= 1
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
                try? FileManager.default.removeItem(at: dir.appendingPathComponent("mic.m4a"))
                try? FileManager.default.removeItem(at: dir.appendingPathComponent("system.m4a"))
                job.stage = .minuting
                store.save(job)
            }
            let transcript = try store.loadTranscript(job: job)
            let file = try await Pipeline.minutes(job: job, transcript: transcript)
            store.delete(job.id)
            Notifier.post("Ata salva", file.lastPathComponent)
            return nil
        } catch {
            let error = AppError.from(error)
            job.lastError = error.message
            store.save(job)
            return (job, error)
        }
    }

    private func askWhatToDo(with job: Job, after error: AppError) {
        let kept = job.stage == .transcribing ? "O áudio ficou guardado." : "A transcrição ficou guardada."
        let title = job.stage == .transcribing ? "Não foi possível transcrever a gravação"
                                               : "Não foi possível gerar a ata"
        let choice = Alerts.show(title: title, message: "\(error.message)\n\n\(kept)",
                                 buttons: ["Tentar de novo", "Depois", "Descartar"], destructive: 2)
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
                buttons: ["Processar", "Depois", "Descartar"], destructive: 2)
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

    func openOutputFolder() {
        try? FileManager.default.createDirectory(at: Config.outputDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Config.outputDir)
    }
}

enum Pipeline {
    static func transcribe(job: Job, dir: URL) async throws -> Transcript {
        let stt = try Providers.transcriber()
        let micURL = dir.appendingPathComponent("mic.m4a")
        let noMic: (text: String, words: [Word]) = ("", [])
        async let mic = FileManager.default.fileExists(atPath: micURL.path)
            ? stt.transcribe(file: micURL, diarize: false) : noMic
        async let system = stt.transcribe(file: dir.appendingPathComponent("system.m4a"), diarize: true)
        let transcript = TranscriptBuilder.build(
            mic: try await mic, system: try await system,
            micOffset: job.micOffset, systemOffset: job.systemOffset)
        guard !transcript.segments.isEmpty else { throw AppError("A transcrição veio vazia.") }
        return transcript
    }

    static func minutes(job: Job, transcript: Transcript) async throws -> URL {
        let data = try await Providers.minuter().minutes(transcript: transcript, job: job)
        let markdown = MinutesRenderer.render(data, transcript: transcript, job: job)
        return try MinutesRenderer.write(markdown, job: job)
    }
}
