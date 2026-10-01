import XCTest

@testable import Minuta

final class MinutesTests: XCTestCase {
    private let job = Job(
        id: "20260930-140200", startedAt: Date(timeIntervalSince1970: 1_790_000_000),
        durationSeconds: 253, stage: .minuting, micOffset: 0, systemOffset: 0, lastError: nil)

    private func words(_ items: [(String, String?, Double, Double)]) -> [Word] {
        items.map { Word(text: $0.0, speaker: $0.1, start: $0.2, end: $0.3) }
    }

    func testBuilderSeparatesSpeakersAndOrdersByTime() {
        UserDefaults.standard.set("Juliano", forKey: Config.userNameKey)
        let mic = (text: "Bom dia", words: words([("Bom", nil, 0.0, 0.3), ("dia", nil, 0.4, 0.7)]))
        let system = (
            text: "",
            words: words([
                ("Oi", "spk_7", 1.0, 1.2), ("pessoal", "spk_7", 1.3, 1.6),
                ("Claro", "spk_3", 2.0, 2.4),
            ])
        )
        let transcript = TranscriptBuilder.build(mic: mic, system: system, micOffset: 0, systemOffset: 0)
        XCTAssertEqual(transcript.segments.map(\.speaker), ["Juliano", "Participante 1", "Participante 2"])
        XCTAssertEqual(transcript.segments.map(\.id), ["t-000000", "t-000001", "t-000002"])
        XCTAssertEqual(transcript.segments[1].text, "Oi pessoal")
    }

    func testBuilderKeepsIDsUniqueWhenSegmentsStartInTheSameSecond() {
        let mic = (text: "a", words: words([("a", nil, 5.1, 5.2)]))
        let system = (text: "b", words: words([("b", "spk_1", 5.4, 5.5)]))
        let transcript = TranscriptBuilder.build(mic: mic, system: system, micOffset: 0, systemOffset: 0)
        XCTAssertEqual(Set(transcript.segments.map(\.id)).count, 2)
    }

    func testRendererValidatesSourcesAndNames() {
        UserDefaults.standard.set("Juliano", forKey: Config.userNameKey)
        let transcript = Transcript(segments: [
            Segment(id: "t-000010", speaker: "Participante 1", start: 10, text: "Aqui é a Marina."),
            Segment(id: "t-000020", speaker: "Juliano", start: 20, text: "Vamos adiar para o dia quinze."),
            Segment(id: "t-000030", speaker: "Participante 2", start: 30, text: "Bom dia."),
        ])
        let data = MinutesData(
            title: "Teste", summary: "Resumo.",
            participants: [
                .init(label: "Participante 1", name: "Marina", sources: ["t-000010"]),
                .init(label: "Participante 2", name: "Roberto", sources: ["t-999999"]),
            ],
            decisions: [
                .init(text: "Adiar o lançamento", sources: ["t-000020"]),
                .init(text: "Decisão inventada", sources: ["t-999999"]),
            ],
            actions: [
                .init(
                    text: "Enviar | texto", owner: "Participante 1", deadline: "não definido",
                    sources: ["t-000010"])
            ],
            openPoints: [], topics: [])
        let md = MinutesRenderer.render(data, transcript: transcript, job: job)

        XCTAssertTrue(md.contains("- Marina (Participante 1, nome inferido em [00:00:10](#t-000010))"))
        XCTAssertTrue(
            md.contains("- Participante 2 (sem nome identificado)"), "nome sem evidência válida deve ser ignorado")
        XCTAssertTrue(md.contains("- Adiar o lançamento [00:00:20](#t-000020)"))
        XCTAssertTrue(md.contains("- Decisão inventada sem evidência na transcrição"))
        XCTAssertTrue(md.contains("| Enviar \\| texto | Marina (Participante 1) | não definido |"))
        XCTAssertTrue(md.contains("<a id=\"t-000010\"></a>**[00:00:10] Marina (Participante 1):**"))
        XCTAssertTrue(md.contains("\n- Juliano\n"))
        XCTAssertFalse(md.contains("canal do microfone"))
    }
}

final class EnvTests: XCTestCase {
    func testParseHandlesCommentsQuotesAndExport() {
        let values = Env.parse(
            """
            # comentário
            GOOGLE_API_KEY=abc123
            export ANTHROPIC_API_KEY = "sk-xyz"
            MINUTER_MODEL='claude-x'

            SEM_VALOR=
            linha sem igual
            """)
        XCTAssertEqual(values["GOOGLE_API_KEY"], "abc123")
        XCTAssertEqual(values["ANTHROPIC_API_KEY"], "sk-xyz")
        XCTAssertEqual(values["MINUTER_MODEL"], "claude-x")
        XCTAssertEqual(values["SEM_VALOR"], "")
        XCTAssertEqual(values.count, 4)
    }

    func testTemplateRoundTripsThroughParse() {
        let values = Env.parse(Env.template(google: "g-key", anthropic: "a-key"))
        XCTAssertEqual(values["GOOGLE_API_KEY"], "g-key")
        XCTAssertEqual(values["ANTHROPIC_API_KEY"], "a-key")
        XCTAssertEqual(values["TRANSCRIBER"], Config.defaultTranscriber)
        XCTAssertEqual(values["MINUTER_MODEL"], Config.defaultMinuterModel)
    }
}

final class ClockTests: XCTestCase {
    func testElapsedFormat() {
        XCTAssertEqual(Fmt.elapsed(0), "00:00")
        XCTAssertEqual(Fmt.elapsed(754.9), "12:34")
        XCTAssertEqual(Fmt.elapsed(3725), "1:02:05")
    }
}

final class ErrorMessageTests: XCTestCase {
    func testRejectedKeyOpensSettings() {
        let error = AppError.http(status: 401, provider: .google, body: Data())
        XCTAssertEqual(error.fix, .keys)
        XCTAssertTrue(error.message.contains("GOOGLE_API_KEY"))
        XCTAssertTrue(error.message.hasPrefix("Google:"))
    }

    func testRateLimitDoesNotExposeRawBody() {
        let body = Data(#"{"error":{"message":"Rate limit exceeded for model gemini-3.5-transcribe"}}"#.utf8)
        let error = AppError.http(status: 429, provider: .google, body: body)
        XCTAssertFalse(error.message.contains("gemini-3.5-transcribe"))
        XCTAssertEqual(error.fix, .none)
    }

    func testOtherStatusIncludesApiMessage() {
        let body = Data(#"{"error":{"message":"Campo inválido"}}"#.utf8)
        let error = AppError.http(status: 400, provider: .anthropic, body: body)
        XCTAssertTrue(error.message.contains("Campo inválido"))
        XCTAssertTrue(error.message.contains("400"))
    }

    func testOfflineMapsToPlainMessage() {
        let error = AppError.from(URLError(.notConnectedToInternet))
        XCTAssertEqual(error.message, "Sem conexão com a internet.")
    }
}
