import XCTest

@testable import Minuta

final class TranscriptCleanerTests: XCTestCase {
    private func transcript(_ items: [(String, String)]) -> Transcript {
        Transcript(
            segments: items.enumerated().map {
                Segment(
                    id: "t-\(String(format: "%06d", $0.offset))", speaker: "A", start: Double($0.offset),
                    text: $0.element.1)
            })
    }

    func testUsesACleanedSegmentAndKeepsTheRawText() {
        let t = transcript([("", "Tu tem tu tem aí um um um PPT.")])
        let result = TranscriptCleaner.apply([t.segments[0].id: "Tu tem aí um PPT."], to: t)
        XCTAssertEqual(result.segments[0].text, "Tu tem aí um PPT.")
        XCTAssertEqual(result.segments[0].raw, "Tu tem tu tem aí um um um PPT.")
    }

    func testRejectsAProposalThatAddsAWord() {
        let t = transcript([("", "Vamos adiar para janeiro.")])
        let result = TranscriptCleaner.apply([t.segments[0].id: "Vamos adiar para janeiro, certo."], to: t)
        XCTAssertEqual(result.segments[0].text, "Vamos adiar para janeiro.")
        XCTAssertNil(result.segments[0].raw)
    }

    func testRejectsAProposalThatDeletesMostOfALongSegment() {
        let text = "um dois três quatro cinco seis sete oito nove dez"
        let t = transcript([("", text)])
        let result = TranscriptCleaner.apply([t.segments[0].id: "um dois"], to: t)
        XCTAssertEqual(result.segments[0].text, text)
    }

    func testDropsAShortSegmentThatIsOnlyNoise() {
        let t = transcript([("", "Ãh."), ("", "Então vamos começar.")])
        let result = TranscriptCleaner.apply([t.segments[0].id: ""], to: t)
        XCTAssertEqual(result.segments.map(\.text), ["Então vamos começar."])
    }

    func testKeepsSegmentsTheModelDidNotReturn() {
        let t = transcript([("", "Primeiro."), ("", "Segundo.")])
        let result = TranscriptCleaner.apply([:], to: t)
        XCTAssertEqual(result.segments, t.segments)
    }

    func testSplitsLongTranscriptsIntoChunks() {
        let word = Array(repeating: "palavra", count: 1000).joined(separator: " ")
        let t = transcript([("", word), ("", word), ("", word)])
        let chunks = TranscriptCleaner.chunks(t.segments)
        XCTAssertEqual(chunks.map(\.count), [2, 1])
    }

    func testDecodesTheCleaningAnswer() throws {
        let json = #"{"segments":[{"id":"t-000001","text":"Oi."},{"id":"t-000002","text":""}]}"#
        XCTAssertEqual(try MinutesPrompt.decodeCleaning(json), ["t-000001": "Oi.", "t-000002": ""])
        XCTAssertThrowsError(try MinutesPrompt.decodeCleaning("{}"))
    }
}
