# 0033. Visão de conversa e cores do sistema

Status: aceita; a visão de conversa e as cores dos balões foram substituídas pelo ADR 0034; as cores do sistema continuam
Data: 2026-10-05
Substitui: a regra de cor monocromática do `docs/decisions/0029-reading-typography-hierarchy.md`. A tipografia, a coluna e os tons de fundo daquele ADR continuam, agora derivados das cores do sistema.
Complementa: `docs/decisions/0032-transcript-turns.md`.

## Contexto

O usuário pediu ver a transcrição como uma conversa, com balões. Os balões precisam de cor para distinguir quem fala. Com a leitura monocromática (ADR 0029), a interface e os balões seguiriam linguagens diferentes. O usuário decidiu abandonar o tom monocromático e usar as cores padrão do sistema.

## Decisão

Decisão: um quarto ícone no grupo de exportação da leitura alterna a transcrição entre texto (ADR 0032) e conversa. Motivo: é uma forma de ler, no mesmo lugar dos outros controles da ata.

- **Conversa.** Cada segmento é um balão. Os balões da pessoa que gravou (o nome do campo "Seu nome") ficam à direita, preenchidos com a cor de destaque do sistema e texto sobre ela; os dos outros ficam à esquerda, em cinza do sistema. O nome e o horário aparecem uma vez por turno, acima do primeiro balão. O horário de cada balão fica no balão de dica.
- **Ícone.** `minuta://view/conversation`, com `aria-pressed`. Ligado, usa a cor de destaque. A escolha vale para todas as janelas e fica em `UserDefaults` (`conversationView`). Ao alternar, a página rola até a seção Transcrição.
- **Exportação.** HTML e PDF continuam com a transcrição em texto.
- **Cores.** Chips de seção, links, chips de horário (página, balão de citação e janela de correção) e a linha selecionada usam a cor de destaque do sistema (`AccentColor` no CSS, com `-apple-system-control-accent` e `LinkText` como alternativas; `Color.accentColor` no SwiftUI). A chip da seção atual é preenchida com a cor de destaque. Voltam as cores de estado: laranja no aviso de resumo desatualizado e em "Sem resumo", verde em "Corrigida", ponto de cor por modelo na lista de atas, vermelho nos erros.
- **Tons.** O texto, o painel e o cabeçalho deixam de usar valores fixos: o painel é `Canvas`, o cabeçalho é `Canvas` com 4% de `CanvasText`, o corpo é `CanvasText` a 86%. O off-white quente do ADR 0029 sai.

## Alternativas descartadas

- Janela própria para a conversa: duplica a leitura e a lista de citações.
- Balões em cinza, sem cor de destaque: não distinguem quem fala de relance e mantêm a divergência com o resto da interface.

## Consequências

- A visão de conversa é um desvio das HIG (balões próprios), a registrar entre os desvios vigentes do `AGENTS.md`.
- Contraste do texto sobre a cor de destaque depende da cor escolhida no sistema; o CSS usa `AccentColorText` quando existe.
- Se o campo "Seu nome" mudar depois da gravação, os balões da pessoa antiga ficam à esquerda.
- Sem teste visual no app.
