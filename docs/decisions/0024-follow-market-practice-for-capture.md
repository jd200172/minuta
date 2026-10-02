# 0024. Captura e atribuição pelo padrão de mercado

Status: aceita; implementada
Data: 2026-10-02
Substitui: `docs/decisions/0021-echo-removal-in-transcript.md`.
Confirma: `docs/decisions/0004-two-channel-capture.md`, `docs/decisions/0006-participant-identification.md` e `docs/decisions/0023-echo-cancellation-at-capture.md`.

## Contexto

Na reunião de 2026-10-01 às 19:06 (chamada com o alto-falante ligado), a voz do outro participante entrou no microfone e saiu duplicada na transcrição, com a cópia atribuída ao usuário. Na busca por uma correção foram propostas soluções próprias: comparar o texto dos dois canais para apagar o eco (ADR 0021), guardar o que foi apagado numa seção da ata, cortar o microfone por detecção de fala e trocar os dois canais por um áudio único com diarização. O usuário pediu que o app siga a solução que o mercado já adota para esse problema, sem soluções próprias.

## Decisão

O app segue a prática consolidada, parte por parte:

| Problema | Prática adotada | Referência |
|---|---|---|
| Saber quem falou | Um canal por lado; o canal define o falante (microfone = usuário, áudio do sistema = demais) | AssemblyAI e Deepgram recomendam transcrição por canal quando há canais separados; o Granola grava microfone e sistema em separado ("Me" e "Them") |
| Várias vozes no mesmo canal | Diarização do serviço de transcrição, só no canal do sistema | Mesmos serviços: diarização é o recurso para um canal com várias vozes |
| A chamada entrando no microfone | Cancelamento de eco acústico no caminho do microfone (o do sistema operacional), ou fone de ouvido | Ferramentas de voz em geral (Zoom, Teams, Meet, Krisp); ADR 0023 |
| Erro que sobrar | Correção humana na transcrição | Janela de correção (ADR 0025) |

O filtro de eco pelo texto (`EchoFilter`, ADR 0021) e a seção "Eco do microfone" foram retirados. A montagem da transcrição voltou a ser a anterior: cada canal é transcrito e rotulado pelo canal.

## Alternativas descartadas

- **Áudio único com diarização de todas as vozes**, inclusive a do usuário, identificado pela atividade do microfone. Testado nos oito cenários sintéticos (2026-10-02): em 3 de 8 a diarização juntou a voz do usuário com a de outra pessoa (75%, 94% e 62% das palavras com o falante certo); só com o canal do sistema, os mesmos cenários deram 98% a 100%. Os serviços de transcrição indicam diarização para quando não há canais separados.
- **Filtro de eco pelo texto** (ADR 0021): aparece só em projetos abertos como contorno de quem não tem cancelamento de eco; erra nos dois sentidos (deixa resto de eco e pode apagar fala do usuário) sem que o erro apareça.
- **Corte do microfone por detecção de fala antes de transcrever**: solução própria, sem referência de mercado.

## Consequências

- Sem o cancelamento de eco (opção desligada, fone Bluetooth que não o suporta) e sem fone, a duplicata pode voltar. A resposta prevista é o cancelamento ligado por padrão, a orientação de usar fone e a correção manual na janela de correção.
- O teste que falta é uma chamada real com o alto-falante ligado e o cancelamento ligado (ADR 0023). Só um resultado ruim nesse teste reabre esta decisão.
- O áudio dos dois canais continua guardado (ADR 0022), o que permite repetir a comparação com o áudio único numa gravação real, se for preciso.
