# Status

Atualizado em: 2026-09-30

## Em andamento
- Primeira versão do app em Swift (ADR 0009): compila, abre na barra de menus e tem 3 testes passando. O pipeline de transcrição e ata foi exercitado de ponta a ponta com o áudio sintético e as chaves reais (modo `--process`). A captura do áudio do sistema pelo app foi testada pelo usuário e funcionou (teste de 5 s). Falta uma gravação completa pelo menu, até a ata.
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
- A assinatura ad hoc muda a identidade do binário a cada build e o macOS pedia as permissões de novo. Resolvido com a identidade local "Minuta Dev" (`scripts/setup-signing.sh`): o requisito designado é o mesmo depois de recompilar.
- O app só aparece na lista de Gravação de Tela depois de pedir acesso. A tela de configurações anterior abria os Ajustes sem pedir, e o botão Salvar não dava retorno nem tratava erro do Keychain. Corrigido; as chaves passam a usar o serviço `app.minuta.Minuta.keys` e precisam ser digitadas de novo uma vez.
- Este Mac é um Mac mini sem microfone embutido e sem entrada de áudio conectada. O app travava ao iniciar a gravação (`installTap` sem dispositivo de entrada). Agora grava só o áudio do sistema e avisa quando não há microfone. Para gravar a própria voz, conecte um microfone (fone, webcam ou USB).
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
- Interface revisada e instalada em `/Applications` (ADR 0011): menu mínimo, erros por aviso, configurações em abas. Verificado por captura de tela das três abas. Não verificado: cliques nos botões, avisos de erro, opção Abrir ao iniciar o Mac.
- Confirmar o limite de 30 minutos (ADR 0010).
- Gravar 30 a 60 segundos de um vídeo com fala pelo menu do app e conferir a ata em `~/Documents/Atas`.
- Conectar um microfone e repetir o teste de captura, para validar o canal do usuário e o eco.
- Medir o custo em tokens e o tempo por ata, e comparar o esforço `medium` com `high`.
- Migrar a chave do Google para a camada paga antes de gravar reuniões reais.
- Ler os termos de dados do Google e da Anthropic (teste 7).
- Confirmar o público do projeto (hoje registrado como uso próprio).

## Bloqueado
- Nada.
