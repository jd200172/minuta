# 0004. Captura em dois canais

Status: aceita. Formato e empacotamento atualizados pelo ADR 0009 (dois arquivos mono AAC em vez de um arquivo Ogg/Opus de dois canais).
Data: 2026-09-30
Substitui: seção 2 (Captura de Áudio, "unifica microfone e saída do sistema") de `docs/project-brief.md`.

## Contexto

O brief mixava microfone e áudio do sistema num arquivo único. A mixagem perde a origem de cada fala e, sem fone, o microfone capta o alto-falante e duplica o texto.

## Decisão

Gravar dois canais no mesmo arquivo: canal 1 é o microfone (o usuário) e canal 2 é o áudio do sistema (os demais participantes da reunião virtual). Formato: Ogg/Opus a 16 kHz, gravado em streaming em disco.

## Consequências

- A separação entre o usuário e os demais vem da captura. Entre os demais, a diarização do canal do sistema distingue os participantes (ADR 0006).
- O eco pode ser tratado comparando os canais.
- Arquivo um pouco maior que o mono, na faixa de poucas dezenas de MB por hora.
- O provedor de STT precisa aceitar áudio multicanal ou receber cada canal separado, e oferecer diarização no canal do sistema. Critério de escolha do provedor.
- `.m4a` sai do escopo. Ogg tolera truncamento, o que cobre queda do app e perda de dispositivo. Suporte a Opus no `soundfile` depende da versão do libsndfile (verificar).

## Alternativas descartadas

- Mixagem em mono: arquivo menor e fluxo mais simples, mas perde a origem da fala e duplica texto por eco.

## Atualização 2026-09-30

Sem dispositivo de entrada de áudio (por exemplo, um Mac mini sem microfone conectado), o app grava só o canal do sistema e avisa o usuário. Nesse caso a ata não terá as falas do usuário.
