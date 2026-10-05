# Status

Atualizado em: 2026-10-05

## Em andamento

ADR 0027 implementado (menu de modelo, chips de seção, exportação em HTML e PDF). O HTML exportado tem seções colapsáveis e fechadas. Chips de seção de cor única, espaçamento Moderado e janela de 964 px com tamanho lembrado, commitados. Cabeçalho reorganizado (ícones junto da data, modelo em linha própria, sem a justificativa da sugestão). 93 testes passam. O app instalado em `/Applications/Minuta.app` está sem os ADRs 0026 e 0027; `./scripts/install.sh` instala a versão atual.

### Estado do app por área

- **Barra de menus** (ADRs 0011, 0014 e 0015): ícone de microfone fixo, estado pelo fundo do botão (verde gravando, vermelho pausado, amarelo processando); menu com Iniciar gravação, Atas…, Configurações… e Sair.
- **Gravação** (ADRs 0010 e 0013): pausar, continuar e encerrar, contador, lembrete de pausa, confirmação ao sair gravando, limite de 30 minutos de tempo gravado.
- **Captura** (ADRs 0023 e 0024): dois canais, o canal define o falante, diarização só no canal do sistema. O microfone passa pelo cancelamento de eco do macOS, ligado por padrão, com opção em Preferências.
- **Transcrição, classificação e resumo** (ADRs 0002, 0008, 0012, 0017 e 0018): Gemini 3.5 Transcribe; Claude Sonnet 5.5 sugere um de quatro modelos (Decisão, Problemas e ideias, Informativa, Geral) e o título, e gera o resumo sugerido. Todos os resumos ficam no `.resumos.json`; o escolhido é copiado no `.md`.
- **Áudio** (ADR 0022): depois da ata criada, os dois arquivos vão para a pasta de atas das configurações (antes: Application Support; o que sobrou lá é movido na inicialização) com o radical do secundário e seguem a ata para a Lixeira. Atas anteriores não têm áudio.
- **Janela de atas** (ADR 0015): tabela no estilo do Finder, com menu de contexto, gravações em andamento como linhas e verificação da pasta.
- **Janela de leitura** (ADRs 0015 a 0019, 0026 e 0027): cabeçalho fixo sobre um painel de texto contínuo (o chip rola até a seção e o chip da seção no topo fica preenchido); botão "Refazer a transcrição", ativo só com áudio guardado; janela sem moldura, margem de 32 px e coluna de até 900 px sempre centralizada, com o cabeçalho na mesma coluna. Cabeçalho em blocos: título; data com os botões de e-mail (inativo), HTML e PDF logo abaixo, à esquerda; botão "Modelo" com menu nativo dos modelos e "Refazer este resumo"; linha de estado só quando há aviso; chips de seção, todas do mesmo estilo, que rolam até a seção. Espaçamento no nível "Moderado" (card 28 × 36 px, entrelinha 1,65). A janela abre com 964 × 780 px e lembra o tamanho. Lápis no título e nos participantes, transcrição colapsável lembrada por reunião, balão de citação com o trecho e um segmento de cada lado. Todos os balões e dicas usam `BalloonPanel`, com a forma das antigas chips de modelo.
- **Janela de correção** (ADR 0025): toca o áudio a partir de cada fala, edita o texto, troca o falante, apaga e restaura; correções marcam os resumos como desatualizados, com aviso nas duas janelas.
- **Configurações** (ADRs 0011, 0012, 0023 e 0028): página única com chaves e modelos, permissões com teste de captura, preferências (inclui Aparência: Sistema, Claro ou Escuro) e a versão no rodapé.
- **Padrão de escrita** (`.agents/STYLE.md`, `.agents/GLOSSARY.md`): em "Ajustes deste projeto", frase de procedimento até 20 palavras, descritiva até 25, parágrafo até 6 frases, formato "Decisão: X. Motivo: Y." e lista de palavras vagas. O glossário tem 16 termos, confirmados pelo usuário. O `AGENTS.md` foi revisado contra as regras; ADRs 0001 a 0025 ficam como estão, e as regras valem para ADRs novos.

### Verificado

- Pelo usuário: captura do áudio do sistema, gravação com microfone, pausa e continuação, gravação de teste de fone, apagar uma ata, desenho das chips e da janela de atas.
- No app instalado, por capturas de tela e eventos enviados ao processo: estados do botão, janela de atas (ordenar, menu de contexto, Return, Esc, ⌘O, ⌘W, duplo clique, ⌘⌫), leitura com links, faixa de pasta ausente, renomear e desfazer, trocar e refazer resumo, chips com balão, recolher e expandir a transcrição, balão de citação (dentro do card, sem rolagem, segundo clique fecha, salto ao horário).
- Janela de correção, com uma ata de teste feita do cenário sintético 8 e com áudio (depois mandada para a Lixeira): reprodução, destaque, espaço, edição por clique real, troca de falante, restaurar e o aviso na página de leitura.
- Com chaves reais: os oito cenários sintéticos pelo `--process`, com a classificação correta em todos (plano de validação, teste 8).
- Cancelamento de eco medido com voz tocando no alto-falante: microfone de -33,5 dB para -72,3 dB, correlação com a chamada de 0,95 para 0,29 (ADR 0023).

### Sem teste manual

- Segmentação por pausa e duração (ADR 0030): testes unitários e uma reunião real de 17 min pelo `--process` (136 para 78 segmentos); falta decidir se `pauseLimit` (3,0 s) sobe para 4 a 5 s.

- Tipografia e cor da leitura (ADR 0029, revisado): título 28 px, chips e títulos de seção em 15 px, app monocromático (cor só em erro e no botão da barra de menus); falta ver no app a altura do cabeçalho e a quebra das chips em janela estreita.

- Aparência (ADR 0028): compila; falta ver no app o seletor, as janelas, a leitura e o ícone da barra de menus nos três modos.

- Menu de modelo, chips de seção e exportação (ADR 0027): testes unitários do HTML; página renderizada pela WebKit fora do app nos modos claro e escuro; PDF de uma ata real gerado por script com o mesmo caminho do `PDFExport` (14 páginas A4 com texto). Falta no app: posição do menu, troca e refazer pelo menu, salto com seção recolhida, painel de salvar e o PDF pelo próprio app.
- "Refazer a transcrição" (ADR 0026): só testes unitários (substituição do secundário, HTML); falta ver no app e chamar o STT de verdade.

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
- Revisão do `AGENTS.md` e dos ADRs contra as regras novas (2026-10-03): 34 de 193 frases do `AGENTS.md` e cerca de 135 de 800 dos ADRs passavam de 25 palavras. O script de contagem junta frases separadas por título em negrito e por item de lista; os números são limite superior.

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
- Seções colapsáveis e transcrição colapsável na leitura (ADRs 0019 e 0026): trocadas por cabeçalho fixo e painel de texto contínuo (ADR 0027). Rolagem da página inteira com o cabeçalho que some: o usuário pediu o cabeçalho fixo. Uma seção por vez, trocada pelo chip: implementada e substituída pelo texto contínuo a pedido do usuário.
- Chips de seção em três grupos de cores diferentes e traços verticais (ADR 0027): o usuário não entendeu a diferença de cor. Faixa fixa, índice lateral e controles na barra da janela para o cabeçalho que some ao rolar: descartados, fica a estrutura atual. Respiro Generoso (card 36 × 48 px): custa cerca de 35% de altura.
- Chips de modelo de resumo na leitura (ADR 0017): o usuário as lia como assuntos da ata; trocadas por menu de modelo (ADR 0027). Rótulo "Formato" dos mockups trocado por "Modelo", o termo do glossário. Controle de segmentos, frase de estado, controle na barra da janela, cartões por modelo, chips só das seções do modelo e rótulo "Ir para" (ADR 0027). `NSPopover` como balão de dica: trocado pelo `BalloonPanel`, com a forma das chips.
- Barra de rolagem no balão de citação: o balão cresce em altura antes de largura, e as falas vizinhas são cortadas.
- Reescrever os ADRs 0001 a 0025 pelas regras novas: são registro de decisão já aprovado, e a reescrita pode mudar o sentido. Decisão do usuário (2026-10-03).
- Levar limites de frase e palavras vagas para a skill `project-governance` e para a fonte global agora: sem validação fora do Minuta. Só o procedimento do glossário entrou na skill (versão 3.4.0).

## Próximos
- Testar no app o painel de texto contínuo: clicar nos chips, rolar com roda, teclado e barra e ver o chip da seção atual mudar, horário de citação que leva à Transcrição, trocar de modelo estando em outra seção e janela estreita. Salto por âncora e leitura da seção no topo foram verificados numa `WKWebView` à parte.
- Instalar e testar o ADR 0027 no app: menu de modelo, chips de seção com seção recolhida, salvar HTML e PDF. Conferir com o usuário se a confusão das chips acabou.
- Planejar o envio por e-mail (próxima etapa, ADR próprio); o botão já está na leitura, inativo.
- Gravar uma chamada real com alto-falante e o cancelamento ligado; conferir duplicatas, a fala do usuário e o nível do canal do sistema. Só um resultado ruim reabre o ADR 0024.
- Gravar uma reunião real com 3 ou mais participantes e conferir transcrição, diarização, classificação e resumo (teste 6).
- Conferir os `expected.md` dos oito cenários contra os resumos e ajustar os blocos dos modelos; rodar 06 a 08 com os quatro modelos.
- Avaliar se Decisão em reunião sem decisão deve ser bloqueada ou só avisada (ADR 0018).
- Medir custo em tokens e tempo por reunião; comparar esforço `medium` com `high`.
- Migrar a chave do Google para a camada paga e ler os termos de dados do Google e da Anthropic (teste 7).
- Confirmar o limite de 30 minutos (ADR 0010) e o público do projeto.
- Conferir nas fontes primárias as citações de Tropman, Romano e Nunamaker e Monge (ADR 0017).
- Pendências da revisão de HIG: reticências em "Abrir arquivo…" e "Gravando 5 s…", um só botão de destaque em Permissões, "Configurações" ou "Ajustes" e a grafia do nome do app.
- Usar o padrão de escrita e o glossário em outro projeto. Se as regras de limites e palavras vagas se mostrarem úteis, promovê-las para `~/.agents/AGENTS.md` (exige autorização explícita).
- Decidir se a diretriz de sincronização da skill `project-governance` (Etapa 6) trata o glossário como o `STYLE.md`: entrada nova como rascunho até a confirmação.
- Incluir `.agents/GLOSSARY.md` na linha de governança de projetos de `~/.agents/AGENTS.md`.
- Opcionais, se o uso pedir: reconstruir o secundário a partir do `.md`; cópia interna das atas com restauração (detecta ata apagada); dividir e juntar falas e desfazer na janela de correção (ADR 0025).

## Bloqueado
- Nada.
