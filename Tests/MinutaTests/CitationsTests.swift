import XCTest

@testable import Minuta

private let sample = """
    ---
    inicio: 2026-10-01T14:30:00-03:00
    duracao_segundos: 2520
    titulo: Orçamento
    modelo: decisao
    ---

    # Orçamento

    ## Resumo
    Aprovado o corte. [00:00:04](#t-000004)

    ## Participantes
    - Juliano
    - Participante 1 (sem nome identificado)

    ## Itens de ação
    | Ação | Responsável | Prazo | Origem |
    |---|---|---|---|
    | Enviar a planilha \\| revisada | Juliano | 2026-10-08 | [00:00:04](#t-000004) |

    ## Transcrição
    <a id="t-000002"></a>**[00:00:02] Participante 1:** O corte fecha em 8%?

    <a id="t-000004"></a>**[00:00:04] Juliano:** Fecha. Mando a planilha.

    <a id="t-000009"></a>**[00:00:09] Participante 1:** Perfeito.

    <a id="t-000015"></a>**[00:00:15] Juliano:** Combinado.

    """

final class TranscriptSegmentTests: XCTestCase {
    func testParseReadsEverySegment() {
        let segments = TranscriptSegment.parse(sample)
        XCTAssertEqual(segments.map(\.id), ["t-000002", "t-000004", "t-000009", "t-000015"])
        XCTAssertEqual(segments[1].clock, "00:00:04")
        XCTAssertEqual(segments[1].speaker, "Juliano")
        XCTAssertEqual(segments[1].text, "Fecha. Mando a planilha.")
    }

    func testWindowTakesTheCitedSegmentAndOneOnEachSide() {
        let rows = TranscriptSegment.window(around: "t-000004", in: TranscriptSegment.parse(sample))
        XCTAssertEqual(rows.map(\.segment.id), ["t-000002", "t-000004", "t-000009"])
        XCTAssertEqual(rows.map(\.cited), [false, true, false])
    }

    func testWindowAtTheEdgesHasOnlyOneNeighbour() {
        let segments = TranscriptSegment.parse(sample)
        XCTAssertEqual(
            TranscriptSegment.window(around: "t-000002", in: segments).map(\.segment.id), ["t-000002", "t-000004"])
        XCTAssertEqual(
            TranscriptSegment.window(around: "t-000015", in: segments).map(\.segment.id), ["t-000009", "t-000015"])
        XCTAssertTrue(TranscriptSegment.window(around: "t-999999", in: segments).isEmpty)
    }
}

final class TranscriptStateTests: XCTestCase {
    private func defaults() -> UserDefaults {
        let name = "minuta.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    func testAMeetingNeverSeenOpensCollapsed() {
        XCTAssertTrue(TranscriptState.isCollapsed(sample, defaults: defaults()))
    }

    func testTheChoiceIsRememberedPerMeeting() {
        let store = defaults()
        TranscriptState.set(collapsed: false, for: sample, defaults: store)
        XCTAssertFalse(TranscriptState.isCollapsed(sample, defaults: store))
        let other = sample.replacingOccurrences(of: "14:30:00", with: "15:45:00")
        XCTAssertTrue(TranscriptState.isCollapsed(other, defaults: store), "outra reunião não herda o estado")
        TranscriptState.set(collapsed: true, for: sample, defaults: store)
        XCTAssertTrue(TranscriptState.isCollapsed(sample, defaults: store))
    }
}

final class TranscriptPageTests: XCTestCase {
    func testWithoutTheOptionsThePageIsAsInTheFile() {
        let html = MarkdownHTML.convert(sample).html
        XCTAssertFalse(html.contains("minuta://transcript"))
        XCTAssertFalse(html.contains("minuta://cite"))
        XCTAssertTrue(html.contains("<a class=\"chip\" href=\"#t-000004\">00:00:04</a>"))
        XCTAssertTrue(html.contains("<h2>Transcrição</h2>"))
    }

    func testCollapsedTranscriptHidesTheLinesBehindAToggle() {
        let html = MarkdownHTML.convert(sample, transcriptCollapsed: true).html
        XCTAssertTrue(html.contains("<h2 class=\"disc\"><a href=\"minuta://transcript\""))
        XCTAssertTrue(html.contains("aria-expanded=\"false\""))
        XCTAssertTrue(html.contains("4 segmentos"))
        XCTAssertTrue(html.contains("<div class=\"tr hide\">"))
        XCTAssertTrue(html.contains("id=\"t-000009\""), "as linhas continuam na página, para o salto")
        XCTAssertEqual(html.components(separatedBy: "<div class=\"tr").count, 2)
        XCTAssertTrue(html.contains("</div>\n</div></body>"), "o bloco da transcrição fecha antes do card")
    }

    func testExpandedTranscriptShowsTheLines() {
        let html = MarkdownHTML.convert(sample, transcriptCollapsed: false).html
        XCTAssertTrue(html.contains("<h2 class=\"disc open\">"))
        XCTAssertTrue(html.contains("aria-expanded=\"true\""))
        XCTAssertTrue(html.contains("<div class=\"tr\">"))
        XCTAssertFalse(html.contains("tr hide"))
    }

    func testCitationChipsOpenABalloonAndEachHasItsOwnId() {
        let html = MarkdownHTML.convert(sample, citations: true).html
        XCTAssertTrue(html.contains("id=\"rf-0\" href=\"minuta://cite/t-000004/0\""))
        XCTAssertTrue(html.contains("id=\"rf-1\" href=\"minuta://cite/t-000004/1\""), "resumo e tabela: dois chips")
        XCTAssertFalse(html.contains("href=\"#t-000004\""))
        XCTAssertTrue(html.contains("data-tip=\"Ver o trecho da conversa\""))
        XCTAssertTrue(html.contains("00:00:04</a>"))
    }
}

@MainActor
final class BalloonTextTests: XCTestCase {
    func testOnlyTheModelLeadsAreSemibold() {
        let text = TipBalloon.styled("Serve para decidir\nMostra as decisões\nUse quando há prazo")
        var bold: [String] = []
        text.enumerateAttribute(.font, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            if let font = value as? NSFont, NSFontManager.shared.weight(of: font) > 6 {
                bold.append((text.string as NSString).substring(with: range))
            }
        }
        XCTAssertEqual(bold, ["Serve para", "Mostra", "Use quando"])
        let plain = TipBalloon.styled("Mostrar no Finder")
        var heavy = false
        plain.enumerateAttribute(.font, in: NSRange(location: 0, length: plain.length)) { value, _, _ in
            if let font = value as? NSFont, NSFontManager.shared.weight(of: font) > 6 { heavy = true }
        }
        XCTAssertFalse(heavy, "\"Mostrar no Finder\" não é um modelo e não leva negrito")
    }
}
