import XCTest

@testable import Minuta

final class AtaStoreTests: XCTestCase {
    private var dir: URL!
    private let meta = MeetingMeta(start: Date(timeIntervalSince1970: 1_790_000_000), duration: 240)

    override func setUpWithError() throws {
        UserDefaults.standard.set("Juliano", forKey: Config.userNameKey)
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("minuta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private let transcript = Transcript(segments: [
        Segment(id: "t-000002", speaker: "Juliano", start: 2, text: "Vamos adiar o lançamento."),
        Segment(id: "t-000010", speaker: "Participante 1", start: 10, text: "Eu envio o relatório."),
    ])

    private func classification() -> Classification {
        Classification(
            model: .decisao, confident: true, reason: "Duas decisões fechadas.", title: "Adiamento do lançamento")
    }

    private func decisionSummary() -> SummaryData {
        SummaryData(
            summary: "Lançamento adiado.", participants: [],
            sections: ["decisions": [.init(title: nil, text: "Adiar o lançamento", sources: ["t-000002"])]],
            actions: [
                .init(
                    text: "Enviar relatório", owner: "Participante 1", deadline: "não definido", sources: ["t-000010"])
            ],
            openPoints: [])
    }

    private func generalSummary() -> SummaryData {
        SummaryData(
            summary: "Conversa curta.", participants: [],
            sections: ["topics": [.init(title: "Lançamento", text: "Foi adiado.", sources: ["t-000002"])]],
            actions: [], openPoints: [])
    }

    func testNewMeetingHasNoSummaryAndKeepsTheClassification() throws {
        let url = try AtaStore.create(meta: meta, transcript: transcript, classification: classification(), in: dir)
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(url.lastPathComponent.hasSuffix(" Adiamento do lançamento.md"))
        XCTAssertTrue(text.contains("resumo: nenhum"))
        XCTAssertTrue(text.contains("titulo: Adiamento do lançamento"))
        XCTAssertTrue(text.contains(MinutesRenderer.noSummaryText))
        XCTAssertFalse(text.contains("## Itens de ação"))
        XCTAssertTrue(text.contains("<a id=\"t-000010\"></a>"))
        XCTAssertTrue(AtaStore.isManaged(text))
        XCTAssertNil(AtaStore.model(in: text))
        let sidecar = try AtaStore.loadSidecar(for: url, text: text).sidecar
        XCTAssertEqual(sidecar.classification?.suggestion, .decisao)
        XCTAssertEqual(sidecar.segments.count, 2)
        XCTAssertTrue(sidecar.summaries.isEmpty)
    }

    func testWithoutClassificationTheFileHasNoTitle() throws {
        let url = try AtaStore.create(meta: meta, transcript: transcript, classification: nil, in: dir)
        XCTAssertEqual(url.lastPathComponent, Fmt.fileStem(meta.start) + ".md")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertNil(AtaStore.title(in: text))
        XCTAssertTrue(text.contains("# Sem título"))
    }

    func testCommitShowsTheSummaryAndKeepsOthersInTheSidecar() throws {
        let url = try AtaStore.create(meta: meta, transcript: transcript, classification: classification(), in: dir)
        try AtaStore.commit(decisionSummary(), model: .decisao, to: url)
        var text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("modelo: decisao"))
        XCTAssertFalse(text.contains("resumo: nenhum"))
        XCTAssertTrue(text.contains("## Decisões\n- Adiar o lançamento [00:00:02](#t-000002)"))
        XCTAssertTrue(text.contains("| Enviar relatório | Participante 1 |"))

        try AtaStore.commit(generalSummary(), model: .geral, to: url)
        text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("modelo: geral"))
        XCTAssertTrue(text.contains("### Lançamento\nFoi adiado."))
        XCTAssertFalse(text.contains("## Decisões"), "só o resumo escolhido aparece no arquivo")
        let sidecar = try AtaStore.loadSidecar(for: url, text: text).sidecar
        XCTAssertTrue(sidecar.has(.decisao))
        XCTAssertTrue(sidecar.has(.geral))

        try AtaStore.select(.decisao, in: url)
        text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("modelo: decisao"))
        XCTAssertTrue(text.contains("## Decisões"))
        XCTAssertThrowsError(try AtaStore.select(.informativa, in: url))
    }

    func testNamesGivenByTheUserSurviveAModelSwitch() throws {
        let url = try AtaStore.create(meta: meta, transcript: transcript, classification: classification(), in: dir)
        try AtaStore.commit(decisionSummary(), model: .decisao, to: url)
        var text = try String(contentsOf: url, encoding: .utf8)
        text = try ParticipantEditor.apply(["Participante 1": "Marina"], to: text)
        try text.write(to: url, atomically: true, encoding: .utf8)

        try AtaStore.commit(generalSummary(), model: .geral, to: url)
        text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("**[00:00:10] Marina:**"))
        XCTAssertTrue(text.contains(#"participantes: {"Participante 1":"Marina"}"#))
        try AtaStore.select(.decisao, in: url)
        text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("| Enviar relatório | Marina |"), "o rótulo do secundário vira o nome atual")
        let sidecar = try AtaStore.loadSidecar(for: url, text: text).sidecar
        XCTAssertEqual(sidecar.segments[1].speaker, "Participante 1", "o secundário guarda o rótulo original")
    }

    func testRenamingChangesTheFileButNotTheSidecar() throws {
        let url = try AtaStore.create(meta: meta, transcript: transcript, classification: classification(), in: dir)
        try AtaStore.commit(decisionSummary(), model: .decisao, to: url)
        let before = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }
        let renamed = try AtaStore.rename(url, to: "Novo: título/final")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(renamed.lastPathComponent.hasSuffix(" Novo - título final.md"))
        let text = try String(contentsOf: renamed, encoding: .utf8)
        XCTAssertTrue(text.contains("titulo: Novo: título/final"))
        XCTAssertTrue(text.contains("modelo: decisao"))
        let after = try FileManager.default.contentsOfDirectory(atPath: dir.path).filter { $0.hasSuffix(".json") }
        XCTAssertEqual(before, after)
        XCTAssertNoThrow(try AtaStore.loadSidecar(for: renamed, text: text))
        // An empty title goes back to the timestamp-only name.
        let bare = try AtaStore.rename(renamed, to: "  ")
        XCTAssertEqual(bare.lastPathComponent, Fmt.fileStem(meta.start) + ".md")
    }

    func testSidecarIsFoundByStartEvenIfTheNameChanges() throws {
        let url = try AtaStore.create(meta: meta, transcript: transcript, classification: nil, in: dir)
        let moved = dir.appendingPathComponent("outro nome.md")
        try FileManager.default.moveItem(at: url, to: moved)
        let text = try String(contentsOf: moved, encoding: .utf8)
        XCTAssertNoThrow(try AtaStore.loadSidecar(for: moved, text: text))
    }

    func testTwoMeetingsInTheSameMinuteGetOwnSidecars() throws {
        let first = try AtaStore.create(meta: meta, transcript: transcript, classification: nil, in: dir)
        let other = MeetingMeta(start: meta.start.addingTimeInterval(20), duration: 30)
        let second = try AtaStore.create(meta: other, transcript: transcript, classification: nil, in: dir)
        XCTAssertNotEqual(first, second)
        let a = try String(contentsOf: first, encoding: .utf8)
        let b = try String(contentsOf: second, encoding: .utf8)
        XCTAssertNotEqual(
            try AtaStore.loadSidecar(for: first, text: a).url, try AtaStore.loadSidecar(for: second, text: b).url)
    }

    func testTrashMovesBothFiles() throws {
        let url = try AtaStore.create(meta: meta, transcript: transcript, classification: nil, in: dir)
        let text = try String(contentsOf: url, encoding: .utf8)
        let sidecar = try AtaStore.loadSidecar(for: url, text: text).url
        try AtaStore.trash(url)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: sidecar.path))
    }

    func testOlderFilesAreNotManaged() {
        let old = "---\ninicio: 2026-09-30T14:02:00-03:00\nduracao_segundos: 253\n---\n\n# Antiga\n"
        XCTAssertFalse(AtaStore.isManaged(old))
    }
}

final class SummaryModelTests: XCTestCase {
    func testEveryModelHasSectionsWithUniqueKeys() {
        for model in SummaryModel.allCases {
            let keys = model.sections.map(\.key)
            XCTAssertFalse(keys.isEmpty)
            XCTAssertEqual(Set(keys).count, keys.count, model.rawValue)
        }
    }

    func testSchemaCarriesTheCoreAndTheModelSections() throws {
        for model in SummaryModel.allCases {
            let schema = MinutesPrompt.schema(for: model)
            let properties = try XCTUnwrap(schema["properties"] as? [String: Any])
            XCTAssertEqual(Set(properties.keys), ["summary", "participants", "sections", "actions", "open_points"])
            let sections = try XCTUnwrap(properties["sections"] as? [String: Any])
            let sectionProperties = try XCTUnwrap(sections["properties"] as? [String: Any])
            XCTAssertEqual(Set(sectionProperties.keys), Set(model.sections.map(\.key)))
            let data = try JSONSerialization.data(withJSONObject: schema)
            XCTAssertFalse(data.isEmpty)
        }
    }

    func testSystemPromptHasCommonRulesAndTheModelBlock() {
        for model in SummaryModel.allCases {
            let prompt = MinutesPrompt.system(for: model)
            XCTAssertTrue(prompt.contains("Use somente o que está na transcrição"))
            XCTAssertTrue(prompt.contains(model.focus))
            for spec in model.sections { XCTAssertTrue(prompt.contains("\"\(spec.key)\"")) }
        }
    }

    func testClassifierSchemaOffersEveryModel() throws {
        let properties = try XCTUnwrap(MinutesPrompt.classifierSchema["properties"] as? [String: Any])
        let model = try XCTUnwrap(properties["model"] as? [String: Any])
        XCTAssertEqual(Set(model["enum"] as? [String] ?? []), Set(SummaryModel.allCases.map(\.rawValue)))
        XCTAssertTrue(MinutesPrompt.classifierSystem.contains("Problemas e ideias"))
    }

    func testDecodeSummaryDropsSectionsOfOtherModels() throws {
        let json = """
            {"summary":"R","participants":[],"sections":{"decisions":[{"text":"a","sources":["t-1"]}],"progress":[]},
            "actions":[],"open_points":[]}
            """
        let data = try MinutesPrompt.decodeSummary(json, model: .decisao)
        XCTAssertEqual(Set(data.sections.keys), ["decisions"])
        XCTAssertThrowsError(try MinutesPrompt.decodeSummary("não é json", model: .geral))
    }

    func testDecodeClassificationWithoutConfidenceGivesNoSuggestion() throws {
        let json = #"{"model":"geral","confidence":"baixa","reason":" Pouco conteúdo. ","title":"Alinhamento"}"#
        let c = try MinutesPrompt.decodeClassification(json)
        XCTAssertEqual(c.model, .geral)
        XCTAssertNil(c.suggestion)
        XCTAssertEqual(c.reason, "Pouco conteúdo.")
        let sure = try MinutesPrompt.decodeClassification(
            #"{"model":"decisao","confidence":"alta","reason":"x","title":"y"}"#)
        XCTAssertEqual(sure.suggestion, .decisao)
        XCTAssertThrowsError(
            try MinutesPrompt.decodeClassification(#"{"model":"outro","confidence":"alta","reason":"","title":""}"#))
    }

    func testUserMessageCarriesGivenNames() {
        let transcript = Transcript(segments: [
            Segment(id: "t-000001", speaker: "Participante 1", start: 1, text: "Oi.")
        ])
        let text = MinutesPrompt.user(
            transcript: transcript, start: Date(timeIntervalSince1970: 1_790_000_000),
            names: ["Participante 1": "Marina"])
        XCTAssertTrue(text.contains("Nomes informados pelo usuário: Participante 1 = Marina."))
        XCTAssertTrue(text.contains("[t-000001] Participante 1: Oi."))
    }
}

final class AtaHeadModelTests: XCTestCase {
    func testHeadReadsTitleAndModelFromFrontMatter() {
        let head = AtaHead.parse(
            "---\ninicio: 2026-09-30T14:02:00-03:00\nduracao_segundos: 253\ntitulo: Do cabeçalho\nmodelo: acompanhamento\n---\n\n# Outro\n"
        )
        XCTAssertEqual(head.title, "Do cabeçalho")
        XCTAssertEqual(head.model, .acompanhamento)
        XCTAssertFalse(head.noSummary)
        let none = AtaHead.parse("---\ninicio: 2026-09-30T14:02:00-03:00\nresumo: nenhum\n---\n\n# Sem título\n")
        XCTAssertTrue(none.noSummary)
        XCTAssertNil(none.model)
    }
}

final class LegacyRenameTests: XCTestCase {
    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("minuta-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testRetitledReplacesTheHeadingOrAddsOne() {
        let withHeading = "---\ninicio: 2026-09-30T14:02:00-03:00\n---\n\n# Antigo\n\n## Resumo\nx\n"
        XCTAssertEqual(
            AtaStore.retitled(withHeading, to: "Novo"),
            "---\ninicio: 2026-09-30T14:02:00-03:00\n---\n\n# Novo\n\n## Resumo\nx\n")
        XCTAssertTrue(AtaStore.retitled(withHeading, to: "").contains("# Sem título"))
        let none = "---\ninicio: 2026-09-30T14:02:00-03:00\n---\n\n## Resumo\nx\n"
        XCTAssertTrue(AtaStore.retitled(none, to: "Novo").contains("---\n# Novo\n\n\n## Resumo"))
        XCTAssertEqual(AtaStore.retitled("texto solto", to: "T"), "# T\n\ntexto solto")
    }

    func testRenamingAnOlderAtaChangesHeadingAndFileNameOnly() throws {
        let url = dir.appendingPathComponent("2026-09-30 1402 Antiga.md")
        try "---\ninicio: 2026-09-30T14:02:00-03:00\nduracao_segundos: 60\n---\n\n# Antiga\n\n## Resumo\nTexto.\n"
            .write(to: url, atomically: true, encoding: .utf8)
        let renamed = try AtaStore.rename(url, to: "Reunião: nova")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertEqual(renamed.lastPathComponent, "2026-09-30 1402 Reunião - nova.md")
        let text = try String(contentsOf: renamed, encoding: .utf8)
        XCTAssertTrue(text.contains("# Reunião: nova"))
        XCTAssertTrue(text.contains("## Resumo\nTexto."))
        XCTAssertFalse(AtaStore.isManaged(text))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 1)
    }

    func testRenamingAManagedAtaWithoutItsSidecarFailsAndKeepsTheFile() throws {
        let url = dir.appendingPathComponent("2026-09-30 1402 Nova.md")
        try "---\ninicio: 2026-09-30T14:02:00-03:00\nresumo: nenhum\n---\n\n# Nova\n".write(
            to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AtaStore.rename(url, to: "Outro"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
    }

    func testSummaryLabelAndDurationForSorting() {
        let start = Date(timeIntervalSince1970: 1_790_000_000)
        let a = Ata(url: URL(fileURLWithPath: "/a.md"), start: start, title: "A", duration: 120, model: .decisao)
        let b = Ata(url: URL(fileURLWithPath: "/b.md"), start: start, title: "B", duration: nil, noSummary: true)
        let c = Ata(url: URL(fileURLWithPath: "/c.md"), start: start, title: "C", duration: nil, problem: .empty)
        XCTAssertEqual([a, b, c].map(\.summaryLabel), ["Decisão", "Sem resumo", "Arquivo vazio"])
        XCTAssertLessThan(b.durationSeconds, a.durationSeconds)
    }
}
