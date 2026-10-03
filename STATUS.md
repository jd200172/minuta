# Status

Atualizado em: 2026-10-02

## Em andamento

Trabalho não commitado desde `ba93980` (ADRs 0019 e 0021 a 0025, e esta revisão dos documentos). 88 testes passam. App instalado em `/Applications/Minuta.app`.

### Estado do app por área

- **Barra de menus** (ADRs 0011, 0014 e 0015): ícone de microfone fixo, estado pelo fundo do botão (verde gravando, vermelho pausado, amarelo processando); menu com Iniciar gravação, Atas…, Configurações… e Sair.
- **Gravação** (ADRs 0010 e 0013): pausar, continuar e encerrar, contador, lembrete de pausa, confirmação ao sair gravando, limite de 30 minutos de tempo gravado.
- **Captura** (ADRs 0023 e 0024): dois canais, o canal define o falante, diarização só no canal do sistema. O microfone passa pelo cancelamento de eco do macOS, ligado por padrão, com opção em Preferências.
- **Transcrição, classificação e resumo** (ADRs 0002, 0008, 0012, 0017 e 0018): Gemini 3.5 Transcribe; Claude Sonnet 5.5 sugere um de quatro modelos (Decisão, Problemas e ideias, Informativa, Geral) e o título, e gera o resumo sugerido. Todos os resumos ficam no `.resumos.json`; o escolhido é copiado no `.md`.
- **Áudio** (ADR 0022): depois da ata criada, os dois arquivos vão para a pasta de atas das configurações (antes: Application Support; o que sobrou lá é movido na inicialização) com o radical do secundário e seguem a ata para a Lixeira. Atas anteriores não têm áudio.
- **Janela de atas** (ADR 0015): tabela no estilo do Finder, com menu de contexto, gravações em andamento como linhas e verificação da pasta.
- **Janela de leitura** (ADRs 0015 a 0019 e 0026): todas as seções colapsáveis (estado por reunião); botão "Refazer a transcrição", ativo só com áudio guardado; card centralizado, chips de modelo, lápis no título e nos participantes, transcrição colapsável lembrada por reunião, balão de citação com o trecho e um segmento de cada lado. Todos os balões e dicas usam `BalloonPanel` com a mesma forma das chips.
- **Janela de correção** (ADR 0025): toca o áudio a partir de cada fala, edita o texto, troca o falante, apaga e restaura; correções marcam os resumos como desatualizados, com aviso nas duas janelas.
- **Configurações** (ADRs 0011, 0012 e 0023): página única com chaves e modelos, permissões com teste de captura, preferências e a versão no rodapé.

### Verificado

- Pelo usuário: captura do áudio do sistema, gravação com microfone, pausa e continuação, gravação de teste de fone, apagar uma ata, desenho das chips e da janela de atas.
- No app instalado, por capturas de tela e eventos enviados ao processo: estados do botão, janela de atas (ordenar, menu de contexto, Return, Esc, ⌘O, ⌘W, duplo clique, ⌘⌫), leitura com links, faixa de pasta ausente, renomear e desfazer, trocar e refazer resumo, chips com balão, recolher e expandir a transcrição, balão de citação (dentro do card, sem rolagem, segundo clique fecha, salto ao horário).
- Janela de correção, com uma ata de teste feita do cenário sintético 8 e com áudio (depois mandada para a Lixeira): reprodução, destaque, espaço, edição por clique real, troca de falante, restaurar e o aviso na página de leitura.
- Com chaves reais: os oito cenários sintéticos pelo `--process`, com a classificação correta em todos (plano de validação, teste 8).
- Cancelamento de eco medido com voz tocando no alto-falante: microfone de -33,5 dB para -72,3 dB, correlação com a chamada de 0,95 para 0,29 (ADR 0023).

### Sem teste manual

- Seções colapsáveis e "Refazer a transcrição" (ADR 0026): só testes unitários (substituição do secundário, estado das seções, HTML); falta ver no app e chamar o STT de verdade.

- Chamada real com alto-falante e cancelamento de eco ligado: a fala do usuário e o efeito com fone Bluetooth (ADR 0023).
- Gravação real passando pela guarda do áudio, e falha ao mover o áudio.
- "Refazer resumo" pela janela de correção (usa o mesmo caminho do ícone de refazer, já verificado).
- Janela de atas: linhas de gravação em andamento (só teste unitário), Tentar de novo, Descartar…, gerar um modelo novo pelo submenu Resumo, a leitura acompanhando um renomear feito na lista, ata com problema, botões da faixa de pasta ausente.
- Falha de rede na geração automática do resumo; secundário apagado ou ilegível.
- Renomear com rolagem ou redimensionamento; nomes inferidos no app; atas muito longas; balão de citação ao rolar a página.
- Configurações: Permitir, Testar captura, Escolher… e Abrir ao iniciar o Mac.
- Barra de menus clara, outros papéis de parede e VoiceOver.
- Uma ata antiga com `modelo: acompanhamento` (linha de aviso na leitura; só teste unitário).

### Limites conhecidos

- O cabeçalho da `Table` é desenhado pelo SwiftUI e não aceita ajuste pelo AppKit; mudar exige `NSTableView`. A `Table` do macOS 13 também não oferece clicar de novo para renomear, Quick Look nem reordenar colunas.
- O `--process` grava `duracao_segundos: 0`.
- Nome do usuário com espaço no fim aparece com o espaço na lista de participantes.
- No cenário 6, a diarização juntou duas vozes femininas em turnos seguidos num segmento, e uma ação saiu com a pessoa errada (limite da transcrição).
- A camada gratuita do Google recusa o terceiro pedido por minuto; cada reunião usa dois.
- Com o cancelamento de eco, o canal do sistema fica cerca de 7,6 dB mais baixo (o macOS abaixa o som dos outros apps).

## Descobertas
<!-- fato aprendido durante o trabalho que muda o próximo passo -->
- Reunião real de 2026-10-01 (alto-falante, sem cancelamento de eco): 17 falas da outra pessoa saíram duplicadas no microfone, sempre depois da original (mediana 0,4 s) e atribuídas ao usuário. A ata fica como está, como referência para comparar a qualidade futura.
- Áudio único com diarização de todas as vozes, nos oito cenários sintéticos: em 3 de 8 a voz do usuário foi juntada à de outra pessoa (75%, 94% e 62% das palavras com o falante certo); só o canal do sistema deu 98% a 100% (ADR 0024).
- Comparação dos cinco modelos nos cenários 01 a 05: o modelo errado impõe estrutura sem evidência. Com a regra de seção vazia, melhorou, mas o Decisão de 02 e 05 ainda preenche "decisões" sem decisão do grupo (ADR 0018).
- Gemini 3.5 Transcribe: limite de 30 minutos por pedido com diarização (ADR 0010); atribuição com 3 ou mais falantes marcada como experimental; `custom_vocabulary` não combina com diarização nem com timestamps.
- A camada gratuita do Google usa o conteúdo para melhorar produtos, e revisores humanos podem lê-lo. Reuniões reais exigem a camada paga.
- Claude não aceita áudio na API; a transcrição exige provedor separado.
- O processamento de voz do `AVAudioEngine` pode entregar vários canais; o primeiro é o microfone processado.
- A identidade de assinatura "Minuta Dev" (`scripts/setup-signing.sh`) mantém as permissões do macOS entre builds; a assinatura ad hoc não.
- Este Mac é um Mac mini sem microfone embutido; sem entrada de áudio, o app grava só o sistema e avisa.
- `WKWebView`: campo nativo por cima fica transparente sem uma `NSView` opaca embaixo; com JavaScript da página desligado, `evaluateJavaScript` chamado pelo app ainda funciona e serve para medir a posição de elementos. Com base `about:blank`, o fragmento da URL precisa ser comparado como texto.
- `AppleScript` `click at` faz um clique de acessibilidade e não põe o foco num campo de texto; para testar edição é preciso evento de mouse real (`CGEvent`).
- Um app Swift em repouso usa cerca de 79 MB de RSS e 0% de CPU.

## Descartado
<!-- hipótese ou abordagem descartada e o motivo -->
- Filtro de eco pelo texto (ADR 0021), seção "Eco do microfone" e corte do microfone por detecção de fala: soluções próprias, sem referência de mercado; o filtro erra nos dois sentidos sem que o erro apareça (ADR 0024).
- Áudio único com diarização: pior atribuição nos cenários sintéticos (ADR 0024).
- Envio da ata por e-mail (Mail.app por AppleScript): desenhado e implementado, descartado a pedido do usuário.
- Consulta ao saldo das APIs no app: fora do escopo, a pedido do usuário.
- Modelo Acompanhamento e Informativa ampla (ADR 0018). Estrutura única adaptativa sem seletor: o usuário manteve três tipos próprios mais o Geral.
- Keychain para as chaves: aviso de autorização a cada build com assinatura diferente (ADR 0012).
- Python com `pystray`, `pyobjc` e `customtkinter` (ADR 0009). Notion e Supabase como destino (ADR 0001). LLM multimodal único (ADR 0002). Mixagem em mono (ADR 0004). "Outros" como bloco único (ADR 0006).
- Banco de dados ou pasta interna para as atas; submenu por ata no menu (ADR 0015). Botões nas linhas da lista de atas e ícone no título.
- Folha única com todos os participantes; anotações "(canal do microfone)" e "nome informado por você" (ADR 0016).
- Controle de modelos nativo ou menu pop-up na leitura (ADR 0017). `NSPopover` como balão de dica: trocado pelo `BalloonPanel`, com a forma das chips.
- Barra de rolagem no balão de citação: o balão cresce em altura antes de largura, e as falas vizinhas são cortadas.

## Próximos
- Gravar uma chamada real com alto-falante e o cancelamento ligado; conferir duplicatas, a fala do usuário e o nível do canal do sistema. Só um resultado ruim reabre o ADR 0024.
- Gravar uma reunião real com 3 ou mais participantes e conferir transcrição, diarização, classificação e resumo (teste 6).
- Comando para refazer a transcrição de uma ata a partir do áudio guardado.
- Conferir os `expected.md` dos oito cenários contra os resumos e ajustar os blocos dos modelos; rodar 06 a 08 com os quatro modelos.
- Avaliar se Decisão em reunião sem decisão deve ser bloqueada ou só avisada (ADR 0018).
- Medir custo em tokens e tempo por reunião; comparar esforço `medium` com `high`.
- Migrar a chave do Google para a camada paga e ler os termos de dados do Google e da Anthropic (teste 7).
- Confirmar o limite de 30 minutos (ADR 0010) e o público do projeto.
- Conferir nas fontes primárias as citações de Tropman, Romano e Nunamaker e Monge (ADR 0017).
- Pendências da revisão de HIG: reticências em "Abrir arquivo…" e "Gravando 5 s…", um só botão de destaque em Permissões, "Configurações" ou "Ajustes" e a grafia do nome do app.
- Opcionais, se o uso pedir: reconstruir o secundário a partir do `.md`; cópia interna das atas com restauração (detecta ata apagada); dividir e juntar falas e desfazer na janela de correção (ADR 0025).

## Bloqueado
- Nada.
