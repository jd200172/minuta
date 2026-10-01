# 0017. Resumos por tipo de reunião, guardados por modelo

Status: aceita; não implementada
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
| Decisão | decidir | decisões, alternativas descartadas, responsáveis |
| Acompanhamento | coordenar o trabalho em curso | progresso, bloqueios, próximos passos |
| Problemas e ideias | discutir e gerar | problema, ideias, agrupamentos, a aprofundar |
| Informativa | informar e ensinar | pontos principais, dados citados, perguntas |
| Geral | propósito misto ou classificação incerta | resumo por tema |

Todos levam o núcleo comum: resumo, participantes, itens de ação, pontos em aberto e transcrição com âncoras. Itens de ação e pontos em aberto entram em todos os modelos porque a reunião costuma ter mais de um propósito, e o erro de classificação fica menos caro.

Brainstorm e resolução de problemas formam um modelo só: a frequência de brainstorm isolado é 3,3% e as duas funções produzem a mesma estrutura.

**Prompts e schemas.** Um prompt comum em `MinutesPrompt` (rastreabilidade, uso dos nomes, prazo relativo com a data da reunião, núcleo da saída) mais um bloco específico por modelo. Um schema por modelo, montado a partir do núcleo e do trecho do modelo. A validação de IDs continua no app e percorre toda seção que cita segmentos. O classificador usa um prompt à parte, com uma descrição de uma linha de cada modelo, tirada do próprio modelo.

**Modelo de LLM.** O classificador usa o mesmo modelo e a mesma configuração do resumo (`.env`, ADR 0012). Sem variável própria.

**Armazenamento: dois arquivos por reunião.**
- Principal, `AAAA-MM-DD HHmm Título.md`: frontmatter, cópia renderizada do resumo escolhido e transcrição. É legível sozinho, fora do app. O frontmatter tem `inicio`, `titulo`, `duracao_segundos`, `modelo` (o escolhido) e, quando houver, `participantes` (ADR 0016). A seção do resumo vem marcada como gerada pelo app.
- Secundário, `AAAA-MM-DD HHmm.resumos.json`: todos os resumos gerados da reunião, inclusive o escolhido, como saída estruturada (JSON com os IDs de segmento), com os rótulos originais dos participantes. É o armazém: a cópia no principal deriva dele.
- Trocar de modelo: se o resumo desse modelo existe no secundário, o app o reaproveita sem chamar o LLM. Se não existe, gera, grava no secundário e então reescreve a seção do principal e o campo `modelo`. Os nomes dos participantes valem na renderização, então um resumo guardado antes da correção de nomes sai com os nomes atuais.
- Refazer: ação explícita "Refazer este resumo" substitui o resumo guardado daquele modelo. Clicar em um modelo nunca descarta nada.
- Se o secundário faltar ou não puder ser lido, o principal continua completo. Perdem-se as alternativas, que o app gera de novo sob demanda.

**Nome e chave da reunião.**
- A chave é o início da gravação, `inicio` em ISO 8601 com segundos e fuso, gravado no principal e dentro do secundário. O nome do arquivo é conveniência: o app casa os dois pelo `inicio`, mesmo que o prefixo seja renomeado no Finder.
- O prefixo `AAAA-MM-DD HHmm` (fuso local) ordena cronologicamente e não muda. Início no mesmo minuto continua recebendo ` (2)`, ` (3)` (ADR 0015).
- O secundário nunca é renomeado com o título.
- O título pertence à reunião, não ao resumo. Vem da classificação, fica no frontmatter (`titulo`) e não muda ao trocar de modelo. A linha `# Título` do corpo deriva dele.
- Antes da classificação terminar, o arquivo existe como `AAAA-MM-DD HHmm.md`, e o app o renomeia ao receber o título. Se a classificação falha, a reunião fica sem título, e a lista mostra o timestamp.
- Editar o título na janela de leitura regrava o frontmatter e renomeia só o principal. Isso traz para o MVP a renomeação do título, que o ADR 0015 deixava para depois.

**Interface (janela de leitura).**
- Os cinco modelos formam um controle "Resumo no modelo". O modelo escolhido fica marcado. Os que já têm resumo guardado trocam na hora, e os demais geram ao clicar.
- O modelo sugerido pela classificação traz a marca "Sugerido" e a justificativa em uma linha, mesmo depois de gerado.
- Sem sugestão, nenhum modelo é destacado, uma linha avisa e o usuário escolhe ou usa Geral.
- Durante a geração, o modelo clicado mostra "Gerando…" e os demais ficam esmaecidos.
- "Refazer este resumo" fica num menu discreto ao lado do controle.
- Não há aviso de substituição, porque trocar de modelo não descarta nada.

**Lista de atas.** Mostra o modelo escolhido numa etiqueta. Ignora os `.resumos.json`. Apagar uma ata move os dois arquivos para a Lixeira.

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
- Pontos a definir na implementação:
  - Formato exato da marca de seção gerada e do JSON secundário.
  - Onde guardar o resultado da classificação enquanto o resumo é gerado (estado do job).
  - Se "Refazer este resumo" pede confirmação.
  - Texto do aviso quando o secundário está ilegível.

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
