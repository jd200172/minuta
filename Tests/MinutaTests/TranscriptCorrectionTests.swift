import XCTest

@testable import Minuta

final class TranscriptCorrectionTests: XCTestCase {
    private var dir: URL!
    private let meta = MeetingMeta(start: Date(timeIntervalSince1970: 1_790_000_000), duration: 240)
    private let transcript = Transcript(segments: [
        Segment(id: "t-000002", speaker: "Juliano", start: 2, text: "Vamos adiar o lançamento."),
        Segment(id: "t-000010", speaker: "Participante 1", start: 10, text: "Eu envio o relatorio."),
        Segment(id: "t-000020", speaker: "Participante 1", start: 20, text: "Combinado então."),
    ])

    override func setUpWithError() throws {
        UserDefaults.standard.set("Juliano", forKey: Config.userNameKey)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("minuta-fix-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func newAta() throws -> URL {
        try AtaStore.create(
            meta: meta, transcript: transcript,
            classification: Classification(model: .geral, confident: true, reason: "r", title: "Reunião de teste"),
            in: dir, audioDir: dir.appendingPathComponent("audio"))
    }

    private func sidecar(_ url: URL) throws -> Sidecar {
        try AtaStore.loadSidecar(for: url, text: String(contentsOf: url, encoding: .utf8)).sidecar
    }

    private func summary() -> SummaryData {
        SummaryData(
            summary: "Lançamento adiado.", participants: [], sections: [:],
            actions: [
                .init(
                    text: "Enviar relatório", owner: "Participante 1", deadline: "não definido", sources: ["t-000010"])
            ],
            openPoints: [])
    }

    func testCorrectingTheTextKeepsTheOriginalAndRewritesTheAta() throws {
        let url = try newAta()
        try AtaStore.updateSegment("t-000010", text: "  Eu envio o relatório.  ", speaker: "Participante 1", in: url)
        let s = try sidecar(url)
        XCTAssertEqual(s.segments[1].text, "Eu envio o relatório.")
        XCTAssertEqual(s.original("t-000010")?.text, "Eu envio o relatorio.")
        let md = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(md.contains("**[00:00:10] Participante 1:** Eu envio o relatório."))
        XCTAssertTrue(md.contains("titulo: Reunião de teste"), "o título continua")
    }

    func testReplacingTheTranscriptDropsCorrectionsAndNamesAndOutdatesSummaries() throws {
        let url = try newAta()
        try AtaStore.commit(summary(), model: .geral, to: url)
        try AtaStore.updateSegment("t-000020", text: "Combinado.", speaker: "Participante 1", in: url)
        let text = try String(contentsOf: url, encoding: .utf8)
        let named = try ParticipantEditor.apply(["Participante 1": "Ana"], to: text)
        try named.write(to: url, atomically: true, encoding: .utf8)

        let fresh = Transcript(segments: [
            Segment(id: "t-000003", speaker: "Juliano", start: 3, text: "Adiamos o lançamento."),
            Segment(id: "t-000012", speaker: "Participante 1", start: 12, text: "Envio o relatório."),
        ])
        try AtaStore.replaceTranscript(fresh, in: url)

        let s = try sidecar(url)
        XCTAssertEqual(s.segments, fresh.segments)
        XCTAssertNil(s.originals)
        XCTAssertEqual(s.outdated, ["geral"])
        let md = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(md.contains("**[00:00:12] Participante 1:** Envio o relatório."))
        XCTAssertFalse(md.contains("Ana"))
        XCTAssertTrue(md.contains("modelo: geral"), "o modelo escolhido continua")
        XCTAssertTrue(md.contains("titulo: Reunião de teste"))
    }

    func testTheFirstOriginalIsKeptThroughSeveralCorrections() throws {
        let url = try newAta()
        try AtaStore.updateSegment("t-000020", text: "Combinado.", speaker: "Participante 1", in: url)
        try AtaStore.updateSegment("t-000020", text: "Combinado, então.", speaker: "Participante 1", in: url)
        XCTAssertEqual(try sidecar(url).original("t-000020")?.text, "Combinado então.")
    }

    func testNoChangeWritesNothing() throws {
        let url = try newAta()
        let before = try String(contentsOf: url, encoding: .utf8)
        try AtaStore.updateSegment("t-000002", text: "Vamos adiar o lançamento.", speaker: "Juliano", in: url)
        XCTAssertNil(try sidecar(url).originals)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), before)
    }

    func testAnEmptyTextIsRefused() throws {
        let url = try newAta()
        XCTAssertThrowsError(try AtaStore.updateSegment("t-000002", text: "   ", speaker: "Juliano", in: url))
    }

    func testChangingTheSpeakerKeepsTheChannelOfTheRecording() throws {
        let url = try newAta()
        try AtaStore.updateSegment("t-000020", text: "Combinado então.", speaker: "Juliano", in: url)
        let s = try sidecar(url)
        XCTAssertEqual(s.segments[2].speaker, "Juliano")
        XCTAssertTrue(s.isSystem(s.segments[2]), "a fala foi gravada pelo sistema e continua tocando daquele canal")
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("**[00:00:20] Juliano:** Combinado então."))
    }

    func testDeletingAndRestoringASegment() throws {
        let url = try newAta()
        try AtaStore.deleteSegment("t-000010", in: url)
        XCTAssertEqual(try sidecar(url).segments.map(\.id), ["t-000002", "t-000020"])
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("t-000010"))
        try AtaStore.restoreSegment("t-000010", in: url)
        let s = try sidecar(url)
        XCTAssertEqual(s.segments.map(\.id), ["t-000002", "t-000010", "t-000020"], "volta ao seu lugar no tempo")
        XCTAssertNil(s.originals)
    }

    func testRestoringUndoesACorrection() throws {
        let url = try newAta()
        try AtaStore.updateSegment("t-000002", text: "Vamos adiar.", speaker: "Participante 1", in: url)
        try AtaStore.restoreSegment("t-000002", in: url)
        let s = try sidecar(url)
        XCTAssertEqual(s.segments[0], transcript.segments[0])
    }

    func testACorrectionMarksTheSummariesOutdatedUntilRedone() throws {
        let url = try newAta()
        try AtaStore.commit(summary(), model: .geral, to: url)
        XCTAssertFalse(try sidecar(url).isOutdated(.geral))
        try AtaStore.updateSegment("t-000010", text: "Eu envio o relatório.", speaker: "Participante 1", in: url)
        XCTAssertTrue(try sidecar(url).isOutdated(.geral))
        XCTAssertTrue(
            try String(contentsOf: url, encoding: .utf8).contains("modelo: geral"), "o resumo continua sendo mostrado")
        try AtaStore.commit(summary(), model: .geral, to: url)
        XCTAssertNil(try sidecar(url).outdated)
    }

    func testDeletingACitedSegmentDropsTheCitation() throws {
        let url = try newAta()
        try AtaStore.commit(summary(), model: .geral, to: url)
        try AtaStore.deleteSegment("t-000010", in: url)
        let md = try String(contentsOf: url, encoding: .utf8)
        XCTAssertFalse(md.contains("](#t-000010)"))
        XCTAssertTrue(md.contains("sem evidência na transcrição"))
    }

    func testNamesGivenByTheUserSurviveACorrection() throws {
        let url = try newAta()
        let named = try ParticipantEditor.apply(
            ["Participante 1": "Marina"], to: String(contentsOf: url, encoding: .utf8))
        try named.write(to: url, atomically: true, encoding: .utf8)
        try AtaStore.updateSegment("t-000020", text: "Combinado, então.", speaker: "Participante 1", in: url)
        let md = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(md.contains("**[00:00:20] Marina:** Combinado, então."))
        XCTAssertEqual(try sidecar(url).segments[2].speaker, "Participante 1", "o secundário guarda o rótulo original")
    }

    func testTheMarkdownIsFoundByItsStartAfterARename() throws {
        let url = try newAta()
        let renamed = try AtaStore.rename(url, to: "Outro título")
        let inicio = try sidecar(renamed).inicio
        XCTAssertEqual(AtaStore.markdown(inicio: inicio, in: dir)?.lastPathComponent, renamed.lastPathComponent)
    }

    func testKeepingTheAudioRecordsTheOffsets() throws {
        let url = try newAta()
        let pending = dir.appendingPathComponent("pending")
        try FileManager.default.createDirectory(at: pending, withIntermediateDirectories: true)
        let mic = pending.appendingPathComponent("mic.m4a")
        try Data("x".utf8).write(to: mic)
        AtaStore.keepAudio(
            mic: mic, system: nil, offsets: .init(mic: 0.4, system: 0), forMarkdown: url,
            audioDir: dir.appendingPathComponent("audio"))
        XCTAssertEqual(try sidecar(url).audioOffsets, .init(mic: 0.4, system: 0))
    }
}
