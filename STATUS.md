# Status

Atualizado em: 2026-10-01

## Em andamento
- Nada em execução. ADRs 0001 a 0017 em `docs/decisions/` (o 0017, resumo sob demanda com cinco modelos, está decidido e não implementado; mockups aprovados na conversa); o 0010 (limite de 30 minutos) é proposta e aguarda confirmação. 31 testes passam. O app está instalado em `/Applications/Minuta.app`.

Estado atual do app:
- Barra de menus com `NSStatusItem`: ícone de microfone fixo e estado pelo fundo do botão (verde gravando, vermelho pausado, amarelo processando) (ADRs 0011 e 0014).
- Gravação com pausar, continuar e encerrar, contador, lembrete de pausa, confirmação ao sair gravando e limite de 30 minutos de tempo gravado (ADRs 0010 e 0013).
- Transcrição pelo Gemini 3.5 Transcribe e ata pelo Claude Sonnet 5.5, com provedores e chaves no `.env` (ADRs 0002, 0008 e 0012).
- Janela "Atas…" (lista por data e título, Abrir, Apagar com Lixeira, gravações em andamento com Tentar de novo e Descartar), 5 atas recentes no menu, leitura em página com links para a transcrição, verificação da pasta de atas e nome de arquivo com título (ADR 0015).
- Nomes de participantes pelo lápis da janela de leitura, valendo só na própria ata (ADR 0016).
- Configurações em página única, com a versão no rodapé; regra de seguir as HIG da Apple.

Verificado pelo usuário: captura do áudio do sistema, gravação com microfone, pausa e continuação, gravação de teste de fone e Apagar uma ata.

Verificado por mim no app instalado (capturas de tela e scripts): todos os estados do botão, a janela de atas, a leitura com os links, a faixa de pasta ausente, o campo de renomear e o desfazer.

Ainda sem teste manual:
- Janela de atas: Descartar, Tentar de novo e Mostrar no Finder; botões da faixa de pasta ausente.
- Renomear: rolar ou redimensionar com o campo aberto; nomes inferidos pelo modelo no app; atas muito longas.
- Configurações: Permitir, Testar captura, Escolher… e Abrir ao iniciar o Mac.
- Barra de menus clara, outros papéis de parede e VoiceOver.

## Decisão pendente de implementação (ADR 0017)
- Classificação ao fim da transcrição devolve modelo sugerido, justificativa e título; o sugerido é gerado automaticamente. Cinco modelos: Decisão, Acompanhamento, Problemas e ideias, Informativa, Geral.
- Dois arquivos: principal `AAAA-MM-DD HHmm Título.md` (frontmatter, cópia do resumo escolhido, transcrição) e secundário `AAAA-MM-DD HHmm.resumos.json` (todos os resumos). Chave: `inicio`. Trocar de modelo reaproveita ou gera; nada é descartado; "Refazer este resumo" substitui o do modelo.
- A implementação muda `MinutesPrompt`, `Minutes`, `AppModel`, `Job`, `AtaLibrary`, `AtaViewer`, `MarkdownHTML` e os testes. O título editável entra no MVP.
- Em aberto: formato do JSON e da marca de seção gerada, onde guardar a classificação durante a geração, confirmação ao refazer, aviso de secundário ilegível.
- Fora: envio por e-mail e consultas por conectores (ADR próprio depois).

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
- O app só aparece na lista de Gravação de Tela depois de pedir acesso. A tela de configurações anterior abria os Ajustes sem pedir, e o botão Salvar não dava retorno nem tratava erro do Keychain. Corrigido; as chaves hoje ficam no `.env` (ADR 0012).
- Este Mac é um Mac mini sem microfone embutido e sem entrada de áudio conectada. O app travava ao iniciar a gravação (`installTap` sem dispositivo de entrada). Agora grava só o áudio do sistema e avisa quando não há microfone. Para gravar a própria voz, conecte um microfone (fone, webcam ou USB).
- Um app Swift em repouso usa cerca de 79 MB de RSS e 0% de CPU.
- Um campo de texto nativo sobre uma `WKWebView` fica transparente: é preciso uma `NSView` opaca por baixo. A `WKWebView` com JavaScript da página desligado ainda responde a `evaluateJavaScript` chamado pelo app, o que permite medir a posição de um elemento sem executar nada da página.
- Com a base `about:blank`, o `URL` do Foundation não extrai o fragmento (`about:blank#id`); a navegação para âncoras precisa comparar a string.
- Gravações de silêncio geravam atas com títulos como "sem conteúdo identificável"; hoje transcrições com menos de 10 palavras não geram ata (ADR 0015).

## Descartado
<!-- hipótese ou abordagem descartada e o motivo -->
- Keychain para as chaves: o aviso de autorização volta em qualquer build com assinatura diferente (ADR 0012).
- Python com `pystray`, `pyobjc` e `customtkinter`: mais dependências e empacotamento frágil com uma só plataforma (ADR 0009).
- Notion e Supabase como destino do MVP (ADR 0001).
- LLM multimodal único para transcrição e ata (ADR 0002).
- Mixagem em mono (ADR 0004).
- "Outros" como bloco único (ADR 0006).
- Tipos de reunião e notas no MVP (ADR 0007). Os tipos voltaram ao escopo pelo ADR 0017; notas continuam fora.
- Dois arquivos por reunião, ata e transcrição (ADR 0005).
- Gravação de 27 s com microfone conectado: a ata mostrou um "Participante 1" que só disse "É". Uma segunda gravação de 30 s, de fone e com o Mac sem tocar nada, não gerou participante falso. O mais provável é eco (a voz do usuário voltando pelo alto-falante para o canal do sistema); a hipótese de o transcritor inventar fala num canal em silêncio perdeu força. Sem fone, o eco é esperado; cancelamento de eco (processamento de voz do `AVAudioEngine`) não foi adotado.
- O campo "Seu nome" estava salvo como `.... ` e apareceu como rótulo do usuário na ata. É valor digitado, não falha do app.
- O Gemini trocou palavras em português numa fala do microfone ("participante 1" virou "participantium"). Registrar como dado do teste 6 (voz real).
- Banco de dados ou pasta interna do app para as atas, e um submenu por ata no menu: ver ADR 0015.
- Folha única com todos os participantes aberta por um botão da barra de título (ADR 0016): invasiva; trocada pelo lápis individual.
- Anotações "(canal do microfone)" e "nome informado por você" na lista de participantes: redundantes (ADR 0016).

## Próximos
- Implementar o ADR 0017 e criar cinco reuniões sintéticas (uma por modelo) com resultado esperado, para testar os modelos e a acurácia do classificador.
- Conferir nas fontes primárias as citações de Tropman, Romano e Nunamaker e Monge usadas no ADR 0017.
- Confirmar o limite de 30 minutos (ADR 0010).
- Gravar uma reunião real com voz (3 ou mais participantes) e conferir transcrição, diarização e ata (teste 6).
- Teste de eco sem fone (alto-falante e microfone abertos), para medir o quanto o eco vaza para a ata e decidir se vale o cancelamento de eco.
- Medir o custo em tokens e o tempo por ata, e comparar o esforço `medium` com `high`.
- Migrar a chave do Google para a camada paga antes de gravar reuniões reais.
- Ler os termos de dados do Google e da Anthropic (teste 7).
- Pendências da revisão de HIG: reticências em "Abrir arquivo…" e "Gravando 5 s…", um só botão de destaque em Permissões, "Configurações" ou "Ajustes" (a confirmar) e a grafia do nome do app.
- Opcionais, se o risco ou o uso pedirem: cópia interna das atas com restauração (detecta ata apagada), regenerar o resumo com os nomes dos participantes (corrige artigos), cancelamento de eco.
- Confirmar o público do projeto (hoje registrado como uso próprio).

## Bloqueado
- Nada.
