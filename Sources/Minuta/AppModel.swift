import AppKit
import SwiftUI

@MainActor
final class AppModel: ObservableObject {
    struct JobState: Identifiable {
        var job: Job
        var running: Bool
        var id: String { job.id }
    }

    @Published var recordingStart: Date?
    @Published var jobs: [JobState] = []

    private let store = JobStore()
    private let recorder = Recorder()
    private var currentJob: Job?
    private var limitTimer: Timer?

    var iconName: String {
        if recordingStart != nil { return "record.circle.fill" }
        if jobs.contains(where: { !$0.running }) { return "exclamationmark.triangle" }
        if jobs.contains(where: { $0.running }) { return "arrow.triangle.2.circlepath" }
        return "mic"
    }

    init() {
        Notifier.requestAuthorization()
        jobs = store.load().map { stored in
            var job = stored
            if job.stage == .recording { job.stage = .transcribing }
            job.lastError = job.lastError ?? "Interrompido antes de terminar."
            return JobState(job: job, running: false)
        }
        recorder.onInterrupted = { [weak self] in
            Task { @MainActor in self?.stopRecording() }
        }
    }

    // MARK: Recording

    func startRecording() {
        guard recordingStart == nil else { return }
        guard Keychain.get(Config.googleAccount) != nil, Keychain.get(Config.anthropicAccount) != nil else {
            Notifier.post("Faltam as chaves de API", "Abra Configurações e salve as chaves do Google e da Anthropic.")
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
                if !recorder.micActive {
                    Notifier.post("Sem microfone", "Nenhum microfone encontrado. Gravando só o áudio do sistema.")
                }
                limitTimer = Timer.scheduledTimer(withTimeInterval: Config.maxRecordingSeconds,
                                                  repeats: false) { _ in
                    Task { @MainActor in self.stopRecording() }
                }
            } catch {
                store.delete(job.id)
                Notifier.post("Não foi possível gravar", error.localizedDescription)
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

    // MARK: Jobs

    func run(_ job: Job) {
        upsert(JobState(job: job, running: true))
        Task {
            var job = job
            job.lastError = nil
            do {
                if job.stage == .transcribing {
                    let transcript = try await Pipeline.transcribe(job: job, dir: store.dir(job.id))
                    try store.saveTranscript(transcript, job: job)
                    let dir = store.dir(job.id)
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent("mic.m4a"))
                    try? FileManager.default.removeItem(at: dir.appendingPathComponent("system.m4a"))
                    job.stage = .minuting
                    store.save(job)
                }
                let transcript = try store.loadTranscript(job: job)
                let file = try await Pipeline.minutes(job: job, transcript: transcript)
                store.delete(job.id)
                jobs.removeAll { $0.id == job.id }
                Notifier.post("Ata salva", file.lastPathComponent)
            } catch {
                job.lastError = error.localizedDescription
                store.save(job)
                upsert(JobState(job: job, running: false))
                Notifier.post(job.stage == .transcribing ? "Falha ao transcrever" : "Falha ao gerar a ata",
                              error.localizedDescription)
            }
        }
    }

    func discard(_ job: Job) {
        store.delete(job.id)
        jobs.removeAll { $0.id == job.id }
    }

    private func upsert(_ state: JobState) {
        if let index = jobs.firstIndex(where: { $0.id == state.id }) {
            jobs[index] = state
        } else {
            jobs.append(state)
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
            throw AppError("Chave da API do Google ausente. Salve em Configurações.")
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
            throw AppError("Chave da API da Anthropic ausente. Salve em Configurações.")
        }
        let data = try await ClaudeMinuter(apiKey: key).minutes(transcript: transcript, job: job)
        let markdown = MinutesRenderer.render(data, transcript: transcript, job: job)
        return try MinutesRenderer.write(markdown, job: job)
    }
}
