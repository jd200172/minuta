# 0022. Guardar o áudio de todas as reuniões

Status: aceita; implementada; destino alterado em 2026-10-02 (ver "Alteração")
Data: 2026-10-02
Substitui: a regra "o áudio é descartável" de `AGENTS.md` e a decisão de apagar o áudio depois da transcrição (ADRs 0001, 0004 e 0009 tratavam o áudio como temporário).

## Contexto

O app apagava o áudio assim que a transcrição era gravada. Na reunião de 2026-10-01 às 19:06 a transcrição saiu com a voz do outro participante duplicada e atribuída ao usuário (ADR 0021), e sem o áudio não havia como conferir o texto, comparar modelos de transcrição nem refazer a transcrição com outros parâmetros. O usuário decidiu guardar o áudio sempre, com o nome associado ao das transcrições e dos resumos.

## Alteração (2026-10-02)

A pedido do usuário, a regra "sem armazenamento de áudio na nuvem" deixa de existir e o áudio passa a ficar na pasta de atas definida nas configurações, ao lado do `.md` e do secundário. O que a pasta sincroniza (OneDrive, por exemplo) é escolha do usuário. `Config.audioDir` passa a devolver `Config.outputDir`. Na inicialização, `AudioArchive.migrateLegacy` move os `.mic.m4a` e `.system.m4a` de `~/Library/Application Support/Minuta/audio/` para a pasta de atas; arquivo que já exista no destino não é sobrescrito e fica na pasta antiga, que é removida quando esvazia. Trocar a pasta de atas nas configurações não move áudio nem atas já gravadas. Os trechos abaixo sobre pasta local e nuvem ficam como registro da decisão original.

## Decisão

**O áudio de toda reunião que vira ata é guardado.** Os dois arquivos mono AAC `.m4a` (microfone e sistema) saem da pasta do job, depois que a ata é criada, e vão para `~/Library/Application Support/Minuta/audio/`.

**Nome associado ao da ata.** Os arquivos usam o radical do arquivo secundário (`AAAA-MM-DD HHmm`, com ` (2)` etc. em colisão), sem o título, como o secundário:

    2026-10-01 1906.resumos.json   transcrição e resumos (ADR 0017)
    2026-10-01 1906.mic.m4a        microfone
    2026-10-01 1906.system.m4a     áudio do sistema

Renomear a reunião muda o `.md` e não toca no secundário nem no áudio. O radical é o que liga os três. Uma ata nova nunca toma o nome de um áudio que ainda existe: o nome seguinte livre (` (2)`) é escolhido.

**Pasta local, fora da pasta de atas.** A pasta de atas pode estar sincronizada com um serviço de nuvem (a do usuário está no OneDrive), e áudio de reunião sincronizado seria armazenamento de áudio na nuvem, que a regra do projeto veda. O áudio fica só neste Mac. Trocar o destino é uma mudança em `Config.audioDir`.

**Ciclo de vida.**
- Mover o áudio é o último passo depois de gravar o `.md` e o secundário. Se não for possível, a ata fica, o app avisa, e o áudio continua na pasta de gravações pendentes (que então mostra a gravação como linha na janela de atas).
- Mover a ata para a Lixeira leva o áudio junto. "Descartar" de uma gravação pendente apaga o áudio dela.
- Gravação com menos de 10 palavras não gera ata e continua sendo descartada com o áudio: sem ata não há nome a que associar.
- Falha de rede: o áudio continua na pasta do job até a transcrição, como antes.
- Menu de contexto da lista de atas: "Mostrar áudio no Finder" (desabilitado quando não há áudio).
- Atas anteriores a este ADR não têm áudio (foi apagado).

## Consequências

- O consumo de disco passa a crescer com cada reunião (dois arquivos mono AAC de 16 kHz, da ordem de alguns MB por 25 minutos cada), sem limite nem limpeza automática. A regra "consumo baixo de disco" fica atendida só por reunião; limpeza por idade fica como opção futura.
- O áudio é dado sensível guardado em claro, no perfil do usuário. A Lixeira do macOS é o único caminho de remoção do app.
- Com o áudio é possível refazer a transcrição e comparar modelos (próximo passo: um comando que refaz a transcrição de uma ata a partir do áudio guardado).
- `AGENTS.md`: a regra do áudio e a descrição do estado do job mudam; escopo "Armazenamento de áudio na nuvem" continua fora.
