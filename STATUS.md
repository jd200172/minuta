# Status

Atualizado em: 2026-10-01

## Em andamento
- Primeira versão do app em Swift (ADR 0009): compila, abre na barra de menus e tem 3 testes passando. O pipeline de transcrição e ata foi exercitado de ponta a ponta com o áudio sintético e as chaves reais (modo `--process`). A captura do áudio do sistema pelo app foi testada pelo usuário e funcionou (teste de 5 s). Falta uma gravação completa pelo menu, até a ata.
- Decisões em `docs/decisions/` (ADRs 0001 a 0013). O ADR 0010 (limite de 30 minutos) é proposta e aguarda confirmação.
- Áudio sintético de teste em `tools/synthetic-meeting/out/` (253 s, 4 vozes: 1 no microfone, 3 no sistema, 3 sobreposições). Gabarito em `tools/synthetic-meeting/expected.md`.
- Mockups das telas no chat. Não implementados: tela de primeiro uso, teste de captura, "Abrir transcrição" na falha da ata.

- ADR 0012 implementado: chaves e provedores no `.env` (`~/Library/Application Support/Minuta/.env`), `Transcriber` e `Minuter` como protocolos, aba de chaves removida, migração do Keychain na primeira abertura. Compila e os 9 testes passam. Não executado: o app não foi instalado nem aberto depois da mudança (o usuário removeu `/Applications/Minuta.app`), então a migração, o botão que abre o arquivo e o aviso de chave ausente estão sem teste manual.
- ADR 0013 implementado: pausar, continuar e encerrar a gravação, contador na barra de menus, confirmação ao sair gravando e lembrete de pausa a cada 10 min. Compila e os testes passam. Sem teste manual: o menu nos três estados, a pausa no áudio gravado, o contador e o aviso de saída.
- Janela de configurações em página única implementada (mockup B atualizado), instalada e verificada por captura de tela. Não verificado por clique: botões Permitir, Testar captura, Escolher…, o interruptor Abrir ao iniciar o Mac e a linha Reabrir o minuta.
- Revisão contra as HIG (regra no `AGENTS.md`): corrigidos o pedido de permissão de notificação (agora só na primeira notificação), o Esc nos avisos (botão seguro de cada aviso) e ⌘W e Esc na janela de configurações. Verificado: ⌘W e Esc fecham a janela no app instalado; o Esc dos avisos foi testado num script à parte, não no app. Pendentes da revisão: rótulo de acessibilidade do ícone da barra de menus, reticências em "Abrir arquivo…" e "Gravando 5 s…", um só botão de destaque em Permissões, botão "Escolher" no painel de pasta, "Configurações" vs "Ajustes" (a confirmar) e grafia do nome do app.
- ADR 0014 implementado com `NSStatusItem`: ícone de microfone fixo, fundo verde (gravando), vermelho com símbolo de pausa (pausado) e amarelo com spinner (processando); gravação e processamento juntos mostram a cor da gravação com o spinner. Verificado no app instalado por capturas da barra de menus em todos os estados, inclusive iniciar uma gravação durante o processamento. Não verificado: barra de menus clara, outros papéis de parede, VoiceOver e o aviso de sair gravando com o novo menu.
- ADR 0015 implementado: janela Atas (lista por data e título, Abrir, Apagar com Lixeira, seção Em andamento com Tentar de novo e Descartar), 5 atas recentes no menu, leitura em página com links para a transcrição, nome do arquivo com título e sem ata para transcrição com menos de 10 palavras. Verificado no app instalado: menu, lista, janela de leitura, clique nos horários (leva ao trecho e o destaca), linha de falha e aviso de gravação sem fala. Um erro encontrado no teste e corrigido: o link de âncora era bloqueado pela política de navegação. Não verificado por clique: Apagar e Descartar (confirmações e Lixeira), Tentar de novo e o botão Mostrar no Finder. 18 testes passam.

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
- Keychain para as chaves: o aviso de autorização volta em qualquer build com assinatura diferente (ADR 0012).
- Python com `pystray`, `pyobjc` e `customtkinter`: mais dependências e empacotamento frágil com uma só plataforma (ADR 0009).
- Notion e Supabase como destino do MVP (ADR 0001).
- LLM multimodal único para transcrição e ata (ADR 0002).
- Mixagem em mono (ADR 0004).
- "Outros" como bloco único (ADR 0006).
- Tipos de reunião e notas no MVP (ADR 0007).
- Dois arquivos por reunião, ata e transcrição (ADR 0005).
- Gravação de 27 s com microfone conectado: a ata mostrou um "Participante 1" que só disse "É". Uma segunda gravação de 30 s, de fone e com o Mac sem tocar nada, não gerou participante falso. O mais provável é eco (a voz do usuário voltando pelo alto-falante para o canal do sistema); a hipótese de o transcritor inventar fala num canal em silêncio perdeu força. Sem fone, o eco é esperado; cancelamento de eco (processamento de voz do `AVAudioEngine`) não foi adotado.
- O campo "Seu nome" estava salvo como `.... ` e apareceu como rótulo do usuário na ata. É valor digitado, não falha do app.
- O Gemini trocou palavras em português numa fala do microfone ("participante 1" virou "participantium"). Registrar como dado do teste 6 (voz real).

## Próximos
- Interface revisada e instalada em `/Applications` (ADR 0011): menu mínimo, erros por aviso, configurações em abas. Verificado por captura de tela das três abas. Não verificado: cliques nos botões, avisos de erro, opção Abrir ao iniciar o Mac.
- Confirmar o limite de 30 minutos (ADR 0010).
- Gravar 30 a 60 segundos de um vídeo com fala pelo menu do app e conferir a ata em `~/Documents/Atas`.
- Teste de eco sem fone (alto-falante e microfone abertos), para medir o quanto o eco vaza para a ata e decidir se vale o cancelamento de eco.
- Medir o custo em tokens e o tempo por ata, e comparar o esforço `medium` com `high`.
- Migrar a chave do Google para a camada paga antes de gravar reuniões reais.
- Ler os termos de dados do Google e da Anthropic (teste 7).
- Confirmar o público do projeto (hoje registrado como uso próprio).

## Bloqueado
- Nada.
