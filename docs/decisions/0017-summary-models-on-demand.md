# 0017. Resumos por tipo de reunião, guardados por modelo

Status: aceita; implementada; parcialmente substituída pela `docs/decisions/0018-four-summary-models.md` (o modelo Acompanhamento deixou de existir, e a Informativa foi redefinida)
Data: 2026-10-01
Substitui: o prompt único e a estrutura única de ata do `docs/decisions/0005-minutes-structure-and-traceability.md`, e o adiamento dos tipos de reunião do `docs/decisions/0007-defer-meeting-types-and-notes.md`. A rastreabilidade do ADR 0005 continua valendo. Notas continuam adiadas (ADR 0007).
Complementa: `docs/decisions/0015-minutes-library.md` (nome do arquivo e renomeação do título) e `docs/decisions/0016-manual-participant-names.md`.

## Contexto

O app gerava a ata sozinho ao fim da transcrição, com um prompt único. Reuniões têm funções diferentes (decidir, acompanhar trabalho, discutir problemas, informar), e uma estrutura de ata corporativa serve mal a uma apresentação ou a um brainstorm. Os nomes dos participantes eram corrigidos só depois da ata pronta (ADR 0016), e o texto do modelo não os usava. O título da ata vinha do resumo e entrava no nome do arquivo, o que impede guardar mais de um resumo por reunião sem renomear arquivos.

Uso previsto: ler a ata fora do app (Obsidian, OneDrive), enviá-la por e-mail e consultá-la com o Claude por conectores. O arquivo `.md` precisa ser legível e completo sozinho.

Pesquisa sobre tipologias de reunião (consultada em 2026-10-01):
- Allen, Beck, Scott e Rogelberg (2014), *Understanding workplace meetings: A qualitative taxonomy of meeting purposes*: 491 respondentes descreveram a última reunião, e dois codificadores chegaram a 16 propósitos. Os mais frequentes são "projetos em andamento" (11,6%) e "estado do negócio" (10,8%). "Brainstorm" é o menos frequente (3,3%). Os autores registram que uma reunião costuma ter mais de um propósito e criticam as tipologias anteriores por falta de relações testáveis. Os 16 rótulos descrevem assunto (benefícios, tecnologia, finanças), não função.
- Tropman, *Making Meetings Work*: três ações numa reunião, informar, decidir e discutir. Consultado só em resumo secundário.
- Romano e Nunamaker (2001): 45% reuniões de equipe, 22% de força-tarefa e 21% de compartilhamento de informação. Consultado por citação em Allen et al. e por resultado de busca.
- Monge et al. (1989), 903 reuniões na 3M: decisão em grupo 26%, resolução de conflito 29%, resolução de problemas 11%. Consultado por citação em Allen et al.
- QMSum (Zhong et al., 2021): benchmark de sumarização com reuniões de produto, acadêmicas e de comitê, resumidas por pergunta, sem formato único.

Não há tipologia canônica. Só Allen et al. foi lido em texto completo. As demais citações precisam de conferência na fonte primária antes de serem repetidas fora deste ADR.

## Decisão

**Fluxo.**
1. Gravação encerrada: o app transcreve e grava a transcrição.
2. Classificação: uma chamada ao LLM recebe a transcrição e devolve o modelo sugerido, uma frase de justificativa e o título da reunião.
3. Geração automática: com sugestão, o app gera o resumo no modelo sugerido. Sem sugestão (falha ou baixa confiança), não gera.
4. O usuário abre a reunião, corrige os nomes dos participantes (ADR 0016) e, se quiser, troca de modelo.

Transcrição com menos de 10 palavras continua sem ata e sem classificação (ADR 0015).

**Modelos.** Cinco, definidos pela função da reunião:

| Modelo | Função | Seções específicas |
|---|---|---|
| Decisão | decidir | decisões, alternativas descartadas |
| Acompanhamento | coordenar o trabalho em curso | progresso, bloqueios, próximos passos |
| Problemas e ideias | discutir e gerar | problema, ideias, agrupamentos, a aprofundar |
| Informativa | informar e ensinar | pontos principais, dados citados, perguntas |
| Geral | propósito misto ou classificação incerta | resumo por tema |

Todos levam o núcleo comum: resumo, participantes, itens de ação, pontos em aberto e transcrição com âncoras. O responsável por cada ação fica nos itens de ação, não numa seção própria. As seções específicas vêm entre Participantes e Itens de ação. Itens de ação e pontos em aberto entram em todos os modelos porque a reunião costuma ter mais de um propósito, e o erro de classificação fica menos caro.

Brainstorm e resolução de problemas formam um modelo só: a frequência de brainstorm isolado é 3,3% e as duas funções produzem a mesma estrutura.

**Prompts e schemas.** Um prompt comum em `MinutesPrompt` (rastreabilidade, uso dos nomes, prazo relativo com a data da reunião, núcleo da saída) mais um bloco específico por modelo. Um schema por modelo, montado a partir do núcleo e do trecho do modelo. Os modelos são dados em `SummaryModels.swift` (seções, bloco de instruções e descrição para o classificador), e o schema, o prompt e a renderização leem dessa definição. Nomes informados pelo usuário entram na mensagem do pedido como evidência; `label` e `owner` continuam com o rótulo original e o texto corrido usa o nome. A validação de IDs continua no app e percorre toda seção que cita segmentos. O classificador usa um prompt à parte, com uma descrição de uma linha de cada modelo, tirada do próprio modelo.

**Modelo de LLM.** O classificador usa o mesmo modelo e a mesma configuração do resumo (`.env`, ADR 0012). Sem variável própria. O esforço de raciocínio do pedido é `low` na classificação e `medium` no resumo. A classificação devolve `model`, `confidence` (`alta` ou `baixa`), `reason` e `title`; confiança baixa vale como sem sugestão.

**Armazenamento: dois arquivos por reunião.**
- Principal, `AAAA-MM-DD HHmm Título.md`: frontmatter, cópia renderizada do resumo escolhido e transcrição. É legível sozinho, fora do app. O frontmatter tem `inicio`, `duracao_segundos`, `titulo` (quando houver), `modelo` (o escolhido) ou `resumo: nenhum` (ainda sem resumo) e, quando houver, `participantes` (ADR 0016). A presença de `modelo` ou `resumo` distingue o arquivo deste fluxo das atas anteriores, que continuam abrindo como antes, sem o controle de modelos.
- Secundário, `AAAA-MM-DD HHmm.resumos.json`: a transcrição segmentada com os rótulos originais, a classificação (modelo, confiança, justificativa e título) e todos os resumos gerados, como saída estruturada (JSON com os IDs de segmento). É o armazém: o principal, inclusive a transcrição e os nomes dos participantes, é renderizado a partir dele, então trocar de modelo não depende do texto do principal.
- Trocar de modelo: se o resumo desse modelo existe no secundário, o app o reaproveita sem chamar o LLM. Se não existe, gera, grava no secundário e então reescreve a seção do principal e o campo `modelo`. Os nomes dos participantes valem na renderização, então um resumo guardado antes da correção de nomes sai com os nomes atuais.
- Refazer: ação explícita "Refazer este resumo" substitui o resumo guardado daquele modelo. Clicar em um modelo nunca descarta nada.
- Se o secundário faltar ou não puder ser lido, o principal continua completo e legível, mas o controle de modelos mostra erro ao trocar de modelo e não gera outro resumo: sem a transcrição com rótulos originais o app não refaz o arquivo. Reconstruir o secundário a partir do principal não está implementado.

**Nome e chave da reunião.**
- A chave é o início da gravação, `inicio` em ISO 8601 com segundos e fuso, gravado no principal e dentro do secundário. O nome do arquivo é conveniência: o app casa os dois pelo `inicio`, mesmo que o prefixo seja renomeado no Finder.
- O prefixo `AAAA-MM-DD HHmm` (fuso local) ordena cronologicamente e não muda. Início no mesmo minuto continua recebendo ` (2)`, ` (3)` (ADR 0015).
- O secundário nunca é renomeado com o título.
- O título pertence à reunião, não ao resumo. Vem da classificação, fica no frontmatter (`titulo`) e não muda ao trocar de modelo. A linha `# Título` do corpo deriva dele.
- Antes da classificação terminar, o arquivo existe como `AAAA-MM-DD HHmm.md`, e o app o renomeia ao receber o título. Se a classificação falha, a reunião fica sem título, e a lista mostra o timestamp.
- Editar o título na janela de leitura regrava o frontmatter e renomeia só o principal. Isso traz para o MVP a renomeação do título, que o ADR 0015 deixava para depois.

**Interface (janela de leitura).**
- Os cinco modelos são chips na própria página, logo abaixo do título e da data. O escolhido fica preenchido, e um ponto dentro da chip indica que o modelo já tem resumo guardado. Esses modelos trocam na hora, e os demais geram ao clicar. Chips e ícones são links internos (`minuta://model/<modelo>`, `minuta://redo`, `minuta://title`), tratados pelo app como o lápis dos participantes; a página continua sem JavaScript.
- Cada chip tem um tooltip em três linhas: "Serve para", "Mostra" e "Use quando" (textos em `SummaryModel.tooltip`, ADR 0018). Todos os elementos da página com dica (chips, ponto de resumo gerado, lápis do título e dos participantes, ícone de refazer) usam o mesmo balão: um `NSPopover` com seta, no material do sistema (Liquid Glass onde o sistema o aplica). A página marca o elemento com `data-tip` (nunca `title`, que mostraria o tooltip comum do sistema junto) e `aria-label` ou `aria-description`; `PageTips` segue o mouse com um monitor de eventos, pergunta à página qual elemento está sob o ponteiro (`elementFromPoint`, como os renomes no lugar) e abre o balão abaixo do elemento após 0,4 s. O balão não recebe mouse nem teclado e fecha ao mover para fora, clicar, rolar, digitar ou perder o foco. Desvio das HIG, a pedido do usuário: o tooltip comum do sistema não aceita estilo nem três linhas com destaque. Controles nativos (botão "Mostrar no Finder", `.help` da lista de atas) continuam com o tooltip do sistema.
- A página é um card: o conteúdo inteiro fica num bloco de até 760 px, centralizado, sobre o fundo da janela (cor de página, mais escura que o card em ambos os modos). Em janela estreita o card ocupa a largura menos 16 px de cada lado; em janela larga a sobra vira margem igual dos dois lados. Antes, o corpo tinha `max-width: 760px` colado à esquerda e a sobra ficava toda à direita.
- Desvio da HIG, a pedido do usuário: chips próprias no lugar de um controle de segmentos nativo, por coerência com os horários clicáveis e os lápis da página. A escolha foi entre três propostas (controle nativo, chips e menu pop-up) e as chips ganharam. Respiro: 14 px de preenchimento horizontal e 8 px vertical por chip, 8 px entre chips, 18 px entre a data e as chips e 30 px entre a linha de sugestão e a primeira seção.
- Uma linha abaixo das chips mostra "Sugerido: modelo" e a justificativa da classificação, mesmo depois de gerado. Sem sugestão, a linha avisa e o usuário escolhe ou usa Geral.
- Durante a geração, a chip do modelo mostra um indicador de progresso, as outras ficam esmaecidas e deixam de ser links, e a linha diz "Gerando o resumo no modelo X…".
- O título tem um lápis ao lado, que renomeia no lugar (`TitleRename`): Return salva, Esc cancela, clicar fora salva. O título vazio volta ao nome só com o horário.
- Um ícone de atualizar ao fim das chips refaz o resumo do modelo escolhido ("Refazer este resumo"). Não pede confirmação: é uma ação nomeada, e o resumo gerado de novo substitui só o daquele modelo.
- Não há aviso de substituição ao trocar de modelo, porque nada se descarta.

**Lista de atas.** Mostra o modelo escolhido na coluna Resumo, com ponto colorido e nome (ADR 0015). Ignora os `.resumos.json`. Mover uma ata para a Lixeira move os dois arquivos. O menu de contexto da ata tem o submenu Resumo, com os cinco modelos.

## Consequências

- Custo: duas chamadas por reunião (classificação e resumo sugerido), mesmo que o usuário não abra a ata. Cada modelo adicional custa uma chamada com a transcrição inteira. Classificação errada deixa o resumo do modelo errado guardado, e a chamada é gasta.
- A edição manual da seção do resumo no `.md` principal se perde na próxima troca de modelo. A marca de seção gerada avisa disso.
- ADR 0002: o resumo continua um passo separado sobre o texto.
- ADR 0015: o título sai do resumo e vem da classificação. O nome de arquivo com título passa a depender só do título da reunião.
- ADR 0016: renomear participante regrava a seção do principal a partir do secundário, com os rótulos originais, e o campo `participantes` continua sendo o registro do desfazer. O defeito dos artigos ("O Marina") continua.
- A lista, a leitura, o conversor de Markdown e o gerador de Markdown precisam suportar seções variáveis por modelo, o arquivo secundário e o estado sem resumo.
- Falha na classificação não bloqueia: a reunião fica sem título e sem sugestão, e o usuário escolhe um modelo. Falha na geração mantém a transcrição e permite clicar de novo.
- Cada modelo precisa de uma reunião sintética do seu tipo, com resultado esperado, e o classificador precisa acertar o tipo e produzir um título aceitável nessas reuniões. A acurácia do classificador é critério de adoção. Provedor novo continua passando pela reunião sintética.
- Os testes automatizados do montador, do gerador de Markdown, da biblioteca de atas e do conversor para leitura mudam.
- A reunião entra no `.md` e no secundário ao fim da classificação, antes do resumo. O job pendente é apagado nesse ponto. A geração do resumo sugerido corre sobre o arquivo, e falha nela não perde a transcrição: o usuário clica no modelo para tentar de novo. A janela de atas mostra "Gerando resumo…" na linha da reunião enquanto isso.
- O modo `--process` da linha de comando classifica, grava os dois arquivos e gera o resumo sugerido (Geral sem sugestão); `--model <modelo>|all` escolhe outro.
- A marca de "seção gerada" do texto original não foi implementada: o frontmatter (`modelo`) já distingue o arquivo, e um comentário no corpo apareceria como texto na janela de leitura.

## Fora desta decisão

Envio da ata por e-mail e consulta por conectores são etapas posteriores, com ADR próprio. O envio contraria hoje a regra de que nada é armazenado na nuvem pelo app e de que texto só sai para o LLM, e exige decidir o que vai no e-mail (resumo escolhido, todos, transcrição), o destinatário e a guarda da credencial. O consumo por conectores depende só de o `.md` principal ser completo e de o frontmatter e os nomes serem estáveis. O Claude Desktop ou o Claude Code podem ler a `OUTPUT_DIR` diretamente, sem conector.

## Alternativas descartadas

- Resumo só sob clique, sem geração automática: a reunião chega sem resumo, e o custo evitado deixa de existir quando os resumos ficam guardados.
- Um resumo por arquivo, com substituição ao trocar de modelo: descarta resumos já gerados e pagos.
- Referência ao resumo escolhido no principal, sem a cópia: o `.md` deixa de ser legível sozinho, e perder o secundário perde todos os resumos.
- Mover o resumo escolhido entre principal e secundário: lógica de troca mais frágil que reescrever a seção a partir de um armazém completo.
- Vários resumos dentro do `.md` principal: arquivo longo, e a leitura fora do app mistura modelos.
- Título vindo do primeiro resumo: o nome do arquivo e o par com o secundário passariam a depender do resumo.
- Classificar e gerar na mesma chamada: erro de classificação produz o formato errado sem chance de correção.
- Um schema único com seções opcionais: campos vazios e preenchimento errado pelo modelo, testes menos claros.
- Botão separado "Gerar resumo" ao lado do seletor de modelo: dois controles para a mesma ação.
- Os 16 propósitos de Allen et al. como modelos: descrevem assunto, não estrutura de saída.
- Brainstorm como modelo próprio: 3,3% das reuniões e mesma estrutura de resolução de problemas.
- Modelos definidos pelo usuário: adiado. Os cinco ficam embutidos no app.
- Variável própria de modelo para o classificador: uma configuração a mais, sem medida que justifique.
