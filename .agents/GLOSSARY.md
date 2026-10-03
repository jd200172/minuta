# Glossário

Um termo, um sentido. Termo fora desta lista, ou usado com outro sentido, é erro de documento (regra em `.agents/STYLE.md`).

Entradas confirmadas pelo usuário em 2026-10-03. Termo novo entra aqui antes de aparecer em documento.

| Termo | Sentido | Não usar para |
| --- | --- | --- |
| reunião | Evento que o usuário grava. | O arquivo gerado. |
| gravação | Captura de áudio em andamento ou o job dela na lista. | A reunião, a ata. |
| job | Unidade de processamento de uma gravação (transcrever, classificar). | A gravação em si. |
| ata | O arquivo `.md` principal, com resumo, seções e transcrição. | O arquivo `.resumos.json`. |
| arquivo secundário | O `.resumos.json`. | A ata. |
| transcrição | Segmentos de fala com falante e tempo. | O resumo. |
| segmento | Trecho da transcrição com ID. | O resumo de um tema. |
| resumo | Texto gerado por um modelo de resumo para a reunião. | A ata inteira. |
| modelo de resumo | Um dos quatro: Decisão, Problemas e ideias, Informativa, Geral. | O modelo de LLM. |
| modelo de LLM | Modelo do provedor (ex.: Claude Sonnet 5.5). | O modelo de resumo. |
| provedor | Serviço de STT ou de LLM atrás de `Transcriber` ou `Minuter`. | O modelo. |
| participante | Falante identificado por rótulo ou nome. | O usuário, que é o canal do microfone. |
| rótulo | Nome automático ("Participante N"). | O nome informado. |
| canal | Fluxo de áudio: microfone ou sistema. | O arquivo de áudio. |
| pasta de atas | `OUTPUT_DIR`. | A pasta do job. |
| pasta do job | Diretório em `pending/` com o estado e o áudio de um job. | A pasta de atas. |
| sessão | Período de trabalho de uma ferramenta de IA no projeto (ver Protocolo de sessão no `AGENTS.md`). | A gravação ou a reunião. |
