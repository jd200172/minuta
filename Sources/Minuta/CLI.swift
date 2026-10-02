import Foundation

/// Developer mode: runs the transcription and minutes pipeline on existing audio files.
///
/// Usage: Minuta --process <dir with mic.m4a and system.m4a> --out <output dir> [--date 2026-09-30T14:02:00-03:00]
///        [--model decisao|problemas|informativa|geral|all]
/// Writes transcript.json, the meeting file and its sidecar into the output dir, classifies the meeting and
/// generates the summary in the suggested model (Geral without a suggestion), or in the model(s) asked for.
enum CLI {
    static func requested() -> Bool {
        CommandLine.arguments.contains("--process") || CommandLine.arguments.contains("--capture-test")
    }

    private static func value(after flag: String) -> String? {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else { return nil }
        return args[index + 1]
    }

    /// Minuta --capture-test <report.json> [--aec on|off] [--seconds 10]
    /// Records both channels for a few seconds, with echo cancellation on or off, and writes the levels and the bleed
    /// of the call into the microphone to the report (ADR 0023). Start it with `open -a Minuta --args ...` so it runs
    /// with the app's microphone and screen permissions.
    private static func captureTest(report: String) async -> Int32 {
        if let aec = value(after: "--aec") { Config.echoCancellationOverride = aec != "off" }
        let seconds = value(after: "--seconds").flatMap(Double.init) ?? 10
        do {
            let result = try await CaptureTest.run(seconds: seconds)
            let body: [String: Any] = [
                "echoCancelled": result.echoCancelled, "hasMicrophone": result.hasMicrophone,
                "micLevelDB": Double(result.micLevel), "systemLevelDB": Double(result.systemLevel),
                "micPeak": Double(result.micPeak), "systemPeak": Double(result.systemPeak),
                "bleed": Double(result.bleed), "seconds": seconds,
            ]
            try JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys])
                .write(to: URL(fileURLWithPath: report))
            return 0
        } catch {
            try? Data("{\"error\": \"\(error.localizedDescription)\"}".utf8).write(to: URL(fileURLWithPath: report))
            return 1
        }
    }

    static func run() async -> Int32 {
        if let report = value(after: "--capture-test") { return await captureTest(report: report) }
        guard let input = value(after: "--process"), let out = value(after: "--out") else {
            print("Uso: Minuta --process <pasta> --out <pasta> [--date ISO8601] [--model <modelo>|all]")
            return 2
        }
        Env.prepare()
        let outURL = URL(fileURLWithPath: out)
        Config.outputOverride = outURL
        let date = value(after: "--date").flatMap { ISO8601DateFormatter().date(from: $0) } ?? Date()
        let job = Job(
            id: Fmt.jobID(date), startedAt: date, durationSeconds: 0, stage: .transcribing,
            micOffset: 0, systemOffset: 0, lastError: nil)
        do {
            try FileManager.default.createDirectory(at: outURL, withIntermediateDirectories: true)
            print("Transcrevendo...")
            let transcript = try await Pipeline.transcribe(job: job, dir: URL(fileURLWithPath: input))
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            try encoder.encode(transcript).write(to: outURL.appendingPathComponent("transcript.json"))
            print("Segmentos: \(transcript.segments.count)")
            print("Classificando...")
            let classification = try? await Providers.minuter().classify(transcript: transcript)
            if let classification {
                print(
                    "Modelo sugerido: \(classification.model.title)"
                        + (classification.confident ? "" : " (confiança baixa, sem sugestão)"))
                print("Justificativa: \(classification.reason)")
                print("Título: \(classification.title)")
            } else {
                print("Classificação indisponível.")
            }
            let url = try AtaStore.create(
                meta: MeetingMeta(start: date, duration: job.durationSeconds), transcript: transcript,
                classification: classification, in: outURL)
            var models: [SummaryModel] = [classification?.suggestion ?? .geral]
            if let asked = value(after: "--model") {
                if asked == "all" {
                    models = SummaryModel.allCases
                } else if let model = SummaryModel(rawValue: asked) {
                    models = [model]
                } else {
                    print("Modelo desconhecido: \(asked)")
                    return 2
                }
            }
            for model in models {
                print("Gerando o resumo (\(model.title))...")
                try await SummaryService.shared.show(model, for: url)
            }
            print("Ata: \(url.path)")
            return 0
        } catch {
            print("Erro: \(error.localizedDescription)")
            return 1
        }
    }
}
