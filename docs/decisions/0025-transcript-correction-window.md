# 0025. Janela de correção da transcrição

Status: aceita; implementada
Data: 2026-10-02
Complementa: `docs/decisions/0022-keep-audio.md` e `docs/decisions/0024-follow-market-practice-for-capture.md`.

## Contexto

Nenhum serviço de transcrição acerta nomes, termos e falas sobrepostas em todas as reuniões, e o resumo só é tão bom quanto a transcrição. Com o áudio guardado (ADR 0022), o usuário pode ouvir o trecho e corrigir o texto. A correção humana é a última camada da prática adotada no ADR 0024.

## Decisão

Uma janela própria por reunião, aberta pelo botão "Corrigir a transcrição" na barra da janela de leitura e por "Corrigir transcrição…" no menu de contexto da lista de atas. Só atas com arquivo secundário (ADR 0017) podem ser corrigidas.

**O que a janela faz**
- Lista todas as falas com horário, falante, canal de origem (microfone ou sistema) e texto.
- Clicar no horário toca o áudio dos dois canais, sincronizados, a partir daquela fala. A fala em reprodução fica destacada e a lista acompanha. Espaço toca e pausa quando nenhum texto está em edição. Velocidade de 0,75x a 1,5x; cada canal pode ser silenciado. Sem áudio guardado (atas anteriores ao ADR 0022), a janela corrige o texto e avisa que não há o que ouvir.
- O texto é editado no lugar: Return ou sair do campo salva; Esc devolve o texto. Fala vazia é recusada.
- O falante se troca por um menu com os rótulos da reunião (nomes dados pelo usuário aparecem no lugar do rótulo). O canal de origem não muda: a fala continua tocando do canal em que foi gravada.
- "Apagar fala" pede confirmação. "Restaurar original" devolve a versão do modelo.
- Filtro "Todas" ou "Corrigidas".

**Dados**
- A correção altera `segments` no arquivo secundário e a ata é reescrita com o mesmo título, modelo de resumo e nomes. A primeira mudança em uma fala guarda a versão do modelo em `originals` (por id), que serve para restaurar e, depois, para medir erros do modelo de transcrição. Apagar remove a fala e guarda o original.
- Toda correção marca como desatualizados (`outdated`) os resumos já gerados. O resumo continua sendo mostrado; a janela de correção e a página de leitura avisam, e "Refazer resumo" (ou o ícone de refazer da página) gera de novo, o que custa uma chamada à API. Gerar um modelo tira a marca dele. A marca é conservadora: restaurar todas as falas não a remove.
- O app passa a guardar no secundário o início de cada canal no relógio da reunião (`audio_offsets`), para tocar o trecho certo de cada arquivo.
- A ata é encontrada pelo `inicio` antes de cada gravação, porque o nome do `.md` muda com o título.

## Fora desta versão

Dividir e juntar falas (mudariam os ids citados pelos resumos), fila de revisão por suspeita, desfazer com ⌘Z e medição de erro a partir das correções.

## Consequências

- Interface do app ganha uma janela (Escopo do `AGENTS.md`).
- Testes: `TranscriptCorrectionTests` (texto, falante, apagar, restaurar, resumo desatualizado, nomes, citação apagada, localização pelo `inicio`, deslocamentos do áudio). A janela foi conferida no app com uma ata de teste feita do cenário sintético 8 e com áudio: reprodução, destaque da fala, espaço, edição, troca de falante, restaurar e o aviso na página de leitura. "Refazer resumo" não foi acionado no teste (usa o mesmo caminho do ícone de refazer).
