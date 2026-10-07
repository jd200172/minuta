# 0032. Transcrição em turnos de fala

Status: aceita; implementada
Data: 2026-10-05
Complementa: `docs/decisions/0019-collapsible-transcript-and-citation-balloons.md`, `docs/decisions/0030-segment-by-pause-and-length.md`.

## Contexto

A página de leitura mostrava cada segmento como uma linha, com o nome do falante em todas. Falas seguidas da mesma pessoa repetiam o nome e o espaçamento, e a troca de quem fala não se destacava. A segmentação (ADR 0030) e a limpeza (ADR 0031) reduzem a repetição na origem. Na reunião de 17 min medida, ainda restavam 27 sequências do mesmo falante.

## Decisão

Decisão: na página de leitura e no HTML exportado, segmentos consecutivos do mesmo falante formam um turno. O turno mostra o nome e o horário do primeiro segmento uma vez, e as frases seguem em parágrafo corrido. Motivo: lê-se como texto, e o nome só aparece quando muda quem fala. O usuário escolheu esta entre quatro alternativas (parágrafo corrido, balões, roteiro, cabeçalho com guia).

- Cada segmento continua sendo um `<span class="s" id="t-…">` dentro do parágrafo do turno, com o horário em `data-tip`. Citações, salto a um horário e realce do segmento escolhido seguem pelo mesmo ID.
- Entre turnos, 20 px. Dentro do turno, nenhum espaço extra.
- O agrupamento é só de apresentação. Segmentos, arquivos, janela de correção e áudio não mudam.

## Alternativas descartadas

- Balões de conversa: ocupam mais altura e são um desvio novo das HIG.
- Estilo roteiro, com o nome numa coluna: mantém uma linha por fala.
- Cabeçalho de turno com guia vertical e contagem de falas.

## Consequências

- O realce de um segmento (`:target`) cobre só a frase, dentro do parágrafo.
- O horário de cada frase aparece ao passar o mouse; só o do início do turno fica visível.
- Sem teste visual no app.
