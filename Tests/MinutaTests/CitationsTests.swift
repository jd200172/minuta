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

    func testWindowTakesOnlyTheCitedSegment() {
        let segments = TranscriptSegment.parse(sample)
        let rows = TranscriptSegment.window(around: "t-000004", in: segments)
        XCTAssertEqual(rows.map(\.segment.id), ["t-000004"])
        XCTAssertEqual(TranscriptSegment.window(around: "t-000002", in: segments).map(\.segment.id), ["t-000002"])
        XCTAssertTrue(TranscriptSegment.window(around: "t-999999", in: segments).isEmpty)
    }
}
