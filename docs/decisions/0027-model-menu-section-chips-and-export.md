# 0027. Menu de modelo, chips de seção e exportação da ata

Status: aceita; implementada
Data: 2026-10-05
Substitui: as chips de modelo de resumo e o ícone de refazer da página de leitura (`docs/decisions/0017-summary-models-on-demand.md`, seção Interface). O restante do ADR 0017 continua valendo.
Complementa: `docs/decisions/0026-collapsible-sections-and-retranscribe.md` (seções colapsáveis).

## Contexto

O ADR 0017 pôs os quatro modelos de resumo como chips logo abaixo do título. No uso, o usuário lê as chips como assuntos ou trechos da ata, não como modelos de resumo. As chips não têm rótulo e ficam dentro do documento, perto dos títulos de seção. Um modelo e uma de suas seções podem ter quase o mesmo nome ("Decisão" e "Decisões").

À parte, o usuário pediu para salvar a ata como HTML e como PDF, e um botão de envio por e-mail para a próxima etapa.

## Decisão

**Menu de modelo.** As chips saem. Em linha própria, abaixo do bloco de título e data, um botão com o rótulo "Modelo" e o nome do modelo de resumo atual abre um menu nativo (`NSMenu`) logo abaixo dele. O menu tem:
- os quatro modelos de resumo, com marca no atual;
- em cada item, uma segunda linha com o que o modelo mostra (a linha "Mostra" de `SummaryModel.tooltip`);
- "resumo gerado" ao lado de cada modelo que já tem resumo;
- um separador e "Refazer este resumo", que substitui o ícone de refazer.

Escolher um modelo funciona como a chip funcionava: troca na hora ou gera o resumo. Sem resumo, o botão diz "Escolher". Durante a geração, o botão deixa de ser link e mostra um indicador de progresso. Abaixo do botão há uma linha de estado, que só aparece quando há algo a avisar: resumo desatualizado depois de uma correção, geração em curso, resumo ainda não gerado, modelo que não existe mais ou classificação que falhou. A justificativa da sugestão da classificação deixou de aparecer (decisão do usuário); ela continua no arquivo secundário.

Decisão: botão na página que abre menu nativo. Motivo: a página roda sem JavaScript, então um `<select>` não teria efeito; o botão é um link `minuta://models`, e o app mede a posição dele e abre o menu.

**Chips de seção.** Abaixo do botão de modelo e da linha de estado, uma chip por seção `##` da ata, sem rótulo. O clique rola até a seção (`minuta://goto/N`, alvo `s-N`). Seção recolhida (ADR 0026) é expandida antes do salto. O título da seção pisca em azul por 1,6 s, por CSS.

Todas as chips têm o mesmo estilo (tinta azul), na ordem das seções da ata, sem grupos nem traços. A primeira versão separava as seções do modelo atual (azul) das fixas (cinza com borda); o usuário não entendeu a diferença de cor e pediu cor única.

**Espaçamento (nível "Moderado" dos mockups, a pedido do usuário).** A página estava apertada. Mudanças, de antes para depois:
- card: 22 × 28 px para 28 × 36 px; margem da janela de 16 para 20 px;
- entrelinha do texto: 1,55 para 1,65 (1,3 no título);
- título para a linha da data: 2 para 6 px; da data para o botão de modelo: 24 px; do botão para os chips: 20 px;
- entre chips: 6 para 8 px;
- entre seções: 22 para 30 px, com 18 px acima do filete; título da seção para o texto: 6 para 10 px;
- entre itens de lista: 3 para 5 px; entre parágrafos: 6 para 8 px.
**Tamanho da janela.** Os 720 px de largura da abertura eram menores que o máximo do card (760 px), então o card nunca chegava a esse máximo. A janela passa a abrir com 964 × 780 px e a lembrar o tamanho em que o usuário a deixou (`readingWindowSize` em `UserDefaults`, um valor para todas as janelas de leitura, gravado ao fim de um redimensionamento). O máximo do card continua em 760 px, pelo comprimento da linha de texto.
O custo do respiro é cerca de 15% a mais de altura por ata. O HTML exportado usa o mesmo CSS.

**Cabeçalho fixo e texto contínuo no painel.** A página da janela de leitura tem duas partes: o cabeçalho (título, data com ícones, botão de modelo, linha de estado e chips), que não rola, e um painel abaixo, com todas as seções em sequência, que rola sozinho. Os chips ficam sempre à vista. O clique num chip rola o painel até o título da seção, a 12 px do topo, e preenche o chip. Enquanto o usuário rola, o chip da seção que está no topo do painel fica preenchido: é a última seção cujo título está no topo ou acima dele, e a última seção quando o painel chega ao fim. Ao abrir, o chip do Resumo está preenchido. Um horário de citação, no balão, rola o painel até a fala na Transcrição.

Decisão: o app acompanha a rolagem e preenche o chip. Motivo: a página roda sem JavaScript, então ela mesma não marca a seção atual. O app observa roda do mouse, teclado e soltar do mouse (barra de rolagem) e, 0,1 s depois, pergunta à página qual título está no topo, com um script fixo (`evaluateJavaScript`, como nos renomes). Sem evento, nada roda.

Esta decisão substitui as seções colapsáveis (ADR 0026) e a transcrição colapsável (ADR 0019) na janela de leitura. O estado de recolhimento por reunião (`collapsedSections` e `transcriptCollapsed` em `UserDefaults`) deixa de ser usado. O HTML exportado mantém as seções colapsáveis.

**Janela sem moldura.** Na janela de leitura, a página não tem card, borda nem fundo de página: o cabeçalho e o painel ocupam a janela inteira, com o fundo da janela. O filete sob o cabeçalho vai de borda a borda, e a barra de rolagem fica na borda da janela. As margens laterais são de 32 px (antes, 20 px de fundo mais 36 px do card). O cabeçalho e o painel dividem a mesma coluna, de até 900 px (primeiro 820 px, depois 900 px a pedido do usuário), sempre centralizada: em janela larga, a sobra se divide igualmente nos dois lados, e o texto e o cabeçalho continuam alinhados entre si. Abaixo de 964 px de janela, as margens são de 32 px e a coluna ocupa o resto. O HTML exportado mantém o card centralizado de 760 px, porque abre num navegador.

**Cabeçalho.** Quatro blocos, em linhas separadas: título; data, e logo abaixo dela, em linha própria, os botões de exportação (grupo do título, alinhados à esquerda; versão anterior: na mesma linha da data, unidos por um traço); botão de modelo, 24 px abaixo; linha de estado, quando houver; chips de seção, 20 px abaixo. Os botões ficam no bloco do título por pertencerem à ata inteira, e não ao modelo.

**Botões de exportação.** Logo abaixo da data, três botões só com ícone e dica:
- "Enviar por e-mail (em breve)": visível e inativo. O envio é da próxima etapa e terá ADR próprio.
- "Salvar como HTML": um arquivo autônomo, com o CSS embutido.
- "Salvar como PDF": em páginas do tamanho de papel do sistema, com margem de 40 pt.

O conteúdo exportado é a ata do arquivo `.md`, com o modelo de resumo atual e as correções. Não leva a barra, os lápis nem as chips de seção. A transcrição vai sempre. No HTML, cada seção `##` é um bloco colapsável (`<details>` e `<summary>`, sem script) e abre sempre fechada, com o chevron e a contagem de segmentos da transcrição. No PDF, todas as seções vão abertas, porque seção fechada não sai na impressão. As citações viram âncoras para a linha da transcrição, sem balão. O PDF é impresso por uma `WKWebView` fora da tela, em aparência clara, com regras `@media print` (sem card, sem quebra dentro de uma fala).

**Desvio das HIG.** O botão de modelo imita um botão pop-up do macOS dentro da página, e o menu é nativo. As chips de seção são próprias. Os balões de dica e de citação mantêm a forma que vinha das chips de modelo (raio de 16 px), para não mudar a linguagem dos balões (ADR 0019).

## Alternativas descartadas

- Rótulo e controle de segmentos no lugar das chips: mantém as quatro opções à vista, mas ocupa a linha inteira e disputa espaço com as chips de seção.
- Frase de estado com "Trocar modelo": explica a sugestão, mas exige um clique a mais para ver as opções.
- Controle na barra de ferramentas da janela: tira o seletor do documento, mas fica longe do documento.
- Cartões com a estrutura de cada modelo: ocupam mais altura e destoam da leitura.
- Só as chips das seções do modelo, sem as fixas: a linha fica curta, mas as chips sozinhas voltam a parecer as chips de modelo, e a transcrição perde o atalho.
- Rótulo "Ir para" antes das chips de seção: descartado pelo usuário; a cor e os grupos distinguem as chips do menu.
- PDF numa página única (`createPDF`): não pagina para impressão.

## Consequências

- O modelo de resumo deixa de ter dica de três linhas na página; o menu mostra só a linha "Mostra".
- A tela não mostra mais por que o modelo foi sugerido.
- O rótulo do botão é "Modelo", o mesmo termo do glossário (`.agents/GLOSSARY.md`). "Formato", usado nos mockups, foi descartado para não criar um segundo termo para o modelo de resumo.
- As chips de seção usam a mesma tinta das chips de citação. As de citação têm ícone de balão e horário, e as de seção, texto.
- A chip não indica quais seções mudam com o modelo. O menu Modelo e o texto de cada seção dão essa informação.
- Em janela estreita, as chips de seção quebram em duas linhas.
- A moldura (20 px, borda e 36 px de padding) comia cerca de 56 px de largura útil por lado e dava à janela o aspecto de uma janela dentro de outra.
- O cabeçalho fixo ocupa cerca de 250 px da janela de 780, o que reduz a área de leitura. O texto rola dentro do painel.
- A seção final precisa de texto abaixo para chegar ao topo do painel. A Transcrição é longa, então só Itens de ação e Pontos em aberto, nas atas com transcrição curta, podem não chegar ao topo; nesse caso o chip clicado fica preenchido até a próxima rolagem.
- O preenchimento do chip depende de um atraso de 0,1 s depois da rolagem.
- A alternativa de mostrar uma seção por vez, trocada pelo chip, foi implementada primeiro e substituída por esta a pedido do usuário.
- No HTML exportado, uma citação aponta para uma fala dentro de seção fechada. Chrome e Firefox abrem a seção ao seguir o link; o Safari pode não abrir, e a fala fica oculta até o usuário abrir a seção.
- Nova peça: `AtaExport` e `PDFExport` (`Sources/Minuta/Export.swift`). `MarkdownHTML.sectionTitles` dá a ordem das seções para as chips e para o app.
- Os links `minuta://model/<modelo>` e `minuta://redo` deixam de existir.
