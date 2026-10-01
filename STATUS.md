# Status

Atualizado em: 2026-10-01 (fim do dia)

## Em andamento
- Nada em execução. ADRs 0001 a 0018 em `docs/decisions/`; o 0010 (limite de 30 minutos) é proposta e aguarda confirmação. 61 testes passam. Os quatro modelos de resumo (ADR 0018) estão no código e instalados em `/Applications/Minuta.app`. Falta abrir uma ata antiga com `modelo: acompanhamento` para ver a linha de aviso na janela de leitura (só há teste unitário).

Estado atual do app:
- Barra de menus com `NSStatusItem`: ícone de microfone fixo e estado pelo fundo do botão (verde gravando, vermelho pausado, amarelo processando); menu com Iniciar gravação, as 5 atas recentes, Atas…, Configurações… e Sair (ADRs 0011, 0014 e 0015).
- Gravação com pausar, continuar e encerrar, contador, lembrete de pausa, confirmação ao sair gravando e limite de 30 minutos de tempo gravado (ADRs 0010 e 0013).
- Transcrição pelo Gemini 3.5 Transcribe, classificação e resumo pelo Claude Sonnet 5.5, com provedores e chaves no `.env` (ADRs 0002, 0008, 0012 e 0017).
- Resumos por tipo de reunião (ADRs 0017 e 0018): ao fim da transcrição, o app classifica a reunião (modelo, confiança, justificativa e título), grava o `.md` e o `.resumos.json` e gera o resumo no modelo sugerido. Quatro modelos: Decisão, Problemas e ideias, Informativa e Geral (ADR 0018; o Acompanhamento saiu, e reunião de status vai para Geral). Todos os resumos gerados ficam guardados no secundário; o escolhido é copiado no `.md`, que é legível sozinho.
- Janela de leitura: o conteúdo fica num card centralizado de até 760 px sobre o fundo da janela; as chips têm balão de dica nativo (`NSPopover`, `PageTips`) com serve para, mostra e use quando, e os lápis e o refazer usam o mesmo balão (ADR 0017); verificado por captura de tela num teste temporário com mouse sintético, não com o mouse real. Chips de modelo abaixo do título (ponto nos já gerados, linha "Sugerido", indicador ao gerar, ícone de refazer), lápis no título e lápis de cada participante, ambos renomeando no lugar (ADRs 0016 e 0017).
- Janela "Atas…" no estilo do Finder (ADR 0015): tabela com colunas Data, Título, Resumo e Duração ordenáveis, sem botões nas linhas, gravações em andamento como linhas, datas relativas, ponto colorido na coluna Resumo, menu de contexto (Abrir, Mostrar no Finder, Resumo ▸, Mover para a Lixeira, Renomear; Tentar de novo e Descartar… nas gravações), Return renomeia, duplo clique e ⌘O abrem, ⌘⌫ move para a Lixeira sem pergunta. Verificação da pasta de atas e nome de arquivo por data e hora.
- Configurações em página única, com a versão no rodapé; regra de seguir as HIG da Apple, com dois desvios registrados (botão da barra de menus, ADR 0014; chips de modelo, ADR 0017).

Verificado pelo usuário: captura do áudio do sistema, gravação com microfone, pausa e continuação, gravação de teste de fone, Apagar uma ata, e o desenho das chips e da janela de atas (aprovado em mockups; o usuário testou as janelas e pediu ajustes, já aplicados).

Verificado por mim no app instalado (capturas de tela e teclas enviadas direto ao processo): todos os estados do botão, a janela de atas, a leitura com os links, a faixa de pasta ausente, o campo de renomear e o desfazer, trocar de modelo (instantâneo para um guardado, geração para um novo), refazer o resumo, renomear o título, ordenar por cabeçalho, menu de contexto com o submenu Resumo, Return, Esc, ⌘O, ⌘W, duplo clique e ⌘⌫.

Verificado com chaves reais: os cenários sintéticos (`tools/synthetic-meeting/scenarios/`) passaram pelo `--process` (sete na primeira rodada, os oito na segunda), e a classificação acertou o modelo esperado em todos (01 Decisão, 02 Acompanhamento (hoje Geral, ADR 0018), 03 Problemas e ideias, 04 Informativa, 05 Geral, 06 Decisão, 07 sem sugestão por confiança baixa, 08 Acompanhamento ou Decisão; Acompanhamento deixou de existir no ADR 0018). O cenário 8 rodou com "Seu nome" vazio (rótulo "Eu"). As atas do cenário foram copiadas para a pasta de atas do usuário e depois apagadas por ele. Plano de validação: teste 8.

Ainda sem teste manual:
- Janela de atas: linhas de gravação em andamento (só teste unitário), Tentar de novo, Descartar…, Mostrar no Finder, gerar um modelo novo pelo submenu Resumo, a janela de leitura acompanhando um renomear feito na lista, menu de uma ata com problema e botões da faixa de pasta ausente.
- Falha de rede na geração automática do resumo; secundário apagado ou ilegível (o `.md` continua legível, mas não dá para trocar de modelo; reconstruir a partir do principal não foi feito).
- Renomear: rolar ou redimensionar com o campo aberto; nomes inferidos pelo modelo no app; atas muito longas.
- Configurações: Permitir, Testar captura, Escolher… e Abrir ao iniciar o Mac.
- Barra de menus clara, outros papéis de parede e VoiceOver (inclusive nas chips de modelo).

Limites conhecidos:
- O cabeçalho da `Table` é o do sistema. Tentei ajustar fonte e cor pelo AppKit (trocando a célula de cabeçalho de cada coluna) e não teve efeito, porque o SwiftUI desenha o cabeçalho por conta própria; o código foi removido. Mudar o estilo exige uma `NSTableView` do AppKit (reescrita da janela). Decisão: manter.
- A `Table` do macOS 13 não permite clicar de novo no nome para renomear, Quick Look nem reordenar colunas.
- O `--process` grava `duracao_segundos: 0` porque não conhece a duração.
- O nome do usuário com espaço no fim ("JULIANO ") aparece com o espaço na lista de participantes.
- No cenário 6, a diarização juntou a fala da Gabriela à da Roberta (Participante 1) num segmento, e uma ação saiu com a pessoa errada. É limite da transcrição (duas vozes femininas em turnos seguidos), não do resumo.
- A camada gratuita do Google recusa o terceiro pedido por minuto; cada reunião usa dois.

## Descobertas
<!-- fato aprendido durante o trabalho que muda o próximo passo -->
- Comparação dos cinco modelos nos cenários 01 a 05 (25 resumos, 2026-10-01): o miolo muda pouco, e o modelo errado impõe estrutura sem evidência (decisão inventada, meta tratada como decisão, bloqueio fabricado). Resultado no ADR 0018. Com a regra de seção vazia e os blocos reforçados, os mesmos cenários melhoraram (seções vazias no modelo errado, classificação correta nos cinco), mas o Decisão do 05 e do 02 ainda preenche "decisões" sem decisão do grupo.
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
- Modelo Acompanhamento e Informativa ampla: o Geral entrega o mesmo conteúdo e a Informativa se confundia com o status (ADR 0018). Estrutura única adaptativa sem seletor: recomendada pela comparação, mas o usuário manteve três tipos próprios mais o Geral.
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
- Controle de modelos nativo ou menu pop-up na leitura: o usuário escolheu as chips entre três mockups (ADR 0017).
- Botões e ícones nas linhas da lista de atas: trocados pelo menu de contexto, como no Finder (ADR 0015). Ícone de documento no título: não informa, todas as linhas são do mesmo tipo.
- Estilo do cabeçalho da tabela pelo AppKit: sem efeito na `Table` do SwiftUI.

## Próximos
- Conferir os `expected.md` dos oito cenários contra os resumos gerados e ajustar os blocos dos modelos onde faltar (acerto de responsáveis, prazos e armadilhas). Rodar os cenários 06 a 08 com os quatro modelos (só 01 a 05 foram refeitos depois do ADR 0018).
- Avaliar se Decisão em reunião sem decisão deve ser bloqueada ou só avisada (o prompt reduz, não impede; ADR 0018).
- Reuniões reais: confirmar que quatro modelos bastam e que o Geral de status serve no lugar do Acompanhamento.
- Testar manualmente o que está em "Ainda sem teste manual", em especial a falha da geração automática e o secundário ilegível.
- Conferir nas fontes primárias as citações de Tropman, Romano e Nunamaker e Monge usadas no ADR 0017.
- Confirmar o limite de 30 minutos (ADR 0010).
- Gravar uma reunião real com voz (3 ou mais participantes) e conferir transcrição, diarização, classificação e resumo (teste 6).
- Teste de eco sem fone (alto-falante e microfone abertos), para medir o quanto o eco vaza para a ata e decidir se vale o cancelamento de eco.
- Medir o custo em tokens e o tempo por reunião (classificação mais resumo), e comparar o esforço `medium` com `high`.
- Migrar a chave do Google para a camada paga antes de gravar reuniões reais.
- Ler os termos de dados do Google e da Anthropic (teste 7).
- Pendências da revisão de HIG: reticências em "Abrir arquivo…" e "Gravando 5 s…", um só botão de destaque em Permissões, "Configurações" ou "Ajustes" (a confirmar) e a grafia do nome do app.
- ADR próprio para o envio da ata por e-mail e a consulta por conectores (exige rever a regra de que nada vai para a nuvem).
- Opcionais, se o risco ou o uso pedirem: reconstruir o secundário a partir do `.md`, cópia interna das atas com restauração (detecta ata apagada), cancelamento de eco.
- Confirmar o público do projeto (hoje registrado como uso próprio).

## Bloqueado
- Nada.
