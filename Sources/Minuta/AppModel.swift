import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var recordingStart: Date?
    @Published private(set) var processing = 0

    private let store = JobStore()
    private let recorder = Recorder()
    private var currentJob: Job?
    private var limitTimer: Timer?

    var iconName: String {
        if recordingStart != nil { return "record.circle.fill" }
        if processing > 0 { return "arrow.triangle.2.circlepath" }
        return "mic"
    }

    init() {
        Notifier.requestAuthorization()
        // A recording cut off mid-capture leaves an unreadable .m4a: nothing to recover.
        for job in store.load() where job.stage == .recording { store.delete(job.id) }
        recorder.onInterrupted = { [weak self] in
            Task { @MainActor in self?.stopRecording() }
        }
        Task { await reviewPendingJobs() }
    }

    // MARK: Recording

    func startRecording() {
        guard recordingStart == nil else { return }
        guard Keychain.get(Config.googleAccount) != nil, Keychain.get(Config.anthropicAccount) != nil else {
            fail(AppError("Salve as chaves do Google e da Anthropic em Configurações > Chaves de API.",
                          opensSettings: true), title: "Faltam as chaves de API")
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
                let timer = Timer(timeInterval: Config.maxRecordingSeconds, repeats: false) { _ in
                    Task { @MainActor in self.stopRecording() }
                }
                RunLoop.main.add(timer, forMode: .common)
                limitTimer = timer
                if !recorder.micActive {
                    Notifier.post("Sem microfone", "Nenhum microfone encontrado. Gravando só o áudio do sistema.")
                }
            } catch {
                store.delete(job.id)
                fail(AppError.from(error), title: "Não foi possível gravar")
            }
        }
    }

    func stopRecording() {
        guard let start = recordingStart, var job = currentJob else { return }
        recordingStart = nil
        currentJob = nil
        limitTimer?.invalidate()
        Task {
            let offsets = await recorder.stop()
            job.durationSeconds = Date().timeIntervalSince(start)
            job.micOffset = offsets.mic
            job.systemOffset = offsets.system
            job.stage = .transcribing
            store.save(job)
            run(job)
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
        let buttons = error.opensSettings ? ["OK", "Abrir Configurações"] : ["OK"]
        if Alerts.show(title: title, message: error.message, buttons: buttons) == 1 {
            SettingsOpener.open()
        }
    }

    func openOutputFolder() {
        try? FileManager.default.createDirectory(at: Config.outputDir, withIntermediateDirectories: true)
        NSWorkspace.shared.open(Config.outputDir)
    }
}

enum Pipeline {
    static func transcribe(job: Job, dir: URL) async throws -> Transcript {
        guard let key = Keychain.get(Config.googleAccount) else {
            throw AppError("Salve a chave do Google em Configurações > Chaves de API.", opensSettings: true)
        }
        let gemini = GeminiTranscriber(apiKey: key)
        let micURL = dir.appendingPathComponent("mic.m4a")
        let noMic: (text: String, words: [Word]) = ("", [])
        async let mic = FileManager.default.fileExists(atPath: micURL.path)
            ? gemini.transcribe(file: micURL, diarize: false) : noMic
        async let system = gemini.transcribe(file: dir.appendingPathComponent("system.m4a"), diarize: true)
        let transcript = TranscriptBuilder.build(
            mic: try await mic, system: try await system,
            micOffset: job.micOffset, systemOffset: job.systemOffset)
        guard !transcript.segments.isEmpty else { throw AppError("A transcrição veio vazia.") }
        return transcript
    }

    static func minutes(job: Job, transcript: Transcript) async throws -> URL {
        guard let key = Keychain.get(Config.anthropicAccount) else {
            throw AppError("Salve a chave da Anthropic em Configurações > Chaves de API.", opensSettings: true)
        }
        let data = try await ClaudeMinuter(apiKey: key).minutes(transcript: transcript, job: job)
        let markdown = MinutesRenderer.render(data, transcript: transcript, job: job)
        return try MinutesRenderer.write(markdown, job: job)
    }
}
