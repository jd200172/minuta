# Cenários de reunião sintética

Cada pasta tem `script.json` (roteiro e vozes), `expected.md` (resultado esperado) e, depois de `build.py`, `out/` (áudio e `ground-truth.json`, não versionado). Cobrem os quatro modelos de resumo e a classificação (ADR 0017).

| Pasta | Modelo esperado | Duração | O que testa |
|---|---|---|---|
| `01-lancamento` | Decisão | 4:13 | Decisão, ações com prazo relativo, proposta descartada, participante citado que não fala |
| `02-semanal-projeto` | Geral | 3:31 | Status por pessoa (progresso, bloqueios e próximos passos), meta que não é decisão, terceiros citados |
| `03-brainstorm-cancelamento` | Problemas e ideias | 3:59 | Ideias sem decisão, agrupamento, assunto fora do tema |
| `04-treinamento-seguranca` | Informativa | 3:33 | Apresentador dominante, dados citados, perguntas, conselhos que não são ações |
| `05-fornecedor-misto` | Geral | 3:28 | Assuntos misturados sem função dominante, propostas que não são decisões |
| `06-decisao-com-status` | Decisão ou Geral | 3:06 | Classificação ambígua, alternativas descartadas |
| `07-conversa-vaga` | sem sugestão ou Geral | 3:04 | Baixa confiança, nada a inventar |
| `08-um-a-um-sem-nomes` | Geral ou Decisão | 3:06 | "Seu nome" vazio ("Eu"), nenhum nome dito |

Comandos:
- `python3 tools/synthetic-meeting/build.py --list` lista os cenários.
- `python3 tools/synthetic-meeting/build.py 02-semanal-projeto` gera um.
- `python3 tools/synthetic-meeting/build.py --all` gera todos (cerca de 4 minutos).

Os cenários 1 a 5 têm um modelo esperado cada. Os 6 a 8 medem o comportamento do classificador em casos ambíguos, vagos e sem nomes. Os valores numéricos dos roteiros são fictícios.
