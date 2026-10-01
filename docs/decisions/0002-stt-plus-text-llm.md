# 0002. Pipeline de IA: STT dedicado e LLM de texto

Status: aceita
Data: 2026-09-30
Substitui: seção 2 (Processamento de IA) e o estado Processando da seção 3 de `docs/project-brief.md`.

## Contexto

O brief enviava o áudio bruto a um LLM multimodal, que devolvia ata e transcrição numa chamada. A transcrição é o artefato principal do projeto. Em áudio longo, LLM multimodal tende a omitir trechos, inventar conteúdo e rotular falantes de forma instável, e alinha mal as notas ao tempo.

## Decisão

Dois passos:
1. STT dedicado transcreve o áudio, com timestamps.
2. LLM de texto recebe a transcrição segmentada, com IDs de segmento, e gera a ata (ADR 0005).

## Consequências

- A transcrição é gravada em disco antes do resumo. O áudio é apagado nesse ponto, não após o destino final. A regra de retenção "manter até o sucesso" continua, com sucesso definido como transcrição gravada.
- Falha no resumo reprocessa só o texto, sem reenviar áudio.
- O STT precisa entregar timestamps por segmento, áudio multicanal e diarização no canal do sistema (ADR 0006). Provedor escolhido: Gemini 3.5 Transcribe (ADR 0008).
- LLM da ata: Claude Sonnet 5.5 (`claude-sonnet-5-5`), escolhido em 2026-09-30 por custo e qualidade em texto. A API do Claude não aceita áudio, então ele só recebe a transcrição segmentada.
- Integração com o Sonnet 5.5: usar saída estruturada (`output_config.format`) para o JSON de decisões, ações e IDs de segmento. `tool_choice` forçado retorna 400. O esforço padrão é `high`; definir `medium` explicitamente e medir.
- Duas chaves no Keychain: Google (STT) e Anthropic (ata). O texto das reuniões sai para a Anthropic; a política de retenção de dados entra nas verificações do ADR 0008.
- Duas chamadas e, possivelmente, duas chaves. Provedores de STT e de LLM são escolhas em aberto.
- Se um provedor entregar transcrição com timestamps e qualidade equivalente numa chamada só, reavaliar esta decisão.

## Alternativas descartadas

- LLM multimodal único: menor custo de integração, pior confiabilidade da transcrição e reprocessamento que exige reenviar o áudio.
