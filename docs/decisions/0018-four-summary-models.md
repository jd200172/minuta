# 0018. Quatro modelos de resumo

Status: aceita; implementada
Data: 2026-10-01
Substitui em parte: `docs/decisions/0017-summary-models-on-demand.md`. Saem o modelo Acompanhamento e a definição ampla de Informativa. O restante do ADR 0017 (fluxo, armazenamento em dois arquivos, chave da reunião, título, chips e lista de atas) continua valendo.

## Contexto

O ADR 0017 definiu cinco modelos: Decisão, Acompanhamento, Problemas e ideias, Informativa e Geral. Os cinco foram gerados para cada um dos cenários sintéticos 01 a 05 (25 resumos, Claude Sonnet 5.5, uma execução por célula) e comparados.

Observações:
- Resumo, participantes, itens de ação, pontos em aberto e transcrição são comuns aos cinco. O parágrafo de Resumo muda pouco entre modelos. Só mudam uma a três seções do miolo.
- No modelo certo, três seções próprias eram distintas e úteis: Alternativas descartadas (Decisão), Ideias por tema com autoria (Problemas e ideias), Perguntas com resposta e Dados citados (Informativa).
- O Acompanhamento não se separava do Geral. No cenário 02, o Geral entregou os mesmos fatos organizados por tema em vez de por pessoa, sem seção vazia. "Próximos passos" repetia Itens de ação quase um a um.
- No modelo errado, a estrutura imposta produzia conteúdo sem sustentação: decisão e alternativa descartada inventadas (cenário 05 em Decisão), meta tratada como decisão (cenário 02 em Decisão), bloqueios fabricados (cenário 03 em Acompanhamento), recomendações viradas em ideias (cenário 04 em Problemas e ideias), perguntas criadas a partir de assuntos (Informativa).
- O núcleo comum variou entre modelos do mesmo cenário: ações a mais ou a menos e um responsável trocado.
- Os `expected.md` aceitavam Geral no lugar do modelo esperado em quatro dos cinco cenários.

## Decisão

**Quatro modelos.**

| Modelo | Função | Seções específicas |
|---|---|---|
| Decisão | decidir | decisões, alternativas descartadas |
| Problemas e ideias | discutir e gerar | problema, ideias por tema, a aprofundar |
| Informativa | alguém expõe conteúdo e o grupo pergunta | pontos principais, dados citados, perguntas |
| Geral | propósito misto, status da equipe, pouco conteúdo ou classificação incerta | resumo por tema |

**Informativa, definição estreita.** Uma ou poucas pessoas expõem conteúdo ao grupo (apresentação, treinamento, palestra), com perguntas do público. Reunião de status, em que cada pessoa conta o próprio avanço, não é informativa.

**Reunião de status vai para Geral.** O bloco do Geral manda usar um tema por pessoa, com o que avançou, o que está travado e o que vem a seguir. A descrição do Geral no classificador cita o status da equipe. No cenário 02 a classificação saiu Geral com confiança alta. Geral com confiança baixa continua sendo "sem sugestão".

**Seção sem evidência fica vazia.** A regra comum do prompt diz que seção sem conteúdo sustentado pela transcrição fica com a lista vazia e não é preenchida para completar a estrutura. Os blocos reforçam: Decisão devolve "decisions" vazio se o grupo não decidiu, e meta, previsão ou estimativa dita por alguém não é decisão; Informativa só registra em "data" número, data e fato como foram ditos (proposta e estimativa não são dados) e só registra em "questions" pergunta que alguém fez.

**Compatibilidade com atas anteriores.**
- Uma classificação gravada com `acompanhamento` decodifica como sem sugestão, preservando justificativa e título.
- O secundário com resumo `acompanhamento` continua legível (as chaves de `summaries` são texto). O resumo não aparece nas chips.
- Um `.md` com `modelo: acompanhamento` abre com a cópia renderizada intacta. A linha sob as chips diz que o modelo não existe mais, e o usuário escolhe um dos quatro. Na janela de atas, a coluna Resumo fica vazia e o submenu Resumo não aparece para essa ata; a troca é feita pela janela de leitura.

## Consequências

- Uma chip a menos e uma cor a menos na lista de atas. A Informativa passa a verde e o Geral continua cinza.
- Menor custo ao trocar de modelo: um resumo a menos para gerar e guardar.
- Reunião de status, que o Acompanhamento cobria, sai no Geral em um formato por tema, com um tema por pessoa.
- Verificação (2026-10-01, cenários 01 a 05, os quatro modelos em cada): a classificação acertou os cinco (01 Decisão, 02 Geral, 03 Problemas e ideias, 04 Informativa, 05 Geral, os dois últimos com confiança alta, diferente da rodada anterior no 05). Com a regra de seção vazia, o Decisão do 03 e do 04 saiu sem decisões, o Problemas e ideias do 02 saiu sem ideias nem problema, e a Informativa do 05 saiu sem perguntas. A regra não elimina tudo: o Decisão do 05 ainda gerou uma "decisão" (nova conversa na terça) e uma alternativa descartada (adoção imediata da embalagem, que o grupo não propôs nem rejeitou), e o Decisão do 02 ainda tratou a meta de terça como decisão. A proteção contra modelo errado continua sendo a classificação e a escolha do usuário; o prompt reduz o dano e não o impede.
- Cenário 02 passa a esperar Geral. Os `expected.md` dos demais perdem a menção ao Acompanhamento.
- Os blocos dos modelos e o plano de validação (teste 8) foram atualizados.

## Alternativas descartadas

- Estrutura única adaptativa, sem tipos nem seletor: proposta feita junto com esta decisão. O usuário preferiu manter três tipos próprios e o Geral. A comparação sustenta o caminho adaptativo (menos custo e menos risco), mas os três tipos restantes têm formato distinto o bastante para o usuário perceber, e o controle explícito do formato foi mantido.
- Manter o Acompanhamento com "Próximos passos" removido: sobra Progresso e Bloqueios por pessoa, que o Geral de status cobre.
- Informativa ampla (apresentação e status): se confunde com o Geral e com o Acompanhamento removido.
- Cinco a oito tipos (Planejamento, Revisão, Deliberativa, Informativa de status, Exploratória): mais seções obrigatórias aumentam o risco de preenchimento sem evidência, e cabeçalho com Local e Participantes ausentes pede dados que o app não tem. Sem teste para Planejamento e Revisão (não há cenário sintético).
- Remover o decodificador do modelo antigo: tornaria ilegíveis o secundário e a classificação das atas já gravadas.
