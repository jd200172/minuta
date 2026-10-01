# Resultado esperado da reunião sintética

Referência para conferir a transcrição e a ata. Os tempos por fala estão em `out/ground-truth.json`, gerado por `build.py`. Data da reunião: 30/09/2026 (quarta-feira).

## Canais e vozes

| Canal | Falante | Voz |
|---|---|---|
| Microfone | Juliano | Reed |
| Sistema | Marina | Luciana |
| Sistema | Carlos | Rocko |
| Sistema | Ana | Shelley |

## Transcrição

- O canal do sistema deve ter 3 falantes distintos (Participante 1, 2 e 3), estáveis do início ao fim.
- O canal do microfone deve ter 1 falante.
- Há 3 trechos com sobreposição de fala (Carlos e Ana por volta de 1:39, Juliano e Marina por volta de 3:21, Carlos e Ana no fim). Conferir se a diarização troca ou funde vozes neles.

## Participantes

- Juliano: canal do microfone.
- Marina: nome dito por ela mesma na segunda fala.
- Carlos: nome dito por ele mesmo e também em vocativo de Juliano.
- Ana: ninguém a chama pelo nome ao falar com ela. Só o resumo final de Juliano diz "A Ana revisa o orçamento até sexta", o que a liga à ação de revisar o orçamento. Nomeá-la é aceitável, e manter "Participante N" também é. (O roteiro original supunha que o nome nunca aparecia; esse trecho foi corrigido após o primeiro teste real.)
- Roberto (do financeiro) é citado, mas não participa. Não pode aparecer como participante nem como responsável.

## Decisões

1. Lançamento adiado do dia 10/10 para 15/10/2026.
2. Antecipar o lançamento para 05/10 foi proposto e descartado (não é decisão; é discussão rejeitada).
3. Reunião de acompanhamento em 08/10/2026 (quinta-feira).

## Itens de ação

| Ação | Responsável | Prazo |
|---|---|---|
| Entregar o esquema de dados | Carlos | 07/10/2026 (próxima quarta-feira) |
| Revisar o orçamento e enviar ao Roberto | Participante de Ana (nome não dito) | 02/10/2026 (sexta-feira) |
| Preparar a comunicação aos clientes e enviar após a validação da migração | Marina | não definido |

## Pontos em aberto

- Tamanho do teste beta: 50 ou 100 usuários, com impacto no custo de infraestrutura. Sem responsável e sem prazo.

## Armadilhas que a ata não pode cair

- Atribuir a revisão do orçamento ao Roberto.
- Inventar prazo para a ação da Marina.
- Tratar a antecipação para 05/10 como decisão.
- Usar "Ana" como nome sem nenhuma evidência. Há uma evidência indireta no resumo final (ver acima).
- Converter "próxima quarta" e "sexta" sem usar a data da reunião como âncora.
