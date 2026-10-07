# 0029. Hierarquia tipográfica e cor da leitura

Status: aceita; implementada (revisada no mesmo dia). A regra de cor monocromática foi substituída pelo ADR 0033
Data: 2026-10-05
Complementa: `docs/decisions/0027-model-menu-section-chips-and-export.md` (chips de seção).

## Contexto

Na leitura, as chips de seção tinham 12 px e os títulos de seção 13 px em cinza, menores que o corpo (14 px). Os títulos não se destacavam do texto.

## Decisão

Decisão: chips de seção e títulos de seção usam o mesmo tamanho (15 px), o mesmo peso (600) e a mesma fonte do sistema. Motivo: os dois são o mesmo elemento visto de dois lados (índice e destino), e o tamanho acima do corpo cria a hierarquia título da ata (22 px), seção (15 px), corpo (14 px).

O título de seção passa de cinza para a cor do texto. A regra vale também para os resumos do HTML exportado (`details.dt > summary`). O contador de itens ao lado do título continua com 12 px.

## Revisão (2026-10-05)

Decisão: o título da ata passa a 28 px (peso 600, entrelinha 1,2) e as chips a peso 500; os títulos de seção continuam em 15 px e peso 600. Motivo: com 22 px o título ficava a 7 px do título de seção, e o peso 600 pesava nas chips.

Decisão: cor monocromática. As chips usam `CanvasText` a 8% de fundo (14% no hover); a da seção atual é preenchida com `CanvasText` e texto em `Canvas`. O azul fica só em links e horários. Motivo: o texto da ata é o conteúdo, e a cor não deve competir com ele.

Decisão: a regra monocromática vale para o app inteiro. Chips de horário e linha selecionada da página, do balão de citação e da janela de correção usam o texto a 8% e 10%. Links da página usam a cor do texto. Tag de modelo e "Sem resumo" na lista de atas, aviso de resumo desatualizado e "Corrigida" na janela de correção perdem a cor. Motivo: cor só onde é necessária.

Exceções que mantêm cor: erro e recusa (vermelho: falha, pasta ausente, permissão negada) e o estado do botão da barra de menus (ADR 0014).

Descartado: chips tintadas com a cor de destaque do sistema. Fica registrado em `STATUS.md` como decisão anterior não implementada; esta a substitui.

## Alternativas descartadas

- 22 px, igual ao título da ata: empata os dois níveis.
- 17 px: chips pesadas ao lado do botão "Modelo" e dos ícones, e cabeçalho fixo mais alto.

## Consequências

- O cabeçalho fixo fica mais alto. Em janela estreita, as chips quebram em duas linhas antes que hoje.
- Sem teste automatizado de aparência; falta ver no app.
