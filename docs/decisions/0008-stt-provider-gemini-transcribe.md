# 0008. Provedor de STT: Gemini 3.5 Transcribe

Status: aceita. Validada com áudio sintético em 2026-09-30 (português, 3 vozes no canal do sistema, 28 de 28 falas com o falante certo; ver `docs/validation-plan.md`). Pendentes: voz real, áudio de 30 minutos e termos de dados.
Data: 2026-09-30
Complementa: `docs/decisions/0002-stt-plus-text-llm.md`, `docs/decisions/0004-two-channel-capture.md`, `docs/decisions/0006-participant-identification.md`.

## Contexto

O STT precisa de diarização, timestamps por segmento e português do Brasil (ADRs 0002, 0004 e 0006). O Gemini 3.5 Transcribe é um modelo dedicado de transcrição do Google, lançado em 26/08/2026. A pesquisa usou fontes secundárias para o modelo (blog Spokenly) e a documentação oficial do Gemini API para áudio geral.

Dados levantados:
- Modelo `gemini-3.5-transcribe`, pela Interactions API.
- Diarização para até 8 falantes. Atribuição com 3 ou mais é marcada como experimental.
- Timestamps por palavra. WER médio de 2,6% (Artificial Analysis). Cerca de US$0,005 por minuto, ou US$0,30 por hora de áudio.
- Mais de 85 idiomas. Português não é citado especificamente.
- A documentação geral de áudio do Gemini combina canais em um só.

## Decisão

Usar o Gemini 3.5 Transcribe como STT do MVP.

- Cada canal é enviado como arquivo mono separado (microfone e sistema), por causa da combinação de canais. Só o canal do sistema usa diarização.
- O custo da transcrição é cobrado por canal: cerca de US$0,60 por hora de reunião com dois canais, menos se o canal do microfone tiver fala curta.

## Consequências

- Risco de requisito: a diarização com 3 ou mais falantes é experimental. O canal do sistema em reunião virtual costuma ter 3 ou mais vozes, o que afeta diretamente a regra de não misturar participantes (ADR 0006).
- Português do Brasil não está confirmado para o modelo. Se a qualidade não for suficiente, a alternativa pesquisada é o AssemblyAI, que documenta diarização em pt-BR para 10 ou mais falantes.
- Um fornecedor só é possível se o LLM de texto também for do Google. O LLM da ata continua em aberto: Claude Sonnet 5.5 é a recomendação por custo e qualidade em texto.
- A interface do STT fica atrás de uma camada própria do app, para permitir troca de provedor sem reescrever o fluxo.

## Verificações antes de implementar

1. Rodar uma reunião virtual real, com 3 ou mais participantes e em português, e contar trocas e fusões de falantes no canal do sistema.
2. Confirmar a duração máxima por arquivo e o limite de tamanho do modelo.
3. Ler os termos de dados do Google para áudio enviado pela API, incluindo plano gratuito e pago, e retenção.
4. Conferir o formato de resposta: timestamps por segmento, rótulos de falante e estabilidade dos rótulos ao longo de 60 minutos.

## Alternativas descartadas

- AssemblyAI: documenta diarização em pt-BR para 10 ou mais falantes. Não escolhido por preferência do usuário por um fornecedor só e pela simplicidade.
- ElevenLabs Scribe v2 e Deepgram Nova-3: sem vantagem decisiva sobre as duas opções acima na pesquisa.
- OpenAI: limite de 1400 s por chunk (fonte secundária) ameaça a consistência de rótulos em 60 minutos.
- Gemini multimodal por prompt (áudio direto no modelo de chat): risco reportado em áudio longo com atribuição de falantes.
