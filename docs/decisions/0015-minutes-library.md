# 0015. Janela de atas, leitura em página e nome do arquivo com título

Status: aceita; implementada
Data: 2026-10-01
Complementa: `docs/decisions/0001-local-markdown-destination.md` e `docs/decisions/0011-minimal-menu-and-install.md`.

## Contexto

As atas ficavam numa pasta aberta pelo Finder. O menu tinha "Abrir pasta de atas", e não havia como listar, ler com formatação ou apagar uma ata pelo app. Preocupações do usuário: a pasta é uma solução frágil se alguém a apagar, e a ata é a única cópia da transcrição, porque o áudio é descartado.

## Decisão

**Os arquivos `.md` continuam sendo a fonte da verdade (ADR 0001).** O app não tem banco de dados nem índice: a lista é refeita lendo a pasta de saída. Edições, renomeações e movimentos feitos no Finder aparecem na lista. A proteção contra perda vem da Lixeira e do backup da pasta (hoje, o OneDrive), não de mover os dados para dentro do app.

**Janela "Atas…".** Substitui "Abrir pasta de atas". Lista ordenada pela data da reunião, da mais recente para a mais antiga, e depois pelo título. Cada ata tem a data, o título, a duração e os botões Abrir e Apagar. No topo, a seção "Em andamento" mostra as gravações pendentes: em processamento (spinner e etapa), com falha (causa e botões Tentar de novo e Descartar) ou interrompidas. Sem atas e sem pendentes, um texto convida a gravar.

**Tabela de atas no estilo do Finder (atualização de 2026-10-01).** A lista é uma `Table` do SwiftUI (`NSTableView` por baixo), com cabeçalhos e ordenação por clique: Data (padrão: mais recente primeiro), Título, Resumo e Duração. A ordem escolhida vale só durante a execução do app. Não há botões nas linhas: toda ação está no menu de contexto.
- **Linhas:** as gravações em andamento são linhas da própria tabela, em ordem de data. Sem ícone no título: todas as linhas são do mesmo tipo, então o ícone não informa nada, e o problema de um arquivo já aparece em vermelho na coluna Resumo. Data em forma relativa ("Hoje às 15:57", "Ontem às 09:06", "28 de set. de 2026 às 16:30"). A coluna Resumo mostra um ponto colorido e o nome do modelo, ou "Sem resumo", "Gerando resumo…", o motivo do problema do arquivo, ou o estado da gravação ("Transcrevendo…", "Falhou: …").
- **Teclado:** Return renomeia, como no Finder; duplo clique, ⌘O e ⌘↓ abrem; ⌘⌫ move para a Lixeira. A tabela chama a mesma ação principal para o duplo clique e para Return; o app distingue pelo evento corrente.
- **Menu de contexto de uma ata:** Abrir, Mostrar no Finder, Resumo ▸ (os quatro modelos, com visto no exibido e "(sugerido)" no sugerido; escolher um mostra o resumo, gerando-o antes se não existe), Mover para a Lixeira e Renomear. Resumo e Renomear ficam desabilitados enquanto o resumo é gerado; Abrir, Resumo e Renomear, em arquivo com problema; Resumo não aparece em ata anterior ao ADR 0017.
- **Menu de uma gravação em andamento:** Tentar de novo (desabilitado enquanto processa) e Descartar…
- **Renomear no lugar:** o campo substitui o título na linha. Return ou clicar fora salva, Esc cancela, até 120 caracteres, título vazio volta ao nome só com o horário. Vale também para atas anteriores ao ADR 0017: nelas só a linha `# Título` e o nome do arquivo mudam. Uma janela de leitura aberta acompanha o novo nome.
- **Lixeira sem confirmação,** como o Finder: ela é reversível. "Descartar…" de uma gravação continua pedindo confirmação, porque apaga de vez. Isso substitui a confirmação do item "Apagar" descrito acima.
- Fora do que a `Table` do macOS 13 permite: clicar de novo no nome para renomear, Quick Look e reordenar colunas.

**Menu da barra.** Entre os comandos de gravação e Configurações: "Atas…". A seção "Atas recentes" (as 5 últimas) foi retirada em 2026-10-02, a pedido do usuário.

**Leitura.** "Abrir" mostra a ata numa janela própria, como página: título, data e duração, seções, tabela de ações, horários como links para o trecho da transcrição (o trecho fica destacado) e botão "Mostrar no Finder". O Markdown é convertido em HTML por um conversor mínimo, que só entende o formato que o `MinutesRenderer` escreve. Todo texto é escapado, e a `WKWebView` roda sem JavaScript, com política de conteúdo restrita e sem navegação além dos âncoras do próprio documento.

**Apagar.** Pede confirmação e move o arquivo para a Lixeira do macOS. Descartar uma gravação pendente também pede confirmação, mas apaga de vez, porque o áudio ou a transcrição não têm outra cópia.

**Nome do arquivo.** `AAAA-MM-DD HHmm Título.md`. O título é higienizado (caracteres reservados saem, `:` vira ` -`, no máximo 80 caracteres), e um nome repetido recebe ` (2)`, ` (3)`. Atas antigas mantêm o nome. A lista mostra o título que está dentro do arquivo (a primeira linha `# `), e usa o do nome só quando o conteúdo não pode ser lido. A data vem do nome, do frontmatter ou da modificação do arquivo, nessa ordem. Arquivos `.md` sem nome de ata e sem `inicio` no frontmatter são ignorados.

**Verificação da pasta (atualização de 2026-10-01).** A cada leitura da pasta o app confere o que dá para ver:
- Pasta ausente: faixa no topo da janela com "Escolher outra pasta…" e "Recriar pasta". Só avisa se a pasta já foi vista antes (o app guarda o último caminho visto, em `seenOutputDir`); uma pasta nunca criada, como na primeira execução ou logo após escolher outra, não gera aviso.
- Pasta ilegível: a mesma faixa, com "Escolher outra pasta…" e "Tentar de novo".
- Arquivo com nome de ata e problema: marcado na lista, na ordem de data, com o nome do arquivo no lugar do título e o motivo: "Arquivo vazio", "Não foi possível ler" (não abre, ou não é UTF-8) ou "Sem cabeçalho de ata" (sem `inicio` nem título; ainda abre). Os dois primeiros oferecem "Mostrar no Finder", e todos oferecem a Lixeira.
- Arquivos `.md` sem nome de ata e sem `inicio` no frontmatter continuam ignorados.
- Fora do alcance: uma ata apagada. O app não guarda o que já existiu, então não vê o que sumiu. Uma cópia interna com restauração (nível C da discussão) ficou para depois.

**Sem fala suficiente.** Uma transcrição com menos de 10 palavras não gera ata: o app não chama o Claude, não grava arquivo, descarta a gravação e mostra um aviso.

## Consequências

- Cada atualização da lista lê as primeiras linhas de cada `.md`. Numa pasta sincronizada pelo OneDrive isso pode baixar os arquivos que estiverem só na nuvem. São arquivos pequenos.
- A `WKWebView` cria um processo extra enquanto uma janela de leitura está aberta.
- O aviso de "gravação sem processar" ao abrir o app continua, e repete o que a seção "Em andamento" mostra.
- Quem edita o título dentro do arquivo vê o novo título na lista, e o nome do arquivo fica desatualizado.
- Renomear o título pelo app e buscar por texto ficam para uma etapa posterior.

## Alternativas descartadas

- Banco de dados ou pasta interna do app: mais difícil de ver e de fazer backup, duas fontes da verdade, e perde a vantagem do Markdown legível por qualquer programa.
- Um submenu por ata no menu da barra: o menu cresce a cada reunião.
- Apagar de vez: um clique errado perde a única cópia da transcrição.
- Painel de leitura ao lado da lista: o usuário preferiu janela própria para ler.
- Manter o nome só com a data: a lista precisaria abrir todos os arquivos, e o Finder fica ilegível.
