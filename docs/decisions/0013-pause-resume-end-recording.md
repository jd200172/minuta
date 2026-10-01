# 0013. Pausar, continuar e encerrar a gravação, com contador na barra de menus

Status: aceita
Data: 2026-10-01
Complementa: `docs/decisions/0011-minimal-menu-and-install.md` e `docs/decisions/0010-recording-limit-30-minutes.md`.

## Contexto

O ícone da bandeja não dizia há quanto tempo a gravação durava, e o menu só tinha Iniciar e Parar. Uma interrupção na reunião obrigava a gravar o intervalo ou a encerrar e começar outra ata.

## Decisão

**Estados.** Ocioso, gravando, pausada. Menu: Iniciar gravação (ocioso); Pausar gravação e Encerrar gravação (gravando); Continuar gravação e Encerrar gravação (pausada). Os demais itens não mudam. Encerrar para a captura e inicia o processamento sem confirmação, e o menu volta a oferecer Iniciar gravação enquanto a ata é feita.

**Contador.** A barra de menus mostra o tempo gravado ao lado do ícone (`mm:ss`, `h:mm:ss` a partir de uma hora), atualizado uma vez por segundo. Gravando: ponto de gravação. Pausada: símbolo de pausa, tempo parado. A forma do ícone distingue os estados, não só a cor.

**Pausa sem cortar arquivo.** Na pausa o `Recorder` descarta as amostras recebidas. Cada canal continua sendo um único `.m4a`, e os horários da transcrição seguem o tempo gravado, sem o das pausas. O tempo em pausa não conta para o limite de 30 minutos (ADR 0010); no limite, o app encerra e processa, e uma notificação avisa.

**Lembrete de pausa.** Uma notificação a cada 10 minutos de pausa lembra de continuar ou encerrar.

**Sair durante a gravação.** ⌘Q com gravação em andamento ou pausada pede confirmação (Continuar no minuta, Sair e perder), porque o `.m4a` só é legível depois de fechado.

## Consequências

- O app que cai ou é encerrado à força durante a gravação ou a pausa perde a gravação; a confirmação cobre só a saída normal.
- A duração gravada na ata é o tempo gravado, não o intervalo entre início e fim.
- A transcrição não marca onde houve pausa. A fala antes e depois da pausa aparece em sequência.
- O ponto vermelho pode aparecer monocromático na barra de menus, dependendo do tema; o contador e a forma do ícone sinalizam o estado.

## Alternativas descartadas

- Um arquivo por trecho gravado: exigiria juntar as transcrições e manter a consistência dos rótulos de falante entre trechos.
- Confirmação ao encerrar: um clique a mais, e o encerramento não destrói nada, já que o processamento começa e o áudio fica guardado até a transcrição.
- Mostrar o tempo restante até o limite: o decorrido basta.
