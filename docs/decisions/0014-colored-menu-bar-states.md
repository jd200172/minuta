# 0014. Estado do app pela cor de fundo do botão na barra de menus

Status: aceita; implementada com `NSStatusItem`
Data: 2026-10-01
Substitui, em parte: `docs/decisions/0013-pause-resume-end-recording.md` (ícones por estado).

## Contexto

O ícone do botão trocava de símbolo conforme o estado (microfone, ponto de gravação, pausa, setas). O usuário pediu um ícone fixo e o estado indicado pela cor de fundo do botão.

## Decisão

O botão mostra sempre o ícone de microfone. O estado vem do fundo e dos elementos ao lado:

| Estado | Fundo | Ao lado do ícone |
|---|---|---|
| Parado | nenhum (como hoje) | nada |
| Gravando | verde | relógio correndo (`mm:ss`) |
| Pausado | vermelho | relógio parado e símbolo de pausa |
| Processando | amarelo | spinner girando |

Gravação e processamento ao mesmo tempo: vale a cor da gravação (verde ou vermelho), com o spinner ao lado do relógio enquanto houver processamento em andamento. Ao terminar o processamento, o botão volta ao estado inicial; a notificação "Ata salva" ou o aviso de erro seguem como hoje.

O relógio tem largura fixa, para o botão não empurrar os outros itens da barra. Ícone e texto são escuros sobre verde e amarelo, e brancos sobre vermelho: o branco sobre o verde do sistema tem contraste baixo.

**Daltonismo.** Verde e vermelho se confundem na deficiência de visão de cores mais comum. O símbolo de pausa ao lado do relógio e o relógio parado mantêm a distinção por forma, como a regra de sinalização do `AGENTS.md` exige.

**Desvio das HIG.** As diretrizes tratam os itens da barra de menus como imagens monocromáticas. O fundo colorido é um desvio deliberado, aceito pelo usuário em 2026-10-01, para que o estado seja visível sem abrir o menu. O ícone continua sendo um SF Symbol e o menu continua padrão.

## Consequências

- O `MenuBarExtra` do SwiftUI não desenha fundo colorido nem animação por conta própria. A implementação escolhe entre desenhar o botão como imagem a cada atualização (custa uma renderização por segundo e por quadro do spinner) e trocar para `NSStatusItem` com `NSMenu`, que aceita fundo na camada do botão e animação nativa, mas altera o ADR 0009. Escolhido: `NSStatusItem` com `NSMenu`.
- Implementação: `StatusItemController` desenha uma pílula (fundo na camada, ícone, relógio de largura fixa, símbolo de pausa e `NSProgressIndicator`) dentro do botão do item; parado, o botão é o ícone padrão em modo template. O ponto de entrada passou a ser `main.swift` com `AppDelegate`, sem cena SwiftUI.
- O spinner é novo: o ícone de processamento atual é estático.
- Contraste do ícone e do relógio precisa ser conferido nas barras clara e escura e com papéis de parede diferentes.
- A forma do ícone deixa de indicar o estado; o relógio, o símbolo de pausa e o spinner o substituem.

## Alternativas descartadas

- Manter ícones diferentes por estado e só acrescentar cor: o usuário preferiu o ícone fixo.
- Cor sem símbolo de pausa: depende só da diferença entre verde e vermelho.
