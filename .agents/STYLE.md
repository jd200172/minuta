---
source: ~/.agents/AGENTS.md
copied_at: 2026-09-30
---
# Padrão de escrita

## Aplica-se a

Documentação de produto, arquitetura e decisão técnica: briefings, specs, ADRs, docs de camada.

## Não se aplica a

Comentários de código e mensagens de commit.

## Registro (tom)

Decisões e consequências são fato, não conquista.

- Sem "a decisão certa", "o item mais valioso", "isso é ótimo porque".
- Sem metáfora de venda e sem flavor text narrativo (cenas, horários, drama de prazo).
- Mantém o porquê e os trade-offs de cada decisão. Não corta o racional, só não dramatiza.
- Comparativo justificado por mérito técnico ou mensurável ("custa mais", "escala pior", "reduz de X para Y"), nunca por orgulho.
- Superlativo só quando é dado verificável, nunca opinião estética.

## Forma (prosa)

- Frase curta quando a ideia é simples. Frase longa só quando carrega uma relação causal real.
- Corta muleta de transição ("isso significa que", "é importante notar", "vale destacar").
- Não repete a mesma estrutura sintática de frase em frase. Varia abertura e ritmo.
- Um substantivo carrega o peso, não um advérbio: "custa mais" em vez de "aumenta significativamente o custo".
- Sem metacomentário sobre o próprio texto ("como vimos", "conforme já dito").

## Ajustes deste projeto

Regras inspiradas no ASD-STE100, adotadas para tornar o padrão verificável.

### Limites

- Frase de procedimento (passos, comandos, instruções): até 20 palavras.
- Frase descritiva: até 25 palavras.
- Parágrafo: um tópico, até 6 frases.
- Exceção: a frase de decisão. O porquê vai em frase própria, no formato "Decisão: X. Motivo: Y.", cada uma dentro do limite. Frase acima do limite só quando carrega uma relação causal que não se separa sem perder o sentido.

### Um conceito, uma palavra

- Cada termo do projeto tem um só sentido, e cada conceito tem um só termo. Sem sinônimo para variar o texto.
- Os termos e seus sentidos ficam em `.agents/GLOSSARY.md`. Termo novo entra no glossário antes de aparecer em documento.
- Termo de domínio técnico (STT, diarização, ScreenCaptureKit) é livre, mas mantém uma só grafia.

### Palavras a evitar

Palavra vaga ou de reforço, que não carrega dado:

- "adequado", "apropriado", "robusto", "eficiente", "simples", "fácil", "melhor" (sem comparação medida);
- "geralmente", "normalmente", "eventualmente", "em geral", "basicamente", "praticamente";
- "etc.", "entre outros", "e assim por diante";
- "significativamente", "muito", "bastante", "diversos" (sem número).

Em vez da palavra vaga, o dado: número, nome, condição ou lista completa.
