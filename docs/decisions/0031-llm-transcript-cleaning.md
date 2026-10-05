# 0031. Limpeza da transcrição pelo LLM

Status: aceita; implementada
Data: 2026-10-05
Complementa: `docs/decisions/0008-stt-provider-gemini-transcribe.md`, `docs/decisions/0030-segment-by-pause-and-length.md`.

## Contexto

O Gemini Transcribe tem dois modos. O `verbatim` devolve preenchimentos, repetições e falsos começos, e é o único com diarização e horário por palavra. O `smart` limpa o texto, mas não aceita diarização nem horários (documentação oficial, 2026-10-05). Sem os dois, a ata perde os falantes e as citações por segmento. O provedor fica como está (ADR 0008).

## Decisão

Decisão: depois de `TranscriptBuilder`, o LLM do resumo (`Minuter.clean`) devolve o texto de cada segmento sem ruído de fala. Motivo: entende repetições de trecho que regras simples erram, e preserva falante, horário e ID de cada segmento.

- O prompt pede só remoção: preenchimentos, repetições gaguejadas e falsos começos. Mantém palavras de conteúdo, números, nomes, negações, respostas curtas e repetição de ênfase. Proíbe acrescentar ou trocar palavras e juntar ou dividir segmentos.
- O app valida a resposta (`TranscriptCleaner.apply`) e nunca confia no modelo. Usa o texto novo só se as palavras forem um subconjunto das originais e, em segmento de 8 palavras ou mais, restar ao menos metade. Segmento de até 3 palavras devolvido vazio é descartado. Segmento ausente ou reprovado fica como veio do STT.
- Quando o texto muda, o original vai em `Segment.raw` (opcional) e fica no `.resumos.json` e no `transcript.json`.
- A transcrição vai em blocos de até 2500 palavras, em paralelo. Qualquer falha (chave ausente, rede, formato) deixa a transcrição sem limpeza, sem interromper o job.
- Vale para gravações novas e para "Refazer a transcrição" (ADR 0026), porque a limpeza fica em `Pipeline.transcribe`.

## Alternativas descartadas

- Modo `smart` do Gemini: sem diarização nem horários.
- Regras fixas (lista de preenchimentos e repetições): sem custo, mas erram na ênfase e nas repetições de trecho. Podem entrar antes do LLM se o custo pesar.
- Limpar só na apresentação: o resumo e as citações continuariam com o texto sujo.

## Consequências

- Uma chamada a mais ao LLM por reunião (cerca de 2500 palavras por bloco), com esforço baixo. O texto da reunião já ia ao LLM para classificar e resumir; nada novo sai da máquina.
- A janela de correção e o resumo trabalham sobre o texto limpo. O original fica em `raw`; ainda não há botão para vê-lo.
- Falha da limpeza é silenciosa: a transcrição segue suja, sem aviso.
- Medição na reunião real de 17 min (2026-10-05): 78 segmentos, 38 alterados, de 2740 para 2622 palavras (4,3%), nenhum descartado. O tempo do `--process` subiu de 40 s para 72 s.
- Interjeições curtas de outra pessoa não são tratadas aqui.
