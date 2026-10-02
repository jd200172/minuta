# 0019. Transcrição colapsável e balões de citação

Status: aceita; implementada
Data: 2026-10-01
Complementa: `docs/decisions/0015-minutes-library.md` e `docs/decisions/0017-summary-models-on-demand.md`.

## Contexto

Cada decisão, ação e ponto em aberto cita um horário que levava a uma linha da transcrição, no fim da página. Conferir uma citação obrigava a rolar até lá e voltar. A transcrição também ocupa a maior parte da página e fica sempre aberta.

## Decisão

**A transcrição é um bloco colapsável.** O título "Transcrição" vira um alternador (`minuta://transcript`) com a contagem de segmentos. O estado é lembrado por reunião, pelo `inicio` do cabeçalho, em `UserDefaults` (chave `transcriptCollapsed`). Reunião nunca vista abre recolhida, para a ata ficar em foco. As linhas continuam na página quando recolhidas (só escondidas), para o salto a um horário funcionar. O alternador recarrega a página, mantendo a rolagem, como os outros links `minuta://`. O arquivo `.md` não muda.

**A citação abre um balão.** Cada horário de citação (`[00:00:04](#t-000004)` no arquivo) vira um link `minuta://cite/<segmento>/<N>` na página, com um id `rf-N` que o app mede, como nos renomes no lugar. O clique abre um balão ancorado na citação, com o segmento citado inteiro e em destaque e, esmaecidos, um segmento antes e um depois, cada um com participante, texto e horário. As falas vizinhas saem em 75% do tamanho (`BalloonStyle.contextScale`) e são cortadas em duas linhas com reticências (`contextLines`); a citada nunca é cortada. **O balão nunca tem barra de rolagem:** ele cresce em altura primeiro e, só quando falta espaço acima e abaixo da citação dentro da janela, passa para a largura seguinte (340, 420 e, por último, a largura do card). Tem 12 pt de respiro acima da primeira linha e abaixo da última. Cada citação abre um balão com o próprio segmento; citações vizinhas do mesmo item não são agrupadas. Os nomes vêm do próprio `.md` (já com os nomes de participantes aplicados), então o balão acompanha renomeações. O balão aceita o mouse e fecha com Esc (que não fecha a janela), clique fora, rolagem da página ou novo clique na citação que o abriu (o app guarda qual citação abriu o balão, porque o clique fecha o balão e depois chega como link).

**O horário do balão leva ao ponto.** Só o horário é link: ele fecha o balão, expande a transcrição se estiver recolhida (gravando o estado) e rola até a linha, que recebe o destaque de `:target`. O trecho do balão fica selecionável para copiar.

**Uma só linguagem de balão no app.** O `BalloonPanel` substitui o `NSPopover`, cujo raio de canto não é configurável: é um painel sem borda, no material do sistema, com o contorno desenhado por `BalloonOutline` (corpo arredondado e seta num só traçado). `BalloonStyle` reúne o que todo balão compartilha: o raio de 16 pt e o espaçamento horizontal de 14 pt das chips de modelo da página, texto de 12 pt, destaques em semibold, pausa de 0,4 s e o tom de link (`linkColor`) dos chips da página. A seta aponta para o centro da citação ou do controle mesmo quando o balão é deslocado para caber no card. O balão abre abaixo do elemento quando cabe dentro da janela, senão acima, senão no lado com mais espaço. Dele leem o balão de dica (`TipBalloon`), o de citação (`CitationBalloon`) e o que cobre os controles nativos. O horário dentro do balão de citação é um chip com o desenho de `a.chip` (11 pt, 14 % de tom de link, cantos de 5 pt), e a linha citada tem o tom da linha selecionada da transcrição (16 %, cantos de 6 pt). Os comportamentos diferem: a dica não recebe o mouse e abre após a pausa; a citação abre no clique. Enquanto a citação está aberta, as dicas ficam suprimidas.

**Dicas dos controles nativos.** Nenhum tooltip do sistema resta no app. O botão "Mostrar no Finder" da barra de título (`TipHost`, uma camada transparente com área de rastreamento) e a mensagem de falha da lista de atas (`.balloonTip`) abrem o mesmo balão de dica, abaixo do controle, e fecham com clique, rolagem ou tecla. O rótulo de acessibilidade do controle continua no próprio controle.

**O balão fica dentro do card.** A página informa ao app o retângulo do card (`#card`). O ponto de ancoragem do balão de citação é deslocado para o lado até o balão caber no card, com 12 pt de folga, e a largura diminui em janela estreita. A seta aponta para a linha da citação, nem sempre para o chip, porque o sistema ancora a seta no centro do ponto informado.

**Sem JavaScript na página.** Alternador, citações e salto são links `minuta://` ou comandos fixos de `evaluateJavaScript` com um id validado (letras, números e hífen). Atas abertas fora do app (por exemplo, uma ata convertida sem `citations`) mantêm as âncoras `#t-…`, que funcionam num navegador.

## Consequências

- O balão desvia das HIG pelo painel próprio no lugar do `NSPopover`: o raio de canto e a seta ancorada fora do centro não existem no popover do sistema. Registrado no ADR 0017 como desvio do balão próprio da página de leitura e estendido aqui a todos os balões do app.
- A conferência de uma citação não muda a posição de rolagem da página.
- Citações no resumo e na tabela de ações usam o mesmo caminho (`MarkdownHTML.inline`).
- Sem teste automatizado da interface (balão, rolagem, foco): verificado só por testes do HTML gerado e do trecho de transcrição.
