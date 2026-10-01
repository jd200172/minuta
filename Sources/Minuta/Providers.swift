import Foundation

/// One step of the pipeline each, so a provider can be swapped through `.env` (ADR 0012).
/// Whatever a provider returns must fit these types; `TranscriptBuilder` and `MinutesRenderer`
/// validate the rest.
protocol Transcriber: Sendable {
    /// Words with start/end times in seconds. With `diarize`, each word carries a speaker label.
    func transcribe(file: URL, diarize: Bool) async throws -> (text: String, words: [Word])
}

protocol Minuter: Sendable {
    /// Minutes as JSON following `MinutesPrompt.schema`, citing segment IDs from the transcript.
    func minutes(transcript: Transcript, job: Job) async throws -> MinutesData
}

enum Providers {
    static func transcriber() throws -> Transcriber {
        let name = Env.value("TRANSCRIBER") ?? Config.defaultTranscriber
        switch name {
        case "gemini":
            return GeminiTranscriber(apiKey: try Env.key(.google),
                                     model: Env.value("TRANSCRIBER_MODEL") ?? Config.defaultTranscriberModel)
        default:
            throw AppError("TRANSCRIBER=\(name) não é um provedor conhecido. Use: gemini.", fix: .keys)
        }
    }

    static func minuter() throws -> Minuter {
        let name = Env.value("MINUTER") ?? Config.defaultMinuter
        switch name {
        case "claude":
            return ClaudeMinuter(apiKey: try Env.key(.anthropic),
                                 model: Env.value("MINUTER_MODEL") ?? Config.defaultMinuterModel)
        default:
            throw AppError("MINUTER=\(name) não é um provedor conhecido. Use: claude.", fix: .keys)
        }
    }
}
