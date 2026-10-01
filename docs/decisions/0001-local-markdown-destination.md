# 0001. Destino de persistência: Markdown local

Status: aceita; o ADR 0017 acrescentou um segundo arquivo por reunião (`.resumos.json`) ao lado do `.md`
Data: 2026-09-30
Substitui: seção 2 (Persistência) e seção 4 (formulário de configurações) de `docs/project-brief.md`.

## Contexto

O brief previa Notion ou Supabase. O contrato de configuração (`TARGET_DATABASE_ID`) só se aplica ao Notion. O Notion limita blocos de texto a 2000 caracteres, então a transcrição de 60 minutos vira dezenas de blocos. O Supabase exige projeto, esquema e RLS, e uma chave de serviço no cliente desktop expõe o banco. Os dois adicionam uma credencial, um estado de rede e um modo de falha. O projeto tem restrição de baixo consumo de recursos.

## Decisão

Cada ata é gravada como arquivo `.md` com frontmatter numa pasta configurada pelo usuário (`OUTPUT_DIR`). O acesso ao destino fica atrás de uma interface `Destination` com uma única implementação no MVP.

## Consequências

- Configuração do app: `LLM_API_KEY`, chave do STT (se distinta) e `OUTPUT_DIR`. Saem `DESTINATION_API_KEY` e `TARGET_DATABASE_ID`.
- O estado Sincronizando deixa de existir. O fim do fluxo é a gravação do arquivo em disco.
- Não há busca estruturada nem acesso entre dispositivos, exceto pelo sincronizador da pasta escolhida.
- Notion ou outro destino entram depois como nova implementação de `Destination`.

## Alternativas descartadas

- Notion: conversão de Markdown para blocos, chunking e credencial adicional.
- Supabase: esquema, RLS e exposição de chave no cliente.
