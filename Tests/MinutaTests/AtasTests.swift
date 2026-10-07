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

    func testConsecutiveLinesOfOneSpeakerShareATurn() {
        let md = """
            ## Transcrição

            <a id="t-000001"></a>**[00:00:01] Daiane:** Primeira.

            <a id="t-000005"></a>**[00:00:05] Daiane:** Segunda.

            <a id="t-000009"></a>**[00:00:09] Juliano:** Terceira.

            <a id="t-000012"></a>**[00:00:12] Daiane:** Quarta.

            """
        let html = MarkdownHTML.convert(md).html
        XCTAssertEqual(html.components(separatedBy: "<div class=\"turn\">").count - 1, 3)
        XCTAssertEqual(html.components(separatedBy: "<strong>Daiane</strong>").count - 1, 2)
        XCTAssertTrue(html.contains("Primeira.</span> <span class=\"s\" id=\"t-000005\""), "uma só frase corrida")
        XCTAssertEqual(
            html.components(separatedBy: "<div class=\"turn\">").count - 1,
            html.components(separatedBy: "</div>\n").count - 1
                - (html.components(separatedBy: "<div class=\"turnhd\">").count - 1),
            "todo turno fecha")
    }

    func testConversationPageShowsBubblesWithMineOnTheRight() {
        let md = """
            ---
            inicio: 2026-10-05T10:00:00-03:00
            ---
            # Ata

            ## Transcrição

            <a id="t-000001"></a>**[00:00:01] Juliano:** Oi.

            <a id="t-000005"></a>**[00:00:05] Daiane:** Oi, tudo bem?

            <a id="t-000009"></a>**[00:00:09] Daiane:** Vamos começar.

            """
        let html = ConversationHTML.page(markdown: md, mine: "Juliano")
        XCTAssertTrue(html.contains("<div class=\"b me tail\" id=\"t-000001\">Oi."))
        XCTAssertEqual(
            html.components(separatedBy: "<div class=\"n\">Daiane</div>").count - 1, 1, "nome só no 1º balão")
        XCTAssertTrue(html.contains("id=\"t-000009\">Vamos começar."))
        XCTAssertFalse(html.contains("<div class=\"n\">Juliano"))
        XCTAssertEqual(html.components(separatedBy: "class=\"day\"").count - 1, 1)
    }

    func testChatButtonOpensTheConversationWindow() {
        let md = "# Ata\n\n## Resumo\n\nTexto.\n"
        let controls = MarkdownHTML.Controls(shown: nil, generating: nil, hint: "", selected: nil)
        let html = MarkdownHTML.convert(md, controls: controls).html
        XCTAssertTrue(html.contains("href=\"minuta://conversation\""))
        XCTAssertFalse(html.contains("aria-pressed"))
    }

    func testTranscriptLineGetsAnchorAndTime() {
        let md = "<a id=\"t-000010\"></a>**[00:00:10] Participante 1:** Oi <b>x</b>\n"
        let html = MarkdownHTML.convert(md).html
        XCTAssertTrue(html.contains("<span class=\"s\" id=\"t-000010\" data-tip=\"00:00:10\">"))
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

final class ReadingBarTests: XCTestCase {
    private let page =
        "---\ninicio: 2026-09-30T14:02:00-03:00\nduracao_segundos: 60\nmodelo: decisao\n---\n\n# Título & <b>\n\n"
        + "## Resumo\nTexto.\n\n## Participantes\n- Eu\n\n## Decisões\n- D.\n\n## Alternativas descartadas\nNenhuma.\n\n"
        + "## Itens de ação\nNenhuma.\n\n## Pontos em aberto\nNenhum.\n\n## Transcrição\n"
        + "<a id=\"t-000001\"></a>**[00:00:01] Eu:** Oi.\n"

    private func controls(generating: SummaryModel? = nil, selected: String? = nil) -> MarkdownHTML.Controls {
        MarkdownHTML.Controls(shown: .decisao, generating: generating, hint: "Aviso <de estado>", selected: selected)
    }

    func testHeaderHasFourBlocksInOrder() {
        let html = MarkdownHTML.convert(page, controls: controls()).html
        XCTAssertTrue(html.contains("id=\"mdl\" href=\"minuta://models\""))
        XCTAssertTrue(html.contains("<span class=\"lb\">Modelo</span>Decisão"))
        XCTAssertTrue(html.contains("href=\"minuta://export/html\""))
        XCTAssertTrue(html.contains("href=\"minuta://export/pdf\""))
        XCTAssertFalse(html.contains("minuta://export/mail"), "o e-mail aparece, mas não é link")
        XCTAssertTrue(html.contains("class=\"act off\" data-tip=\"Enviar por e-mail (em breve)\""))
        XCTAssertTrue(html.contains("aria-disabled=\"true\""))
        XCTAssertFalse(html.contains("minuta://model/"), "o modelo é escolhido no menu nativo")
        XCTAssertTrue(html.contains("href=\"minuta://title\""))
        XCTAssertTrue(html.contains("<span id=\"ti\">Título &amp; &lt;b&gt;</span>"))
        XCTAssertTrue(html.contains("Aviso &lt;de estado&gt;"), "o texto da linha é escapado")
        let order = [
            html.range(of: "<h1>")!.lowerBound, html.range(of: "class=\"bar\"")!.lowerBound,
            html.range(of: "class=\"mdlrow\"")!.lowerBound, html.range(of: "class=\"hint\"")!.lowerBound,
            html.range(of: "class=\"toc\"")!.lowerBound, html.range(of: ">Resumo</h2>")!.lowerBound,
        ]
        XCTAssertEqual(order, order.sorted(), "título, data e ícones, modelo, aviso, chips, seções")
        let bar = html.components(separatedBy: "class=\"bar\"")[1].components(separatedBy: "</div>")[0]
        XCTAssertTrue(bar.contains("class=\"sub\""), "a data e os ícones são o mesmo bloco")
        XCTAssertFalse(bar.contains("class=\"dv\""), "sem traço entre a data e os ícones")
        XCTAssertLessThan(
            bar.range(of: "class=\"sub\"")!.lowerBound, bar.range(of: "class=\"acts\"")!.lowerBound,
            "os ícones ficam logo abaixo da data")
        XCTAssertTrue(bar.contains("minuta://export/pdf"), "os ícones são subordinados ao título")
        XCTAssertFalse(bar.contains("id=\"mdl\""), "o botão de modelo fica fora desse bloco")
    }

    func testWhileGeneratingTheFormatButtonIsNotALink() {
        let html = MarkdownHTML.convert(page, controls: controls(generating: .geral)).html
        XCTAssertFalse(html.contains("minuta://models"))
        XCTAssertTrue(html.contains("<span class=\"mdl busy\" id=\"mdl\"><span class=\"lb\">Modelo</span>Geral"))
        XCTAssertTrue(html.contains("class=\"sp\""))
    }

    func testWithoutSummaryTheButtonAsksToChoose() {
        let html = MarkdownHTML.convert(page, controls: .init(shown: nil, generating: nil, hint: "")).html
        XCTAssertTrue(html.contains("<span class=\"lb\">Modelo</span>Escolher"))
        XCTAssertFalse(html.contains("class=\"hint\""), "sem aviso, não há linha")
    }

    func testSectionChipsPointAtEverySectionAndTheSelectedOneIsFilled() {
        let html = MarkdownHTML.convert(page, controls: controls(selected: "Decisões")).html
        let toc = html.components(separatedBy: "<nav class=\"toc\"")[1].components(separatedBy: "</nav>")[0]
        let titles = MarkdownHTML.sectionTitles(page)
        XCTAssertEqual(titles.count, 7)
        for (index, title) in titles.enumerated() {
            XCTAssertTrue(toc.contains("href=\"minuta://goto/\(index)\">\(MarkdownHTML.escape(title))</a>"), title)
        }
        XCTAssertEqual(toc.components(separatedBy: "<a ").count - 1, titles.count)
        XCTAssertEqual(toc.components(separatedBy: "class=\"on\"").count - 1, 1, "só o chip da seção mostrada")
        XCTAssertTrue(toc.contains("<a class=\"on\" aria-current=\"true\" href=\"minuta://goto/2\">Decisões</a>"))
        XCTAssertFalse(toc.contains("<span"), "sem grupos nem traços")
        XCTAssertFalse(toc.contains("Ir para"), "sem rótulo")
    }

    func testPageHasAFixedHeadOverAPaneWithEverySection() {
        let html = MarkdownHTML.convert(page, controls: controls(selected: "Decisões")).html
        let titles = MarkdownHTML.sectionTitles(page)
        for (index, title) in titles.enumerated() {
            let count = title == "Transcrição" ? "<span class=\"ct\">1 segmento</span>" : ""
            XCTAssertTrue(html.contains("<h2 id=\"s-\(index)\">\(MarkdownHTML.escape(title))\(count)</h2>"), title)
        }
        XCTAssertTrue(html.contains("Texto."), "o texto do Resumo está na página")
        XCTAssertTrue(html.contains("<span class=\"s\" id=\"t-000001\""), "e a transcrição também")
        let order = [
            html.range(of: "<header class=\"head\">")!.lowerBound, html.range(of: "class=\"toc\"")!.lowerBound,
            html.range(of: "</header>")!.lowerBound, html.range(of: "<main class=\"pane\" id=\"pane\">")!.lowerBound,
            html.range(of: "<h2 id=\"s-0\">")!.lowerBound, html.range(of: "</main>")!.lowerBound,
        ]
        XCTAssertEqual(order, order.sorted(), "cabeçalho com os chips, depois o painel com as seções")
        XCTAssertTrue(html.contains("<body class=\"app\">"))
        XCTAssertTrue(html.contains(".pane { flex: 1;"), "o painel rola e o cabeçalho não")
    }

    func testFirstChipIsFilledWhenNothingOrAnUnknownTitleIsSelected() {
        for selected in [nil, "Não existe"] {
            let html = MarkdownHTML.convert(page, controls: controls(selected: selected)).html
            XCTAssertTrue(html.contains("<a class=\"on\" aria-current=\"true\" href=\"minuta://goto/0\">Resumo</a>"))
            XCTAssertEqual(html.components(separatedBy: "class=\"on\"").count - 1, 1)
        }
    }

    func testTooltipsUseDataTipAndNeverTheSystemTitle() {
        let html = MarkdownHTML.convert(page, renamable: true, controls: controls()).html
        XCTAssertFalse(html.contains("title=\""), "title mostraria o tooltip do sistema junto com o balão")
        for tip in ["Renomear", "Modelo de resumo", "Salvar como HTML", "Salvar como PDF"] {
            XCTAssertTrue(html.contains("data-tip=\"\(tip)\""), tip)
        }
    }

    func testModelTooltipsKeepTheirThreeLines() {
        for model in SummaryModel.allCases {
            let lines = model.tooltip.components(separatedBy: "\n")
            XCTAssertEqual(lines.count, 3, model.rawValue)
            XCTAssertTrue(lines[1].hasPrefix("Mostra"), "o menu usa a linha Mostra")
        }
    }

    func testPageIsACenteredCardWithoutWidthLimitOnTheBody() {
        let html = MarkdownHTML.convert(page).html
        XCTAssertTrue(html.contains("<div class=\"card\" id=\"card\">"), "o id deixa o app medir o card")
        XCTAssertTrue(html.contains(".card {"))
        XCTAssertTrue(html.contains("max-width: 760px; margin: 0 auto"))
        let body = html.components(separatedBy: "\n").first { $0.hasPrefix("body {") } ?? ""
        XCTAssertFalse(body.contains("max-width"))
    }

    func testWithoutControlsThereIsNoBarOrTitlePencil() {
        let html = MarkdownHTML.convert(page).html
        XCTAssertFalse(html.contains("class=\"bar\""))
        XCTAssertFalse(html.contains("class=\"toc\""))
        XCTAssertFalse(html.contains("minuta://title"))
        XCTAssertTrue(html.contains("<p class=\"sub\">"))
    }
}

final class ExportTests: XCTestCase {
    func testExportedPageIsStandaloneWithTheTranscriptIncluded() {
        let md =
            "---\ninicio: 2026-09-30T14:02:00-03:00\nduracao_segundos: 60\nmodelo: decisao\n---\n\n# T\n\n"
            + "## Decisões\n- D. [00:00:01](#t-000001)\n\n## Transcrição\n"
            + "<a id=\"t-000001\"></a>**[00:00:01] Eu:** Oi.\n"
        let html = AtaExport.html(md)
        XCTAssertFalse(html.contains("minuta://"), "nada depende do app")
        XCTAssertTrue(html.contains("<style>"), "CSS embutido")
        XCTAssertFalse(html.contains("<link"))
        XCTAssertTrue(html.contains("<span class=\"s\" id=\"t-000001\""), "a transcrição vai sempre")
        XCTAssertFalse(html.contains("sec hide"))
        XCTAssertFalse(html.contains("<script"))
        XCTAssertTrue(html.contains("<a class=\"chip\" href=\"#t-000001\">00:00:01</a>"), "citação vira âncora")
        XCTAssertTrue(html.contains("@media print"))
    }

    private let md =
        "---\ninicio: 2026-09-30T14:02:00-03:00\nduracao_segundos: 60\nmodelo: decisao\n---\n\n# T\n\n"
        + "## Resumo\nTexto.\n\n## Decisões\n- D.\n\n## Transcrição\n"
        + "<a id=\"t-000001\"></a>**[00:00:01] Eu:** Oi.\n"

    func testExportedHTMLHasEverySectionCollapsibleAndClosed() {
        let html = AtaExport.html(md)
        XCTAssertEqual(html.components(separatedBy: "<details class=\"dt\" id=\"s-").count - 1, 3)
        XCTAssertEqual(html.components(separatedBy: "</details>").count - 1, 3, "cada seção fecha")
        XCTAssertFalse(html.contains("<details open"), "ao abrir, tudo fechado")
        XCTAssertFalse(html.contains(" open>"))
        XCTAssertTrue(html.contains("<summary>"))
        XCTAssertTrue(html.contains("1 segmento"), "a transcrição diz quantos segmentos tem")
        XCTAssertFalse(html.contains("minuta://"))
        let transcript = html.components(separatedBy: "<details class=\"dt\" id=\"s-2\">")[1]
        XCTAssertTrue(transcript.contains("id=\"t-000001\""), "a fala fica dentro da seção Transcrição")
    }

    func testExportedPDFHasNoCollapsibleSections() {
        let html = AtaExport.html(md, collapsible: false)
        XCTAssertFalse(html.contains("<details"), "seção fechada não sairia na impressão")
        XCTAssertTrue(html.contains("id=\"t-000001\""))
        XCTAssertTrue(html.contains("<h2 id=\"s-0\">Resumo</h2>"))
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
