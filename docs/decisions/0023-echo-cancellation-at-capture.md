# 0023. Cancelamento de eco na captura do microfone

Status: aceita; implementada; falta conferir a fala do usuário numa chamada real
Data: 2026-10-02
Complementa: `docs/decisions/0004-two-channel-capture.md`. Confirmado pelo `docs/decisions/0024-follow-market-practice-for-capture.md`.

## Contexto

Em chamada com o alto-falante ligado, o microfone capta a voz dos outros participantes e a transcrição sai duplicada e atribuída ao usuário (ADR 0021). Esta decisão trata a causa, na captura, como fazem as ferramentas de voz (ADR 0024).

## Decisão

O microfone passa pelo processamento de voz do macOS (`AVAudioEngine`, `setVoiceProcessingEnabled`), que conhece o que os alto-falantes tocam e o subtrai do que o microfone capta.
- Ligado por padrão. A opção "Cancelar o eco do microfone", em Preferências, desliga (com fone de ouvido não há eco). Se o sistema não conseguir ligar o processamento, o microfone grava como antes.
- No macOS 14 ou superior, o abaixamento do som dos outros apps durante a gravação é limitado ao mínimo. Ao parar, o processamento é desligado e o som volta ao normal.
- O processamento pode entregar vários canais; o conversor usa o primeiro (o microfone processado).
- Modo de teste de desenvolvedor: `open -n -a Minuta --args --capture-test <relatório.json> [--aec on|off] [--seconds N]` grava os dois canais e escreve os níveis e a correlação entre a variação de volume do microfone e a do canal do sistema (`bleed`). Iniciado por `open`, usa as permissões do app.

## Medição (2026-10-02, 12 s por rodada, voz em português tocada no alto-falante do Mac)

| Rodada | Nível do microfone | `bleed` | Nível do canal do sistema |
|---|---|---|---|
| fala tocando, sem cancelamento | -33,5 dB | 0,95 | -18,7 dB |
| fala tocando, com cancelamento | -72,3 dB | 0,29 | -26,3 dB |
| silêncio, sem cancelamento | -60,7 dB | 0 | sem som |
| silêncio, com cancelamento | -71,9 dB | 0 | sem som |

Sem cancelamento, o microfone repete a chamada (`bleed` 0,95). Com cancelamento, ele cai para o ruído de fundo (38 dB abaixo) e a correlação cai para 0,29.

## Consequências

- O canal do sistema fica cerca de 7,6 dB mais baixo com o cancelamento ligado, porque o macOS abaixa o som dos outros apps (e o canal do sistema vem dessa saída). O nível continua adequado à transcrição (média de -26 dB), mas uma voz baixa no outro lado perde margem.
- Não foi testada a fala do usuário com o cancelamento ligado (o teste usou voz sintética no alto-falante e silêncio no microfone). O processamento de voz também aplica supressão de ruído e controle de ganho, e pode atenuar a fala do usuário quando os dois falam juntos. Conferir numa chamada real.
- Com fone Bluetooth, o processamento de voz pode forçar o modo de chamada do fone (qualidade menor); a opção permite desligar.
