# Status

Atualizado em: 2026-09-30

## Em andamento
- Primeira versão do app em Swift (ADR 0009): compila, abre na barra de menus e tem 3 testes passando. O pipeline de transcrição e ata foi exercitado de ponta a ponta com o áudio sintético e as chaves reais (modo `--process`). A captura de áudio pelo app ainda não foi testada: depende das permissões do macOS concedidas por uma pessoa.
- Decisões em `docs/decisions/` (ADRs 0001 a 0010). O ADR 0010 (limite de 30 minutos) é proposta e aguarda confirmação.
- Áudio sintético de teste em `tools/synthetic-meeting/out/` (253 s, 4 vozes: 1 no microfone, 3 no sistema, 3 sobreposições). Gabarito em `tools/synthetic-meeting/expected.md`.
- Mockups das telas no chat. Não implementados: tela de primeiro uso, teste de captura, "Abrir transcrição" na falha da ata.

## Descobertas
<!-- fato aprendido durante o trabalho que muda o próximo passo -->
- Gemini 3.5 Transcribe limita o áudio a 30 minutos por pedido com diarização ou timestamps por palavra (documentação do Google). Uma gravação de 60 minutos exigiria dividir em partes sem garantia de rótulos de falante consistentes (ADR 0010).
- Gemini 3.5 Transcribe marca como experimental a atribuição com 3 ou mais falantes e não cita português especificamente (fonte secundária).
- `custom_vocabulary` não combina com diarização nem com timestamps no Gemini 3.5 Transcribe.
- Claude não aceita áudio na API, então a transcrição exige um provedor de fala separado.
- Formato dos pedidos ao Gemini e da resposta (`steps[].content[].annotations`, `word_info`) confirmado com chave real: funcionou na primeira chamada.
- Com áudio sintético: texto com cerca de 1% de diferença, 28 de 28 falas do canal do sistema com o falante correto, horários com diferença máxima de 0,11 s. Resultados em `docs/validation-plan.md`.
- A ata do Sonnet 5.5 estava citando 4 a 7 trechos por item, listando a antecipação descartada como decisão e gerando pontos em aberto extras. Após o ajuste do prompt (no máximo 3 trechos, proposta descartada fora de decisões), passou nos 5 critérios em 2 execuções.
- A camada gratuita do Google limita o `gemini-3.5-transcribe` a 3 pedidos por minuto (cada reunião usa 2). A chave atual está na camada gratuita, na qual o Google usa o conteúdo para melhorar produtos e revisores humanos podem lê-lo. Reuniões reais exigem a camada paga.
- Assinatura ad hoc muda a identidade do binário a cada build: o macOS pode pedir as permissões de novo. Não há certificado de desenvolvimento neste Mac.
- Um app Swift em repouso usa cerca de 79 MB de RSS e 0% de CPU.

## Descartado
<!-- hipótese ou abordagem descartada e o motivo -->
- Python com `pystray`, `pyobjc` e `customtkinter`: mais dependências e empacotamento frágil com uma só plataforma (ADR 0009).
- Notion e Supabase como destino do MVP (ADR 0001).
- LLM multimodal único para transcrição e ata (ADR 0002).
- Mixagem em mono (ADR 0004).
- "Outros" como bloco único (ADR 0006).
- Tipos de reunião e notas no MVP (ADR 0007).
- Dois arquivos por reunião, ata e transcrição (ADR 0005).

## Próximos
- Confirmar o limite de 30 minutos (ADR 0010).
- Rodar o app: conceder microfone e Gravação de Tela e gravar 30 segundos com um vídeo tocando (teste 1 do `docs/validation-plan.md`).
- Medir o custo em tokens e o tempo por ata, e comparar o esforço `medium` com `high`.
- Migrar a chave do Google para a camada paga antes de gravar reuniões reais.
- Ler os termos de dados do Google e da Anthropic (teste 7).
- Confirmar o público do projeto (hoje registrado como uso próprio).

## Bloqueado
- Teste de captura pelo app (teste 1): depende das permissões do macOS concedidas por você.
