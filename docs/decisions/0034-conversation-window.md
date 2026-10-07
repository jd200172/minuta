# 0034. Janela da conversa no estilo de app de mensagens

Status: aceita; implementada
Data: 2026-10-05
Substitui: a visão de conversa dentro da leitura e as cores dos balões do `docs/decisions/0033-conversation-view-and-system-colors.md`. As cores do sistema no resto da interface continuam.

## Contexto

O ADR 0033 pôs a conversa em balões como alternância da seção Transcrição, na janela de leitura. O usuário pediu que o botão abra uma janela própria, só com a conversa, e que o diálogo copie a forma do WhatsApp.

## Decisão

Decisão: o botão de conversa da leitura (`minuta://conversation`) abre uma quinta janela, só de leitura, com a transcrição em balões. Motivo: a conversa ocupa uma janela inteira sem disputar espaço com o resumo e o resto da ata.

- **Janela.** Uma por arquivo de ata; um segundo clique traz a existente para a frente. Título "Conversa · título da ata". Fecha com ⌘W e Esc. Abre com 520 × 720 px. Não toca áudio, não edita e não tem balão de citação; a correção continua na janela do ADR 0025.
- **Fonte.** A página é montada a partir do Markdown (`ConversationHTML`), então os nomes que o usuário deu aos participantes aparecem. É refeita em `.ataChanged`, inclusive depois de correção, troca de falante e refazer a transcrição.
- **Balões.** A pessoa que gravou (campo "Seu nome") fica à direita, em verde, sem nome. Cada outro falante fica à esquerda, em branco (claro) ou cinza-escuro (escuro), com o nome em cor própria no primeiro balão do turno. Seis cores, atribuídas pela ordem de aparição; passando de seis, repetem. A cauda e o canto reto aparecem só no primeiro balão do turno. Largura máxima de 78%.
- **Horário.** Dentro do balão, embaixo à direita: início da reunião mais o deslocamento do segmento, em `HH:mm`. Sem `inicio` válido, mostra o tempo da reunião (`mm:ss`). Um chip com a data abre cada dia; reunião que cruza a meia-noite tem mais de um.
- **Fundo.** Bege no claro e quase preto no escuro, fixos, como no app de referência. Segue o modo claro ou escuro da janela.
- **Leitura.** A transcrição volta a ser só texto (ADR 0032). O botão deixa de ser uma alternância: sai `aria-pressed`, o estado "ligado" e a preferência `conversationView`.

## Alternativas descartadas

- Alternar a transcrição dentro da leitura (ADR 0033): disputa espaço com o resumo e obriga a rolar até a seção.
- Cor de destaque do sistema nos balões: não distingue vários falantes e não tem a aparência pedida.

## Consequências

- Quinta janela do app, com `AGENTS.md` atualizado.
- Desvio das HIG: verde, cores por falante e fundo próprios. Os balões de dica (ADR 0017) e de citação (ADR 0019) mantêm a linguagem do `Balloon`; a janela de conversa tem a sua. A regra "os balões têm uma só linguagem visual" passa a valer só para dicas e citações.
- Se "Seu nome" mudar depois da gravação, os balões da pessoa antiga ficam à esquerda, com nome.
- A janela guarda o caminho do arquivo; se a ata for renomeada com a janela aberta, ela deixa de atualizar até ser aberta de novo.
- Sem teste visual no app.
