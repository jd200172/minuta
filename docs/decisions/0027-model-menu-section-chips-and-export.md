# 0027. Menu de modelo, chips de seção e exportação da ata

Status: aceita; implementada
Data: 2026-10-05
Substitui: as chips de modelo de resumo e o ícone de refazer da página de leitura (`docs/decisions/0017-summary-models-on-demand.md`, seção Interface). O restante do ADR 0017 continua valendo.
Complementa: `docs/decisions/0026-collapsible-sections-and-retranscribe.md` (seções colapsáveis).

## Contexto

O ADR 0017 pôs os quatro modelos de resumo como chips logo abaixo do título. No uso, o usuário lê as chips como assuntos ou trechos da ata, não como modelos de resumo. As chips não têm rótulo e ficam dentro do documento, perto dos títulos de seção. Um modelo e uma de suas seções podem ter quase o mesmo nome ("Decisão" e "Decisões").

À parte, o usuário pediu para salvar a ata como HTML e como PDF, e um botão de envio por e-mail para a próxima etapa.

## Decisão

**Menu de modelo.** As chips saem. Na linha da data, um botão com o rótulo "Modelo" e o nome do modelo de resumo atual abre um menu nativo (`NSMenu`) logo abaixo dele. O menu tem:
- os quatro modelos de resumo, com marca no atual;
- em cada item, uma segunda linha com o que o modelo mostra (a linha "Mostra" de `SummaryModel.tooltip`);
- "resumo gerado" ao lado de cada modelo que já tem resumo;
- um separador e "Refazer este resumo", que substitui o ícone de refazer.

Escolher um modelo funciona como a chip funcionava: troca na hora ou gera o resumo. Sem resumo, o botão diz "Escolher". Durante a geração, o botão deixa de ser link e mostra um indicador de progresso. A linha de sugestão continua abaixo da barra.

Decisão: botão na página que abre menu nativo. Motivo: a página roda sem JavaScript, então um `<select>` não teria efeito; o botão é um link `minuta://models`, e o app mede a posição dele e abre o menu.

**Chips de seção.** Abaixo da linha de sugestão, uma chip por seção `##` da ata, sem rótulo. O clique rola até a seção (`minuta://goto/N`, alvo `s-N`). Seção recolhida (ADR 0026) é expandida antes do salto. O título da seção pisca em azul por 1,6 s, por CSS.

As chips formam três grupos, separados por um traço vertical:
- abertura (Resumo, Participantes): cinza, com borda;
- seções do modelo de resumo atual: tinta azul;
- fechamento (Itens de ação, Pontos em aberto, Transcrição): cinza, com borda.

**Botões de exportação.** No fim da linha da data, alinhados à direita, três botões só com ícone e dica:
- "Enviar por e-mail (em breve)": visível e inativo. O envio é da próxima etapa e terá ADR próprio.
- "Salvar como HTML": um arquivo autônomo, com o CSS embutido.
- "Salvar como PDF": em páginas do tamanho de papel do sistema, com margem de 40 pt.

O conteúdo exportado é a ata do arquivo `.md`, com o modelo de resumo atual e as correções. Não leva a barra, os lápis nem as chips de seção. Todas as seções vão abertas, e a transcrição vai sempre. As citações viram âncoras para a linha da transcrição, sem balão. O PDF é impresso por uma `WKWebView` fora da tela, em aparência clara, com regras `@media print` (sem card, sem quebra dentro de uma fala).

**Desvio das HIG.** O botão de modelo imita um botão pop-up do macOS dentro da página, e o menu é nativo. As chips de seção são próprias. Os balões de dica e de citação mantêm a forma que vinha das chips de modelo (raio de 16 px), para não mudar a linguagem dos balões (ADR 0019).

## Alternativas descartadas

- Rótulo e controle de segmentos no lugar das chips: mantém as quatro opções à vista, mas ocupa a linha inteira e disputa espaço com as chips de seção.
- Frase de estado com "Trocar modelo": explica a sugestão, mas exige um clique a mais para ver as opções.
- Controle na barra de ferramentas da janela: tira o seletor do documento, mas fica longe da linha de sugestão.
- Cartões com a estrutura de cada modelo: ocupam mais altura e destoam da leitura.
- Só as chips das seções do modelo, sem as fixas: a linha fica curta, mas as chips sozinhas voltam a parecer as chips de modelo, e a transcrição perde o atalho.
- Rótulo "Ir para" antes das chips de seção: descartado pelo usuário; a cor e os grupos distinguem as chips do menu.
- PDF numa página única (`createPDF`): não pagina para impressão.

## Consequências

- O modelo de resumo deixa de ter dica de três linhas na página; o menu mostra só a linha "Mostra".
- O rótulo do botão é "Modelo", o mesmo termo do glossário (`.agents/GLOSSARY.md`). "Formato", usado nos mockups, foi descartado para não criar um segundo termo para o modelo de resumo.
- As chips de seção usam a mesma tinta das chips de citação. As de citação têm ícone de balão e horário, e as de seção, texto.
- Em janela estreita, as chips de seção quebram em duas linhas.
- Nova peça: `AtaExport` e `PDFExport` (`Sources/Minuta/Export.swift`). `MarkdownHTML.sectionTitles` dá a ordem das seções para as chips e para o app.
- Os links `minuta://model/<modelo>` e `minuta://redo` deixam de existir.
