import Foundation

/// Developer mode: runs the transcription and minutes pipeline on existing audio files.
///
/// Usage: Minuta --process <dir with mic.m4a and system.m4a> --out <output dir> [--date 2026-09-30T14:02:00-03:00]
/// Writes transcript.json and the Markdown minutes into the output dir, and prints the result.
enum CLI {
    static func requested() -> Bool {
        CommandLine.arguments.contains("--process")
    }

    private static func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    static func run() async -> Int32 {
        guard let input = value(after: "--process"), let out = value(after: "--out") else {
            print("Uso: Minuta --process <pasta> --out <pasta> [--date ISO8601]")
            return 2
        }
        let outURL = URL(fileURLWithPath: out)
        Config.outputOverride = outURL
        let date = value(after: "--date").flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        let job = Job(id: Fmt.jobID(date), startedAt: date, durationSeconds: 0, stage: .transcribing,
                      micOffset: 0, systemOffset: 0, lastError: nil)
        do {
            try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
            print("Transcrevendo...")
            let transcript = try await Pipeline.transcribe(job: job, dir: URL(fileURLWithPath: input))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(transcript).write(to: outURL.appendingPathComponent("transcript.json"))
            print("Segmentos: \(transcript.segments.count)")
            print("Gerando a ata...")
            let file = try await Pipeline.minutes(job: job, transcript: transcript)
            print("Ata: \(file.path)")
            return 0
        } catch {
            print("Erro: \(error.localizedDescription)")
            return 1
        }
    }
}
