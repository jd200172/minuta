import XCTest

@testable import Minuta

final class ParticipantEditorTests: XCTestCase {
    private func sample(inferred: Bool = true) -> String {
        UserDefaults.standard.set("Juliano", forKey: Config.userNameKey)
        let meta = MeetingMeta(start: Date(timeIntervalSince1970: 1_790_000_000), duration: 60)
        let transcript = Transcript(segments: [
            Segment(id: "t-000002", speaker: "Juliano", start: 2, text: "Vamos adiar o lançamento."),
            Segment(id: "t-000010", speaker: "Participante 1", start: 10, text: "Aqui é o Roberto."),
            Segment(id: "t-000020", speaker: "Participante 2", start: 20, text: "Eu envio o relatório."),
            Segment(id: "t-000030", speaker: "Participante 10", start: 30, text: "Concordo."),
        ])
        let data = SummaryData(
            summary: "Participante 2 enviará o relatório. O Participante 10 concordou.",
            participants: inferred ? [.init(label: "Participante 1", name: "Roberto", sources: ["t-000010"])] : [],
            sections: [
                "decisions": [.init(title: nil, text: "Adiar. Participante 2 concordou.", sources: ["t-000002"])]
            ],
            actions: [
                .init(
                    text: "Enviar relatório", owner: "Participante 2", deadline: "não definido", sources: ["t-000020"])
            ],
            openPoints: [])
        return MinutesRenderer.render(meta: meta, title: "T", model: .decisao, data: data, transcript: transcript)
    }

    func testSpeakersAreClassified() {
        let speakers = ParticipantEditor.speakers(in: sample())
        XCTAssertEqual(speakers.map(\.label), ["Juliano", "Participante 1", "Participante 2", "Participante 10"])
        XCTAssertEqual(speakers.map(\.kind), [.unnamed, .inferred, .unnamed, .unnamed])
        XCTAssertEqual(speakers[1].name, "Roberto")
        XCTAssertEqual(speakers[2].time, "00:00:20")
    }

    func testNamingAVoiceReplacesTheLabelEverywhere() throws {
        let text = try ParticipantEditor.apply(["Participante 2": "Marina"], to: sample())
        let body = text.components(separatedBy: "\n---\n").last ?? ""
        XCTAssertFalse(body.contains("Participante 2"), "o rótulo só fica no cabeçalho, no mapeamento")
        XCTAssertTrue(text.contains("\n- Marina\n"))
        XCTAssertTrue(text.contains("Marina enviará o relatório."))
        XCTAssertTrue(text.contains("| Marina |"))
        XCTAssertTrue(text.contains("**[00:00:20] Marina:**"))
        XCTAssertTrue(text.contains("O Participante 10 concordou."), "Participante 10 não é Participante 1")
        XCTAssertTrue(text.contains(#"participantes: {"Participante 2":"Marina"}"#))
        XCTAssertTrue(text.contains("<a id=\"t-000020\"></a>"))
        let speaker = ParticipantEditor.speakers(in: text).first { $0.label == "Participante 2" }
        XCTAssertEqual(speaker?.kind, .manual)
        XCTAssertEqual(speaker?.name, "Marina")
    }

    func testClearingTheNameRestoresTheOriginalText() throws {
        let original = sample()
        let named = try ParticipantEditor.apply(["Participante 2": "Marina"], to: original)
        let restored = try ParticipantEditor.apply(["Participante 2": ""], to: named)
        XCTAssertEqual(restored, original)
    }

    func testTwoVoicesCannotShareAName() throws {
        let original = sample()
        XCTAssertThrowsError(
            try ParticipantEditor.apply(["Participante 2": "Marina", "Participante 10": "marina"], to: original))
        XCTAssertThrowsError(try ParticipantEditor.apply(["Participante 2": "Participante 10"], to: original))
        XCTAssertThrowsError(try ParticipantEditor.apply(["Participante 2": "Juliano"], to: original))
        let named = try ParticipantEditor.apply(["Participante 2": "Marina"], to: original)
        XCTAssertThrowsError(try ParticipantEditor.apply(["Participante 10": "Marina"], to: named))
    }

    func testRenamingAnInferredName() throws {
        let original = sample()
        let renamed = try ParticipantEditor.apply(["Participante 1": "Beto"], to: original)
        XCTAssertFalse(renamed.contains("Roberto"))
        XCTAssertTrue(renamed.contains("**[00:00:10] Beto:**"))
        XCTAssertTrue(renamed.contains("\n- Beto\n"))
        let cleared = try ParticipantEditor.apply(["Participante 1": ""], to: original)
        XCTAssertTrue(cleared.contains("- Participante 1 (sem nome identificado)"))
        XCTAssertTrue(cleared.contains("**[00:00:10] Participante 1:**"))
    }

    func testWordBoundaryAndMicrophoneVoice() throws {
        let original = sample(inferred: false)
        let text = try ParticipantEditor.apply(["Participante 1": "Ana", "Juliano": "Ju"], to: original)
        XCTAssertTrue(text.contains("**[00:00:10] Ana:**"))
        XCTAssertTrue(text.contains("**[00:00:30] Participante 10:**"), "Participante 10 fica como está")
        XCTAssertTrue(text.contains("\n- Ju\n"))
        XCTAssertTrue(text.contains("**[00:00:02] Ju:**"))
    }

    func testNoChangeReturnsTheSameText() throws {
        let original = sample()
        XCTAssertEqual(try ParticipantEditor.apply(["Participante 2": ""], to: original), original)
    }

    func testNameRules() {
        XCTAssertNil(ParticipantEditor.nameProblem(""))
        XCTAssertNil(ParticipantEditor.nameProblem("Ana-Maria D'Ávila Jr."))
        XCTAssertNotNil(ParticipantEditor.nameProblem("Ana | Maria"))
        XCTAssertNotNil(ParticipantEditor.nameProblem("**Ana**"))
        XCTAssertNotNil(ParticipantEditor.nameProblem(String(repeating: "a", count: 61)))
        XCTAssertTrue(ParticipantEditor.same("José", "jose"))
    }

    func testOldMicrophoneLineLosesItsNoteWhenEdited() throws {
        let old = sample().replacingOccurrences(of: "\n- Juliano\n", with: "\n- Juliano  (canal do microfone)\n")
        XCTAssertTrue(old.contains("(canal do microfone)"))
        let renamed = try ParticipantEditor.apply(["Juliano": "Ju"], to: old)
        XCTAssertTrue(renamed.contains("\n- Ju\n"))
        XCTAssertFalse(renamed.contains("canal do microfone"))
        let cleared = try ParticipantEditor.apply(["Juliano": ""], to: renamed)
        XCTAssertTrue(cleared.contains("\n- Juliano\n"), "a voz do microfone volta sem nota")
    }
}
