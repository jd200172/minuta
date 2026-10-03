import Foundation

/// Transcribes a meeting again from the recordings kept in the audio folder (ADR 0026) and replaces its transcript.
@MainActor
final class Retranscriber: ObservableObject {
    static let shared = Retranscriber()

    /// The atas being transcribed again.
    @Published private(set) var running: Set<URL> = []

    /// Whether `url` is a meeting written by the model flow that still has a recording to transcribe.
    static func canRedo(_ url: URL, text: String) -> Bool {
        AtaStore.isManaged(text) && !AtaStore.audioFiles(forMarkdown: url).isEmpty
    }

    func redo(_ url: URL) async throws {
        guard !running.contains(url), SummaryService.shared.running[url] == nil else {
            throw AppError("Há um processamento em andamento para esta reunião. Aguarde.")
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        let (sidecar, sidecarURL) = try AtaStore.loadSidecar(for: url, text: text)
        guard !AtaStore.audioFiles(forMarkdown: url).isEmpty else {
            throw AppError("Esta reunião não tem áudio guardado.")
        }
        running.insert(url)
        defer { running.remove(url) }
        let audio = AudioArchive.urls(stem: AudioArchive.stem(ofSidecar: sidecarURL), in: Config.audioDir)
        let offsets = sidecar.audioOffsets ?? Sidecar.AudioOffsets(mic: 0, system: 0)
        let transcript: Transcript
        do {
            transcript = try await Pipeline.transcribe(
                mic: audio.mic, system: audio.system, micOffset: offsets.mic, systemOffset: offsets.system)
        } catch is NoSpeechError {
            throw AppError("A nova transcrição não teve fala suficiente. A transcrição atual foi mantida.")
        }
        try AtaStore.replaceTranscript(transcript, in: url)
        if Config.outputOverride == nil { AtaLibrary.shared.refresh() }
        NotificationCenter.default.post(name: .ataChanged, object: url)
    }
}
