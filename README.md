# minuta

Aplicativo de barra de menus para macOS que grava uma reunião virtual, transcreve o áudio e gera uma ata em Markdown com um resumo no modelo adequado ao tipo da reunião (decisão, problemas e ideias, informativa ou geral), participantes, itens de ação e pontos em aberto. Cada item aponta para o trecho da transcrição que o originou.

Uso próprio. Estado atual: MVP validado com áudio sintético em oito cenários; falta validar com voz real (ver [Estado](#estado)).

## Como funciona

1. **Captura.** O app grava o microfone e o áudio do sistema (a voz dos outros participantes) em dois arquivos mono, AAC `.m4a` a 16 kHz. O microfone passa pelo cancelamento de eco do macOS, que tira dele o som que sai do alto-falante (opção em Configurações, ligada por padrão). Sem microfone conectado, grava só o áudio do sistema.
2. **Transcrição.** Cada arquivo vai para o Gemini 3.5 Transcribe. O canal define quem fala: o do microfone leva o seu nome, e o do sistema passa por diarização e vira "Participante 1", "Participante 2" etc. É a prática dos serviços de transcrição quando há canais separados ([ADR 0024](docs/decisions/0024-follow-market-practice-for-capture.md)). O áudio é guardado com o mesmo nome do arquivo de resumos (`AAAA-MM-DD HHmm.mic.m4a` e `.system.m4a`) na pasta de atas e vai para a Lixeira junto com a ata.
3. **Classificação e resumo.** A transcrição segmentada vai para o Claude Sonnet 5.5, que sugere um de quatro modelos de resumo (Decisão, Problemas e ideias, Informativa, Geral) e um título. O app gera o resumo no modelo sugerido. Na janela de leitura, você corrige os nomes dos participantes e troca de modelo: o que já foi gerado fica guardado e troca na hora, e o que não existe é gerado ao clicar. O app valida que todo trecho citado existe e monta o arquivo `.md`.

O resultado é um arquivo por reunião na pasta escolhida, com a transcrição ao final. O nome é `AAAA-MM-DD HHmm Título.md`, e ao lado fica `AAAA-MM-DD HHmm.resumos.json`, com a transcrição segmentada e todos os resumos gerados dessa reunião. O `.md` mostra o resumo escolhido e é legível sozinho, também fora do app. O prefixo com a data e a hora de início da gravação não muda; o título pode ser renomeado.

- **Janela de leitura.** Abaixo do título ficam as quatro chips de modelo, cada uma com um balão de dica (serve para, mostra, use quando); os lápis, o ícone de refazer e as citações usam o mesmo balão. O conteúdo fica num card centralizado de até 760 px. A chip do modelo exibido vem preenchida, e um ponto marca os modelos que já têm resumo; clicar em um deles troca na hora, e clicar em um novo gera o resumo. A linha "Sugerido: …" mostra o que a classificação indicou e por quê. O ícone de atualizar refaz o resumo do modelo exibido. O lápis ao lado do título renomeia a reunião no lugar, e o lápis de cada participante nomeia aquela voz. A transcrição é um bloco que recolhe e expande (o estado fica lembrado por reunião), e o horário de cada citação abre um balão com o trecho e um segmento de cada lado, com o horário que leva ao ponto na transcrição (ADR 0019).
- **Janela de correção.** Aberta pelo botão "Corrigir a transcrição" da janela de leitura ou pelo menu de contexto da lista. Clicar no horário de uma fala toca o áudio a partir dali (espaço pausa, velocidade de 0,75x a 1,5x). O texto se corrige no lugar, o falante se troca por um menu, e cada fala pode ser apagada ou restaurada ao original. Depois de corrigir, a leitura avisa que o resumo está desatualizado, e o ícone de refazer gera de novo ([ADR 0025](docs/decisions/0025-transcript-correction-window.md)).
- **Janela Atas…** É uma tabela no estilo do Finder, com colunas Data, Título, Resumo e Duração ordenáveis. Return renomeia, duplo clique ou ⌘O abre, e ⌘⌫ move para a Lixeira, sem pergunta. O botão direito traz Abrir, Mostrar no Finder, Mostrar áudio no Finder, Corrigir transcrição…, Resumo ▸ (os quatro modelos), Mover para a Lixeira e Renomear. As gravações ainda em andamento aparecem como linhas da tabela, com Tentar de novo e Descartar… no menu de contexto.
- **Menu da barra.** Mostra as 5 últimas atas.
- **Pasta de atas.** Se ela sumir, ou se algum arquivo estiver vazio ou ilegível, a janela avisa. O app não sabe de uma ata que foi apagada, então mantenha a pasta com backup (por exemplo, no OneDrive).

Um exemplo de ata, gerada com o áudio sintético de teste, está em [`tools/synthetic-meeting/sample/ata.md`](tools/synthetic-meeting/sample/ata.md) (formato anterior ao ADR 0017).

Os nomes dos participantes só substituem o rótulo quando a transcrição os identifica (apresentação, saudação ou vocativo), e a ata marca o nome como inferido. Quando o app não identifica alguém, o lápis ao lado de cada participante, na janela de leitura, renomeia aquela voz no próprio lugar; o nome vale só para aquela ata, substitui o rótulo em todo o texto e entra nos resumos gerados depois. Atas geradas antes dos modelos de resumo continuam abrindo como antes, sem as chips.

## Requisitos

- macOS 13 ou superior (desenvolvido e testado no macOS 27).
- Xcode com Swift 6 (o app é um pacote SwiftPM, sem dependências de terceiros).
- Chave de API do Google ([AI Studio](https://aistudio.google.com/apikey)) e da Anthropic ([Claude Console](https://platform.claude.com/settings/keys)).
- ffmpeg com libopus e `say`/`afconvert` do macOS, só para gerar o áudio de teste.

## Instalação

```bash
./scripts/setup-signing.sh   # uma vez: cria a identidade de assinatura local
./scripts/install.sh         # compila, instala em /Applications e abre
```

`setup-signing.sh` cria a identidade "Minuta Dev" num chaveiro separado do chaveiro de login. Com ela, o macOS reconhece o app como o mesmo a cada build e não pede as permissões de novo. Sem ela, o build usa assinatura ad hoc e avisa.

O app não aparece no Dock. Abra-o pelo Spotlight ou pelo Launchpad. Abrir o app que já está rodando abre as configurações.

## Primeiro uso

1. Clique no ícone de microfone na barra de menus e abra **Configurações…** (⌘,).
2. Em **Chaves e modelos de IA**, abra o arquivo e preencha `GOOGLE_API_KEY` e `ANTHROPIC_API_KEY`. O arquivo é `~/Library/Application Support/Minuta/.env`, com permissão `600`, e o app o lê a cada uso.
3. Conceda **Microfone** e **Gravação de tela e áudio do sistema**. Depois da segunda, o macOS pede para reabrir o app.
4. Use **Testar captura** para confirmar que o som chega.
5. Escolha **Iniciar gravação** no menu. O tempo gravado aparece ao lado do ícone. Use **Pausar gravação** e **Continuar gravação** para um intervalo e **Encerrar gravação** para processar. O app transcreve, sugere um modelo de resumo e gera o resumo sugerido; uma notificação avisa quando o resumo estiver pronto, ou que a transcrição foi salva e que falta escolher o modelo.

O ícone é sempre o microfone, e o estado aparece no fundo do botão: sem fundo (parado), verde com o tempo correndo (gravando), vermelho com o tempo parado e o símbolo de pausa (pausada) e amarelo com um spinner (transcrevendo ou classificando). Se você iniciar outra gravação durante o processamento, vale a cor da gravação e o spinner fica ao lado do tempo. Erros viram um aviso com a causa e, se for o caso, a opção de tentar de novo.

## Limites

- **30 minutos de gravação** (a pausa não conta). O Gemini 3.5 Transcribe limita o áudio a 30 minutos por pedido com diarização. No teto, o app encerra a captura e processa. O limite é uma proposta aguardando confirmação ([ADR 0010](docs/decisions/0010-recording-limit-30-minutes.md)).
- **Só reuniões virtuais.** Em reunião presencial, o microfone captaria várias vozes sob um único rótulo.
- **Uma queda do app durante a gravação, ou uma saída forçada, perde aquela gravação** (sair pelo menu pede confirmação), porque o `.m4a` só é legível depois de fechado.
- **Eco sem fone.** Com o alto-falante ligado, o microfone capta a voz dos outros. O cancelamento de eco remove esse som na captura (medido com voz sintética; falta uma chamada real). Com ele desligado, ou com um fone Bluetooth que não o suporte, a fala do outro lado pode sair duplicada e atribuída a você; nesse caso, use fone com fio ou corrija na janela de correção. O cancelamento também deixa o canal do sistema cerca de 7,6 dB mais baixo.
- **Diarização com 3 ou mais vozes é marcada como experimental pelo provedor.** Duas pessoas falando pelo mesmo dispositivo aparecem como uma voz só.

## Provedores

A transcrição, a classificação e o resumo usam provedores escolhidos no mesmo `.env` (`TRANSCRIBER`, `TRANSCRIBER_MODEL`, `MINUTER`, `MINUTER_MODEL`). Hoje existem `gemini` e `claude`. Um provedor novo exige um adaptador no código e um teste com a reunião sintética ([ADR 0012](docs/decisions/0012-env-file-and-provider-seams.md)).

## Privacidade

O áudio das reuniões é enviado ao Google, e o texto, à Anthropic. O app não envia nada para armazenamento na nuvem; o áudio fica na pasta de atas, e a sincronização dessa pasta (se houver) é escolha sua. As chaves ficam em texto puro no `.env`; mantenha o arquivo só neste Mac. Na camada gratuita da API do Google, o conteúdo pode ser usado para melhorar produtos do Google, e revisores humanos podem lê-lo; use a camada paga para reuniões reais. Avise os participantes de que a reunião será gravada.

## Desenvolvimento

```bash
swift test                                   # testes unitários
./scripts/build-app.sh                       # compila e monta build/Minuta.app
python3 tools/synthetic-meeting/build.py --all  # gera o áudio sintético de teste (oito cenários)
build/Minuta.app/Contents/MacOS/Minuta --process <pasta> --out <pasta> [--model <modelo>|all]
```

open -n -a Minuta --args --capture-test <relatório.json> [--aec on|off] [--seconds N]
```

`--process` roda transcrição, classificação e resumo sobre `mic.m4a` e `system.m4a` de uma pasta, usando as chaves do `.env`, sem alterar a pasta configurada no app. Gera o modelo sugerido (Geral, sem sugestão), ou o modelo pedido, ou todos com `all`. `--capture-test` grava os dois canais e mede o nível de cada um e quanto da chamada vaza para o microfone, com ou sem cancelamento de eco.

Estrutura:
- `Sources/Minuta/`: o app, um arquivo por responsabilidade (lista por camada em [`AGENTS.md`](AGENTS.md#convenções-de-código)).
- `Tests/MinutaTests/`: testes.
- `scripts/`: instalação, assinatura local e ícone.
- `tools/synthetic-meeting/`: gerador de áudio de teste, com oito cenários (`scenarios/`), gabaritos e amostras.
- `docs/`: brief original, [plano de validação](docs/validation-plan.md) e [decisões](docs/decisions/README.md), com o índice e a situação de cada uma.

## Estado

- **Validado com áudio sintético** (oito reuniões de 3 a 4 minutos, com 2 a 4 vozes): transcrição com cerca de 1% de diferença e 28 de 28 falas do sistema com o falante certo na reunião original; a classificação acertou o modelo esperado nos oito cenários, inclusive o caso vago (sem sugestão) e o sem nomes. Detalhes em [`docs/validation-plan.md`](docs/validation-plan.md).
- **Áudio único com diarização de todas as vozes**, testado nos mesmos cenários como alternativa aos dois canais, juntou a voz do usuário com a de outra pessoa em 3 de 8; com dois canais, a atribuição ficou entre 98% e 100% ([ADR 0024](docs/decisions/0024-follow-market-practice-for-capture.md)).
- **Validado pelo usuário:** captura do áudio do sistema, gravação com microfone, pausa e continuação, gravação de teste de fone, apagar uma ata, e as chips de modelo e a janela de atas.
- **Pendente:** chamada real com alto-falante e cancelamento de eco, voz real com 3 ou mais participantes, gravação longa (consumo e estabilidade) e termos de dados dos provedores.

O histórico do trabalho e os próximos passos estão em [`STATUS.md`](STATUS.md).

## 🤖 Governança de IA

As regras do projeto para qualquer ferramenta de IA ficam em [`AGENTS.md`](AGENTS.md), com o padrão de escrita em `.agents/STYLE.md` e o estado do trabalho em [`STATUS.md`](STATUS.md). `CLAUDE.md` e `GEMINI.md` só apontam para o `AGENTS.md`.
