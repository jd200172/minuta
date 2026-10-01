import XCTest

@testable import Minuta

final class AtaNameTests: XCTestCase {
    func testSanitizeRemovesReservedCharacters() {
        XCTAssertEqual(AtaName.sanitize("Reunião de teste: adiamento"), "Reunião de teste - adiamento")
        XCTAssertEqual(AtaName.sanitize("  a/b\\c*d?  "), "a b c d")
        XCTAssertEqual(AtaName.sanitize("..."), "")
        XCTAssertLessThanOrEqual(AtaName.sanitize(String(repeating: "x", count: 200)).count, 80)
    }

    func testParseNewOldAndCollisionNames() {
        let start = AtaName.parse("2026-10-01 1137 Reunião de teste")
        XCTAssertEqual(start?.title, "Reunião de teste")
        XCTAssertEqual(AtaName.parse("2026-10-01 1137 Reunião de teste (2)")?.title, "Reunião de teste")
        XCTAssertNil(AtaName.parse("2026-10-01 1137")?.title)
        XCTAssertNil(AtaName.parse("2026-10-01 1137 2")?.title, "sufixo numérico antigo não é título")
        XCTAssertNil(AtaName.parse("anotações pessoais"))
    }

    func testStemRoundTrips() {
        let date = Date(timeIntervalSince1970: 1_790_000_000)
        let stem = AtaName.stem(start: date, title: "Plano: lançamento")
        XCTAssertEqual(AtaName.parse(stem)?.title, "Plano - lançamento")
        XCTAssertEqual(AtaName.stem(start: date, title: "///"), Fmt.fileStem(date))
    }
}

final class AtaScanTests: XCTestCase {
    func testScanSortsNewestFirstAndReadsHeads() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("atas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        func write(_ name: String, _ text: String) throws {
            try text.write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }
        try write(
            "2026-09-30 1402 Alinhamento.md",
            "---\ninicio: 2026-09-30T14:02:00-03:00\nduracao_segundos: 240\n---\n\n# Alinhamento do lançamento\n")
        try write(
            "2026-10-01 1137.md", "---\ninicio: 2026-10-01T11:37:25-03:00\nduracao_segundos: 13\n---\n\n# Teste\n")
        try write("anotações.md", "# Notas pessoais\n")
        try write("2026-10-01 0900 Sem cabeçalho.md", "sem frontmatter")

        let result = AtaLibrary.scan(dir)
        XCTAssertEqual(result.folder, .ok)
        let atas = result.atas
        XCTAssertEqual(
            atas.map(\.title), ["Teste", "2026-10-01 0900 Sem cabeçalho", "Alinhamento do lançamento"])
        XCTAssertEqual(atas[0].duration, 13)
        XCTAssertEqual(atas[1].problem, .noHeader)
        XCTAssertEqual(atas[2].duration, 240)
    }

    func testScanFlagsEmptyAndUnreadableFilesAndIgnoresForeignOnes() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("atas-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let fm = FileManager.default
        fm.createFile(atPath: dir.appendingPathComponent("2026-09-30 1402 Vazia.md").path, contents: Data())
        fm.createFile(
            atPath: dir.appendingPathComponent("2026-09-30 0915 Binária.md").path,
            contents: Data([0xFF, 0xFE, 0xFA, 0x00, 0xC3, 0x28]))
        fm.createFile(atPath: dir.appendingPathComponent("lista.md").path, contents: Data())
        fm.createFile(atPath: dir.appendingPathComponent("notas.txt").path, contents: Data("x".utf8))

        let atas = AtaLibrary.scan(dir).atas
        XCTAssertEqual(atas.count, 2, "só arquivos com nome de ata são marcados")
        XCTAssertEqual(atas.first { $0.title.contains("Vazia") }?.problem, .empty)
        XCTAssertEqual(atas.first { $0.title.contains("Binária") }?.problem, .unreadable)
    }

    func testFolderStates() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("nao-existe-\(UUID().uuidString)")
        XCTAssertEqual(AtaLibrary.scan(missing).folder, .missing)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("vazia-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        XCTAssertEqual(AtaLibrary.scan(dir).folder, .ok)
        XCTAssertTrue(AtaLibrary.scan(dir).atas.isEmpty)
    }

    func testDecodeHeadToleratesACutMultiByteCharacter() {
        let full = Data("# Reunião".utf8)
        XCTAssertNotNil(AtaLibrary.decodeHead(full.dropLast(1)), "corte no meio do ã")
        XCTAssertNil(AtaLibrary.decodeHead(Data([0xFF, 0xFE, 0x00, 0xC3, 0x28])))
    }
}

final class MarkdownHTMLTests: XCTestCase {
    func testEscapesInjectedMarkup() {
        let html = MarkdownHTML.convert("# T\n\n## Resumo\n<script>alert(1)</script> & mais\n").html
        XCTAssertFalse(html.contains("<script>alert"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func testTranscriptLineGetsAnchorAndTime() {
        let md = "<a id=\"t-000010\"></a>**[00:00:10] Participante 1:** Oi <b>x</b>\n"
        let html = MarkdownHTML.convert(md).html
        XCTAssertTrue(html.contains("<p class=\"tl\" id=\"t-000010\">"))
        XCTAssertTrue(html.contains("<span class=\"tm\">00:00:10</span>"))
        XCTAssertTrue(html.contains("&lt;b&gt;x&lt;/b&gt;"))
    }

    func testSourcesBecomeChipsAndTableKeepsEscapedPipe() {
        let md = """
            # T

            ## Decisões
            - Adiar [00:00:07](#t-000007)

            ## Itens de ação
            | Ação | Responsável | Prazo | Origem |
            |---|---|---|---|
            | Enviar \\| texto | Marina | 02/10/2026 | [00:00:10](#t-000010) |
            """
        let html = MarkdownHTML.convert(md).html
        XCTAssertTrue(html.contains("<a class=\"chip\" href=\"#t-000007\">00:00:07</a>"))
        XCTAssertTrue(html.contains("<td>Enviar | texto</td>"))
        XCTAssertTrue(html.contains("<th>Responsável</th>"))
        XCTAssertFalse(html.contains("---"))
    }

    func testSubtitleFromFrontmatter() {
        let md = "---\ninicio: 2026-10-01T11:37:25-03:00\nduracao_segundos: 13\n---\n\n# Teste\n"
        let doc = MarkdownHTML.convert(md)
        XCTAssertEqual(doc.title, "Teste")
        XCTAssertTrue(doc.html.contains("13 s"))
    }

    func testParticipantsGetPencilsOnlyWhenRenamable() {
        let md = """
            # T

            ## Participantes
            - Juliano
            - Participante 1 (sem nome identificado)
            - Marina

            ## Transcrição
            <a id="t-000002"></a>**[00:00:02] Juliano:** Oi
            <a id="t-000010"></a>**[00:00:10] Participante 1:** Olá
            <a id="t-000020"></a>**[00:00:20] Marina:** Bom dia
            """
        XCTAssertFalse(MarkdownHTML.convert(md).html.contains("minuta://rename"))
        let html = MarkdownHTML.convert(md, renamable: true).html
        XCTAssertTrue(html.contains("<span id=\"sp-0\">Juliano</span>"))
        XCTAssertTrue(html.contains("href=\"minuta://rename/1\""))
        XCTAssertTrue(html.contains("<span id=\"sp-2\">Marina</span>"))
        XCTAssertEqual(html.components(separatedBy: "minuta://rename/").count - 1, 3)
    }
}

final class ModelChipsTests: XCTestCase {
    private let page =
        "---\ninicio: 2026-09-30T14:02:00-03:00\nduracao_segundos: 60\nmodelo: decisao\n---\n\n# Título & <b>\n\n## Resumo\nTexto.\n"

    private func controls(generating: SummaryModel? = nil, redo: Bool = true) -> MarkdownHTML.Controls {
        MarkdownHTML.Controls(
            chips: SummaryModel.allCases.map {
                .init(model: $0, selected: $0 == .decisao, has: $0 == .decisao || $0 == .geral)
            },
            generating: generating, hint: "Sugerido: Decisão. <motivo>", canRedo: redo)
    }

    func testChipsLinkToModelsAndMarkTheOnesWithSummary() {
        let html = MarkdownHTML.convert(page, controls: controls()).html
        for model in SummaryModel.allCases { XCTAssertTrue(html.contains("href=\"minuta://model/\(model.rawValue)\"")) }
        XCTAssertTrue(html.contains("class=\"mc on\" href=\"minuta://model/decisao\" data-tip=\""))
        XCTAssertTrue(html.contains("aria-current=\"true\""))
        XCTAssertEqual(html.components(separatedBy: "class=\"dt\"").count - 1, 2, "um ponto por modelo gerado")
        XCTAssertTrue(html.contains("href=\"minuta://redo\""))
        XCTAssertTrue(html.contains("href=\"minuta://title\""))
        XCTAssertTrue(html.contains("<span id=\"ti\">Título &amp; &lt;b&gt;</span>"))
        XCTAssertTrue(html.contains("Sugerido: Decisão. &lt;motivo&gt;"), "o texto da linha é escapado")
        let order = [
            html.range(of: "<h1>")!.lowerBound, html.range(of: "class=\"models\"")!.lowerBound,
            html.range(of: "<h2>Resumo</h2>")!.lowerBound,
        ]
        XCTAssertEqual(order, order.sorted(), "os chips ficam entre o título e o resumo")
    }

    func testWhileGeneratingChipsAreNotLinks() {
        let html = MarkdownHTML.convert(page, controls: controls(generating: .geral, redo: false)).html
        XCTAssertFalse(html.contains("minuta://model/"))
        XCTAssertFalse(html.contains("minuta://redo"))
        XCTAssertTrue(html.contains("class=\"sp\""))
        XCTAssertTrue(html.contains("mc off"))
    }

    func testEveryChipHasATooltipWithThreeLines() {
        for generating in [nil, SummaryModel.geral] {
            let html = MarkdownHTML.convert(page, controls: controls(generating: generating)).html
            for model in SummaryModel.allCases {
                let lines = model.tooltip.components(separatedBy: "\n")
                XCTAssertEqual(lines.count, 3, model.rawValue)
                XCTAssertTrue(lines[0].hasPrefix("Serve para"))
                XCTAssertTrue(lines[1].hasPrefix("Mostra"))
                XCTAssertTrue(lines[2].hasPrefix("Use quando"))
                XCTAssertTrue(
                    html.contains("data-tip=\"" + model.tooltip.replacingOccurrences(of: "\n", with: "&#10;") + "\""))
            }
        }
    }

    func testTooltipsUseDataTipAndNeverTheSystemTitle() {
        let html = MarkdownHTML.convert(page, renamable: true, controls: controls()).html
        XCTAssertFalse(html.contains("title=\""), "title mostraria o tooltip do sistema junto com o balão")
        for tip in ["Renomear", "Refazer este resumo", "Resumo gerado"] {
            XCTAssertTrue(html.contains("data-tip=\"\(tip)\""), tip)
        }
        XCTAssertTrue(html.contains("aria-label=\"Resumo gerado\""), "o ponto continua descrito para o VoiceOver")
    }

    func testPageIsACenteredCardWithoutWidthLimitOnTheBody() {
        let html = MarkdownHTML.convert(page).html
        XCTAssertTrue(html.contains("<div class=\"card\">"))
        XCTAssertTrue(html.contains(".card {"))
        XCTAssertTrue(html.contains("max-width: 760px; margin: 0 auto"))
        let body = html.components(separatedBy: "\n").first { $0.hasPrefix("body {") } ?? ""
        XCTAssertFalse(body.contains("max-width"))
    }

    func testWithoutControlsThereAreNoChipsOrTitlePencil() {
        let html = MarkdownHTML.convert(page).html
        XCTAssertFalse(html.contains("class=\"models\""))
        XCTAssertFalse(html.contains("minuta://title"))
    }
}

final class FinderDateTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Sao_Paulo")!
        return c
    }

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.timeZone = calendar.timeZone
        return f.date(from: s + "-03:00")!
    }

    func testTodayYesterdayAndOlderDates() {
        let now = date("2026-10-01T16:30:00")
        XCTAssertEqual(Fmt.finderDate(date("2026-10-01T09:06:00"), now: now, calendar: calendar), "Hoje às 09:06")
        XCTAssertEqual(Fmt.finderDate(date("2026-09-30T21:20:00"), now: now, calendar: calendar), "Ontem às 21:20")
        XCTAssertEqual(
            Fmt.finderDate(date("2026-09-28T16:30:00"), now: now, calendar: calendar), "28 de set. de 2026 às 16:30")
    }

    func testRowsSortByTheirColumns() {
        let a = Ata(
            url: URL(fileURLWithPath: "/a.md"), start: Date(timeIntervalSince1970: 100), title: "B", duration: 60,
            model: .decisao)
        let b = Ata(
            url: URL(fileURLWithPath: "/b.md"), start: Date(timeIntervalSince1970: 200), title: "A", duration: 30,
            noSummary: true)
        let job = Job(
            id: "j", startedAt: Date(timeIntervalSince1970: 300), durationSeconds: 10, stage: .transcribing,
            micOffset: 0, systemOffset: 0, lastError: nil)
        let rows = [ListRow(kind: .ata(a)), ListRow(kind: .ata(b)), ListRow(kind: .job(job, running: true))]
        XCTAssertEqual(
            rows.sorted(using: [KeyPathComparator(\ListRow.start, order: .reverse)]).map(\.id),
            [rows[2].id, rows[1].id, rows[0].id])
        XCTAssertEqual(rows.sorted(using: [KeyPathComparator(\ListRow.title)]).first?.title, "A")
        XCTAssertEqual(rows[2].title, "Gravação em processamento")
        XCTAssertEqual(rows[2].summaryLabel, "Transcrevendo…")
        XCTAssertTrue(rows[2].id.hasPrefix("job-"))
    }
}
