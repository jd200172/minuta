# 0030. Segmentação da transcrição por pausa e duração

Status: aceita; implementada
Data: 2026-10-05
Complementa: `docs/decisions/0008-stt-provider-gemini-transcribe.md` e `docs/decisions/0024-follow-market-practice-for-capture.md`.

## Contexto

O Gemini devolve palavras com horário e falante. Quem agrupa as palavras em segmentos é o `TranscriptBuilder`. A regra anterior cortava o segmento em pausas acima de 1,2 s. Numa conversa, pausas de 1 a 2,5 s ocorrem dentro do mesmo raciocínio, e a transcrição saía como uma sequência de frases curtas do mesmo falante, sem agrupamento visível.

## Decisão

Decisão: o segmento termina quando muda o falante, quando há pausa acima de 3,0 s ou quando passaria de 45 s. Motivo: o limite de pausa acompanha o raciocínio, e o teto de duração mantém a citação apontando para um trecho curto.

Os dois valores são constantes em `TranscriptBuilder` (`pauseLimit`, `maxSegmentSeconds`). A agregação é por canal; a intercalação dos canais continua por horário de início.

## Alternativas descartadas

- Agrupar por turno só na apresentação: deixa a transcrição guardada fragmentada e não ajuda o resumo.
- Trocar o modelo de transcrição: a fragmentação vem do agrupamento, não do modelo.

## Consequências

- Segmentos mais longos: o trecho citado no balão e a unidade da janela de correção aumentam.
- Os IDs (`t-<segundos>`) mudam em transcrições novas. Atas antigas só mudam com "Refazer a transcrição" (ADR 0026).
- Uma interjeição de outra pessoa dentro de um segmento longo do mesmo canal não o divide; ela aparece depois dele, por horário de início.
- Medição em reunião real de 17 min (2026-10-05, `--process`): de 136 para 78 segmentos; falas seguidas do mesmo falante, de 75 para 27; mediana de 11 para 16 palavras; maior segmento, 146 palavras. Limite de pausa maior (4 a 5 s) não foi testado.
- Os valores não foram calibrados além dessa reunião; as palavras com horário não ficam guardadas.
