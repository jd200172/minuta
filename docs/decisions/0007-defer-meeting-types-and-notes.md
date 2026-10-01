# 0007. Tipos de reunião e notas adiados para a segunda fase

Status: aceita; o adiamento dos tipos de reunião foi substituído pelo ADR 0017 (notas continuam adiadas)
Data: 2026-09-30
Substitui: categorias de reunião e função "Inserir Nota" (seções 1 e 3 de `docs/project-brief.md`).

## Contexto

O brief previa categorias de reunião escolhidas no início, que alteravam o system prompt, e uma barra de notas com atalho global. Gravação e transcrição não dependem de categoria. O app não é destinado a sessões de brainstorming. A nota marca um instante que o LLM talvez não destacasse, mas a ata sai sem ela.

## Decisão

Ficam fora do MVP e vão para a segunda fase:
- tipos de reunião (categorias e seus prompts);
- inserção de notas durante a gravação.

O MVP usa um único prompt de ata.

## Consequências

- Saem do MVP a barra de notas, o atalho global e a permissão de Monitoramento de Entrada.
- O estado do job perde categoria e notas.
- Quando os tipos voltarem, a escolha ocorre após a gravação, no momento de gerar a ata. O resumo sendo um passo separado sobre o texto (ADR 0002) permite regerar a ata com outro tipo sem reenviar áudio.

## Alternativas descartadas

- Manter os tipos com a escolha no início da gravação: decisão pedida antes de a reunião acontecer, sobre algo que só afeta o resumo.
- Manter notas no MVP: terceira interface e permissão extra para um ganho marginal na ata.
