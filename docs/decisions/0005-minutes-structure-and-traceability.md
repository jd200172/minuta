# 0005. Estrutura da ata e rastreabilidade pela transcrição

Status: aceita
Data: 2026-09-30
Substitui: estrutura de ata do exemplo em `docs/project-brief.md` (seção 4) e o formato de saída em `docs/decisions/0001-local-markdown-destination.md` (campos do frontmatter).

## Contexto

O objetivo do app é produzir, ao fim da transcrição, um texto que resume os diálogos, os participantes, as decisões e os responsáveis. A transcrição precisa estar acessível, e cada decisão precisa apontar para o trecho que a origina. Guias de ata e literatura de sumarização convergem em: decisão separada de discussão, ação com responsável e prazo, e resumo por tema com atribuição de fala.

## Decisão

Um arquivo `.md` por reunião, com estas seções, nesta ordem:
1. Resumo: 3 a 5 linhas com objetivo, resultado e pendências.
2. Participantes.
3. Decisões.
4. Itens de ação (ação, responsável, prazo, origem).
5. Pontos em aberto.
6. Resumo por tema.
7. Transcrição, ao final, segmentada.

Fora da estrutura: pauta prévia, local, assinatura, prioridade e status.

Rastreabilidade:
- Cada segmento da transcrição tem âncora `t-<segundos>` derivada do início (`t-002537` para 00:42:17).
- O LLM recebe a transcrição segmentada, com IDs, e devolve decisões, ações e pontos em aberto em JSON com a lista de IDs de origem.
- O app monta o Markdown a partir do JSON e valida: todo ID citado deve existir na transcrição. Item sem ID válido é marcado como sem evidência ou descartado.
- Campo sem evidência na transcrição recebe "não definido". O LLM não preenche por inferência.
- Prazo relativo ("até sexta") só vira data se o prompt receber a data da reunião como âncora.

## Consequências

- O `.md` é longo: a transcrição de 60 minutos soma dezenas de milhares de caracteres.
- Âncoras HTML funcionam em visualizadores Markdown comuns. O Obsidian pode não rolar até elas (verificar). O timestamp visível permite busca em qualquer caso.
- O STT precisa devolver timestamps por segmento. Critério de escolha do provedor.
- Citação literal curta por decisão é opcional e fica para avaliação.
- Frontmatter: `TODO` definir campos (início, duração, participantes identificados, modelos). Campos de categoria e notas saíram (ADR 0007).

## Alternativas descartadas

- Dois arquivos (ata e transcrição) ligados por link relativo: ata mais curta, mas o link depende do visualizador.
- LLM escrevendo os links: risco de referência inventada, sem validação por regra.
