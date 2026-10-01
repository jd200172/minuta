# 0010. Limite de gravação de 30 minutos (proposta)

Status: proposta, aguarda confirmação do usuário
Data: 2026-09-30
Altera, se aceita: a regra de gravação de 60 minutos do `AGENTS.md` (seção Regras e restrições) e do `docs/project-brief.md`.

## Contexto

A documentação do Gemini 3.5 Transcribe limita o áudio a 1 hora por pedido, e a 30 minutos quando a diarização ou os timestamps por palavra estão ativos. O projeto precisa dos dois (ADRs 0005 e 0006). Uma gravação de 60 minutos exigiria dividir o áudio em duas partes de 30 minutos, transcritas em pedidos separados. Nada garante que os rótulos de falante do pedido 1 coincidam com os do pedido 2, o que quebraria o requisito de não misturar participantes.

Fonte: página do modelo em ai.google.dev, conferida em 2026-09-30.

## Decisão proposta

Limitar a gravação a 30 minutos no MVP. No teto, o app encerra a captura e processa, como já fazia no limite de 60.

O código usa a constante `Config.maxRecordingSeconds = 30 * 60`. Alterar o limite é trocar um número.

## Consequências

- Reuniões acima de 30 minutos ficam cortadas no MVP. O início é preservado, e o final se perde.
- Sem divisão em partes e sem reconciliação de rótulos entre pedidos: menos código.
- O teste 4 do `docs/validation-plan.md` (áudio de 60 minutos) passa a verificar o limite real do serviço.

## Alternativas

- Manter 60 minutos com duas partes de 30: exige reconciliar os rótulos de falante entre as partes, sem garantia do provedor.
- Trocar de provedor de STT para um sem esse limite (AssemblyAI não documenta limite equivalente nas páginas consultadas).
- Manter 60 minutos e transcrever sem diarização nem timestamps por palavra: perde o requisito de separar participantes.
