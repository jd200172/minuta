---
inicio: 2026-09-30T14:02:00-03:00
duracao_segundos: 0
---

# Reunião sobre lançamento da versão 2 do aplicativo e orçamento do trimestre

## Resumo
O grupo decidiu adiar o lançamento da versão 2 de 10 para 15 de outubro de 2026, após descartar a antecipação por risco de perda de dados. Participante 2 entrega o esquema de dados até a próxima quarta-feira, Participante 3 revisa o orçamento, que estourou em 12%, e envia ao financeiro até sexta-feira, e Participante 1 prepara a comunicação aos clientes sem data definida. O tamanho do teste beta segue em aberto. Foi marcada reunião de acompanhamento para 08/10/2026.

## Participantes
- Juliano
- Marina (Participante 1, nome inferido em [00:00:10](#t-000010) [00:00:22](#t-000022))
- Carlos (Participante 2, nome inferido em [00:00:17](#t-000017) [00:00:36](#t-000036))
- Participante 3 (sem nome identificado)

## Decisões
- Antecipar o lançamento para o dia 5 de outubro foi descartado devido ao risco de perda de dados. [00:01:04](#t-000064) [00:01:11](#t-000071) [00:01:17](#t-000077)
- O lançamento da versão 2 foi adiado de 10 de outubro para 15 de outubro de 2026. [00:01:17](#t-000077) [00:01:28](#t-000088) [00:01:32](#t-000092) [00:01:39](#t-000099) [00:01:41](#t-000101)
- Realizar reunião de acompanhamento na quinta-feira, 08/10/2026. [00:03:18](#t-000198) [00:03:21](#t-000201) [00:03:31](#t-000211) [00:03:34](#t-000214) [00:03:36](#t-000216) [00:03:38](#t-000218)

## Itens de ação
| Ação | Responsável | Prazo | Origem |
|---|---|---|---|
| Entregar o esquema de dados (dois ajustes nas tabelas de eventos e validação da migração em ambiente de teste) até a próxima quarta-feira. | Carlos (Participante 2) | 07/10/2026 | [00:00:42](#t-000042) [00:01:41](#t-000101) [00:01:54](#t-000114) [00:04:03](#t-000243) [00:04:08](#t-000248) |
| Preparar o texto da comunicação aos clientes e enviá-lo somente depois que a migração for validada. A comunicação precisa sair pelo menos três dias antes do lançamento. | Marina (Participante 1) | não definido | [00:02:01](#t-000121) [00:02:10](#t-000130) |
| Revisar o orçamento do trimestre e enviar a planilha ao Roberto, do financeiro, até sexta-feira. | Participante 3 | 02/10/2026 | [00:02:40](#t-000160) [00:02:48](#t-000168) |

## Pontos em aberto
- Definir se o teste beta terá 50 ou 100 usuários, o que altera o custo de infraestrutura. Não há dados suficientes e o ponto será retomado na próxima reunião. [00:02:52](#t-000172) [00:02:59](#t-000179) [00:03:06](#t-000186) [00:03:12](#t-000192) [00:03:18](#t-000198)
- Data em que a migração será validada, da qual depende o envio da comunicação aos clientes, não está definida. [00:02:01](#t-000121)
- Tratamento do estouro de 12% no orçamento do trimestre ainda depende da revisão dos números e da análise do Roberto, do financeiro, que ainda não viu a planilha. [00:02:20](#t-000140) [00:02:28](#t-000148) [00:02:34](#t-000154)

## Resumo por tema
### Cronograma de lançamento
O lançamento estava marcado para 10 de outubro, mas o time de dados não fechou o esquema das tabelas e a migração precisa de validação em ambiente de teste. A comunicação aos clientes deve sair ao menos três dias antes. Antecipar foi descartado e o lançamento foi adiado para 15 de outubro. [00:00:26](#t-000026) [00:00:42](#t-000042) [00:00:55](#t-000055) [00:01:04](#t-000064) [00:01:11](#t-000071) [00:01:17](#t-000077) [00:01:41](#t-000101)

### Comunicação aos clientes
Marina prepara o texto, mas só o envia após a confirmação de que a migração foi validada, sem data definida. [00:01:57](#t-000117) [00:02:01](#t-000121) [00:02:10](#t-000130)

### Orçamento do trimestre
O orçamento do trimestre estourou em 12% por causa do custo de infraestrutura dos testes. A revisão será feita e enviada ao Roberto do financeiro até sexta-feira. [00:02:20](#t-000140) [00:02:34](#t-000154) [00:02:40](#t-000160) [00:02:48](#t-000168)

### Tamanho do teste beta
Discutiu-se se o beta terá 50 ou 100 usuários. Com 100 usuários o custo sobe e o cálculo precisaria ser refeito. O ponto segue em aberto. [00:02:52](#t-000172) [00:02:59](#t-000179) [00:03:06](#t-000186) [00:03:12](#t-000192) [00:03:18](#t-000198)

## Transcrição
<a id="t-000000"></a>**[00:00:00] Juliano:** Bom dia, pessoal. Vamos começar. A pauta de hoje é o lançamento da versão 2 do aplicativo e orçamento do trimestre.

<a id="t-000010"></a>**[00:00:10] Marina (Participante 1):** Bom dia. Aqui é a Marina. Eu consegui o retorno do time de comunicação ontem à noite.

<a id="t-000017"></a>**[00:00:17] Carlos (Participante 2):** Bom dia a todos. Carlos por aqui.

<a id="t-000020"></a>**[00:00:20] Participante 3:** Bom dia.

<a id="t-000022"></a>**[00:00:22] Juliano:** Marina, pode começar pelo cronograma.

<a id="t-000026"></a>**[00:00:26] Marina (Participante 1):** Claro. Hoje o lançamento está marcado para o dia 10 de outubro. O problema é que o time de dados ainda não fechou o esquema das tabelas.

<a id="t-000036"></a>**[00:00:36] Juliano:** Carlos, você está com esse esquema, certo? Qual é a situação?

<a id="t-000042"></a>**[00:00:42] Carlos (Participante 2):** Estou sim. Faltam dois ajustes nas tabelas de eventos e eu preciso validar a migração em um ambiente de teste. Não consigo terminar antes da próxima quarta-feira.

<a id="t-000055"></a>**[00:00:55] Marina (Participante 1):** Então o dia 10 fica inviável. A comunicação com os clientes precisa sair pelo menos três dias antes do lançamento.

<a id="t-000064"></a>**[00:01:04] Carlos (Participante 2):** Eu poderia tentar antecipar para o dia cinco, mas aí a gente arriscaria lançar sem a migração testada.

<a id="t-000071"></a>**[00:01:11] Participante 3:** Antecipar está fora de questão. O risco de perder dados é grande demais.

<a id="t-000077"></a>**[00:01:17] Juliano:** Concordo. Antecipar está descartado. Então proponho adiar o lançamento para o dia 15 de outubro. Alguém tem objeção?

<a id="t-000088"></a>**[00:01:28] Marina (Participante 1):** Por mim tudo bem. Dá tempo de preparar a comunicação.

<a id="t-000092"></a>**[00:01:32] Carlos (Participante 2):** 15 funciona. Com esse prazo eu consigo entregar o esquema até a próxima quarta e ainda sobra uma semana para testar.

<a id="t-000099"></a>**[00:01:39] Participante 3:** Sem objeção.

<a id="t-000101"></a>**[00:01:41] Juliano:** Então está decidido. O lançamento passa para o dia 15 de outubro. Carlos, fica registrado que você entrega o esquema de dados até a próxima quarta-feira.

<a id="t-000114"></a>**[00:01:54] Carlos (Participante 2):** Fechado. Entrego até quarta.

<a id="t-000117"></a>**[00:01:57] Juliano:** Marina, e a comunicação aos clientes?

<a id="t-000121"></a>**[00:02:01] Marina (Participante 1):** Eu preparo o texto, mas só envio depois que o Carlos confirmar que a migração foi validada. Ainda não sei quando isso vai acontecer.

<a id="t-000130"></a>**[00:02:10] Juliano:** OK. Fica como ação sua, sem data por enquanto. Agora vamos ao orçamento. Quem está com os números?

<a id="t-000140"></a>**[00:02:20] Participante 3:** Sou eu. O orçamento do trimestre estourou em 12% por causa do custo de infraestrutura dos testes.

<a id="t-000148"></a>**[00:02:28] Marina (Participante 1):** 12% é bastante. O Roberto do financeiro já viu isso?

<a id="t-000154"></a>**[00:02:34] Participante 3:** Ainda não. O Roberto só recebe a planilha depois que eu revisar os números.

<a id="t-000160"></a>**[00:02:40] Juliano:** Então a revisão é prioridade. Você consegue revisar o orçamento e mandar para o Roberto até sexta-feira?

<a id="t-000168"></a>**[00:02:48] Participante 3:** Consigo revisar e enviar até sexta.

<a id="t-000172"></a>**[00:02:52] Carlos (Participante 2):** Uma dúvida. O teste beta vai ter 50 ou 100 usuários? Isso muda o custo de infraestrutura.

<a id="t-000179"></a>**[00:02:59] Juliano:** Boa pergunta. Precisamos definir isso, mas hoje não temos dados suficientes.

<a id="t-000186"></a>**[00:03:06] Marina (Participante 1):** Acho que 100 é melhor para a comunicação, mas não o tenho como garantir o orçamento.

<a id="t-000192"></a>**[00:03:12] Participante 3:** Com 100 usuários o custo sobe bastante. Eu precisaria refazer a conta.

<a id="t-000198"></a>**[00:03:18] Juliano:** Vamos deixar esse ponto em aberto e voltar a ele na próxima reunião. Falando em próxima reunião, que tal uma reunião de acompanhamento na quinta-feira, dia 8 de outubro?

<a id="t-000201"></a>**[00:03:21] Marina (Participante 1):** Concordo.

<a id="t-000211"></a>**[00:03:31] Carlos (Participante 2):** Quinta dia oito está bom para mim.

<a id="t-000214"></a>**[00:03:34] Marina (Participante 1):** Para mim também.

<a id="t-000216"></a>**[00:03:36] Participante 3:** Pode ser.

<a id="t-000218"></a>**[00:03:38] Juliano:** Combinado. Reunião de acompanhamento no dia 8 de outubro. Resumindo, o lançamento foi adiado para o dia 15 de outubro. O Carlos entrega o esquema até quarta. A Ana revisa o orçamento até sexta. A Marina prepara a comunicação sem data. E o tamanho do beta segue aberto.

<a id="t-000240"></a>**[00:04:00] Marina (Participante 1):** Perfeito. É isso.

<a id="t-000243"></a>**[00:04:03] Carlos (Participante 2):** Só confirmando. O esquema é até quarta-feira da semana que vem.

<a id="t-000248"></a>**[00:04:08] Juliano:** Isso mesmo. Obrigado a todos.

<a id="t-000251"></a>**[00:04:11] Carlos (Participante 2):** Até mais.

<a id="t-000252"></a>**[00:04:12] Participante 3:** Até mais.

