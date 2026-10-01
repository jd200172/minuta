# Plano de validação

Data: 2026-09-30
Status: testes 2, 3 e 5 executados com o áudio sintético em 2026-09-30; teste 4 parcial. Teste 1 parcial (captura do sistema funciona). Testes 6 e 7 pendentes.

Sete testes que respondem as dúvidas técnicas das decisões antes de escrever o app. A ordem segue o risco: o que mais pode inviabilizar o projeto vem primeiro. Cada teste tem critério de aprovação e registra o resultado neste arquivo. Resultado negativo reabre o ADR indicado.

Critérios marcados como "proposta" são valores sugeridos sem base medida. O primeiro resultado real os confirma ou os ajusta.

## Dependências

| Teste | Precisa de |
|---|---|
| 1. Captura no macOS | nada além do Mac |
| 7. Termos de dados | nada |
| 2, 3 e 4. Transcrição, diarização e formato | chave de API do Google, áudio sintético |
| 5. Ata | chave de API da Anthropic, saída do teste 2 |
| 6. Voz real | 2 ou 3 pessoas e chave do Google |

Os testes 1 e 7 podem começar agora.

## Material de teste

- Áudio sintético de 253 s, em `tools/synthetic-meeting/out/` (gerado por `python3 tools/synthetic-meeting/build.py`): `mic.ogg` e `system.ogg`, um arquivo mono por canal.
- Gabarito: `tools/synthetic-meeting/out/ground-truth.json` (quem fala e quando) e `tools/synthetic-meeting/expected.md` (decisões, ações, armadilhas).
- O áudio sintético tem 44 falas: 16 no microfone (Juliano) e 28 no sistema (Marina 10, Carlos 9, Ana 9), com 3 trechos de sobreposição.

---

## Teste 1. Captura de áudio do sistema no macOS

**Pergunta.** O macOS entrega o áudio do sistema e o microfone para um arquivo de dois canais, sem driver que o usuário precise instalar?

**Decisão afetada.** ADR 0004 e ADR 0003 (captura por ScreenCaptureKit ou driver virtual).

**Passos.**
1. Conceder ao terminal ou ao Python a permissão de Gravação de Tela.
2. Capturar ScreenCaptureKit (áudio do sistema) e microfone ao mesmo tempo, por 30 s, enquanto um vídeo com fala toca e você fala.
3. Gravar em dois canais, Ogg/Opus a 16 kHz. Repetir com driver virtual se o ScreenCaptureKit falhar.
4. Ouvir cada canal separado.
5. Gravar por 60 minutos contínuos e medir CPU, memória e tamanho do arquivo.
6. Desconectar um fone Bluetooth no meio de uma gravação e abrir o arquivo resultante.

**Aprovação.**
- O canal do sistema contém o áudio do vídeo e o do microfone contém só a sua voz (com fone, sem eco do alto-falante).
- O arquivo de 60 minutos abre e tem a duração correta.
- Após a desconexão do fone, o arquivo abre e contém a gravação até aquele ponto (ADR 0004, perda de stream).
- CPU e memória registrados. Limite a definir com os números medidos, pela restrição de baixo consumo.

**Se falhar.** Registrar qual caminho funcionou (ScreenCaptureKit ou driver virtual) e o custo para o usuário. Se nenhum funcionar, o projeto perde o canal do sistema e o ADR 0004 precisa ser reescrito.

**Resultado parcial (2026-09-30, relatado pelo usuário).** O teste de captura de 5 s da tela de configurações funcionou: o app capturou o áudio do sistema por ScreenCaptureKit, com a identidade de assinatura local e as permissões concedidas.
- Este Mac é um Mac mini sem dispositivo de entrada de áudio. O microfone não foi testado, e o app grava só o áudio do sistema nesse caso.
- Não testado: gravação de 60 minutos (e de 30, o limite atual), consumo de CPU e memória durante a gravação, desconexão de fone no meio da gravação, eco do microfone.
- Decisão confirmada: ScreenCaptureKit serve como caminho de captura no macOS, sem driver virtual.

---

## Teste 2. Transcrição em português

**Pergunta.** O Gemini 3.5 Transcribe transcreve português do Brasil com fidelidade suficiente?

**Decisão afetada.** ADR 0008.

**Passos.**
1. Enviar `mic.ogg` e `system.ogg` separadamente, com timestamps e diarização no canal do sistema.
2. Comparar a transcrição com `ground-truth.json` fala por fala.
3. Conferir nomes próprios (Marina, Carlos, Roberto), datas e números (dez, quinze e oito de outubro, doze por cento, cinquenta e cem usuários).

**Aprovação.**
- Nenhuma das 44 falas omitida.
- Nenhuma data ou número errado.
- Nomes próprios corretos, com no máximo uma variação de grafia (proposta).

**Se falhar.** Repetir com o AssemblyAI (alternativa documentada no ADR 0008) antes de trocar de provedor.

**Resultado (2026-09-30, áudio sintético, 253 s).** Aprovado.
- Nenhuma fala omitida. Falas consecutivas do mesmo falante, separadas por menos de 1,2 s, foram agrupadas pelo app: 44 falas viraram 40 segmentos.
- Diferença de texto contra o gabarito: cerca de 1% no microfone (2 palavras em 220) e 1,6% no sistema (5 em 320, contando "por cento" escrito como "%"). Erros reais: "em" omitido e um "o" inserido em "não o tenho".
- Números e datas corretos, escritos em dígitos ("dia 15 de outubro"). Nomes próprios corretos (Marina, Carlos, Roberto).
- O áudio foi enviado como AAC `.m4a` mono de 16 kHz a 32 kbps, um arquivo por canal. Amostra em `tools/synthetic-meeting/sample/transcript.json`.
- Limite: voz sintética é mais limpa que voz real.

---

## Teste 3. Diarização do canal do sistema

**Pergunta.** A diarização separa três vozes e mantém cada uma estável do início ao fim?

**Decisão afetada.** ADR 0006. O modelo marca como experimental a atribuição com 3 ou mais falantes.

**Passos.**
1. No resultado do teste 2, mapear cada rótulo do provedor para Marina, Carlos ou Ana.
2. Contar, entre as 28 falas do sistema, as que receberam o rótulo errado.
3. Registrar o que ocorre nas 3 sobreposições.
4. Repetir com as vozes em ordem diferente de entrada, para conferir que a ordem não altera os rótulos.

**Aprovação.**
- Três rótulos distintos, um por voz.
- Nenhuma fusão de duas vozes num só rótulo.
- Nenhuma troca nas falas sem sobreposição.
- Erros nas sobreposições são registrados e não reprovam (proposta).

**Se falhar.** Fusão de vozes reprova, porque viola o requisito de não misturar participantes. Reabrir o ADR 0008 e testar o AssemblyAI.

**Resultado (2026-09-30, áudio sintético).** Aprovado.
- As 28 falas do canal do sistema receberam o rótulo correto: Marina 10 de 10, Carlos 9 de 9, Ana 9 de 9. Três rótulos distintos, estáveis do início ao fim.
- As três sobreposições foram transcritas sem perder nenhuma das falas.
- Não repeti com a ordem de entrada alterada.
- Limite: são 3 vozes sintéticas bem distintas (2 femininas e 1 masculina no sistema). O modelo marca como experimental a atribuição com 3 ou mais falantes. O teste 6 (voz real) continua necessário.

---

## Teste 4. Formato da resposta e áudio longo

**Pergunta.** A resposta traz os campos que o app precisa, e eles se mantêm estáveis em 60 minutos?

**Decisão afetada.** ADR 0005 (segmentos e âncoras `t-<segundos>`) e limites do ADR 0008.

**Passos.**
1. Conferir se cada segmento traz início, falante e texto.
2. Comparar o início de cada segmento com `ground-truth.json`.
3. Gerar um áudio sintético de 60 minutos repetindo o roteiro (cerca de 14 repetições) e enviar o canal do sistema. Esse arquivo ainda não existe e precisa ser gerado.
4. Registrar duração máxima e tamanho máximo aceitos por arquivo, e se os rótulos de falante se mantêm do início ao fim.

**Aprovação.**
- Diferença de início por segmento de no máximo 2 s (proposta).
- O arquivo de 60 minutos é aceito e transcrito por inteiro.
- Os três rótulos continuam estáveis até o final.

**Se falhar.** Se houver limite de duração abaixo de 60 minutos, segmentar o áudio por partes e reavaliar a consistência dos rótulos entre as partes.

**Resultado parcial (2026-09-30).**
- Formato: a resposta traz palavras com falante (`spk_N`) e início e fim em segundos. O app agrupa em segmentos e gera os IDs `t-<segundos>`.
- Horários: 33 dos 40 IDs coincidem com o gabarito. A maior diferença de início contra o gabarito é de 0,11 s. Os demais IDs diferem porque falas foram agrupadas.
- Não testado: o arquivo de 60 minutos e a estabilidade dos rótulos em áudio longo. A documentação do Google limita a 30 minutos com diarização (ADR 0010).

---

## Teste 5. Geração da ata

**Pergunta.** O Claude Sonnet 5.5 gera uma ata correta e rastreável a partir da transcrição?

**Decisão afetada.** ADR 0002 e ADR 0005.

**Passos.**
1. Montar o prompt único da ata, com a data da reunião (30/09/2026) como âncora.
2. Enviar a transcrição segmentada, com IDs, do teste 2.
3. Exigir saída estruturada em JSON (decisões, ações, pontos em aberto, participantes, IDs de origem).
4. Rodar em esforço `medium` e em `high`. Registrar tokens e custo por ata.
5. Conferir o resultado contra `expected.md`.

**Aprovação.**
- 2 decisões (lançamento em 15/10 e acompanhamento em 08/10). A antecipação para 05/10 não aparece como decisão.
- 3 ações, com responsável e prazo corretos: Carlos em 07/10, Participante 3 em 02/10, Marina com prazo "não definido".
- Roberto não aparece como participante nem como responsável.
- Marina e Carlos com nome inferido e trecho de evidência. Participante 3 sem nome.
- Todos os IDs citados existem na transcrição (validação por regra).

**Se falhar.** Ajustar o prompt e o esquema. Se `high` for necessário para passar, registrar o custo. Só considerar o Opus 5.5 se o Sonnet falhar em atribuição de responsável depois de dois ajustes de prompt (proposta).

**Resultado (2026-09-30, Sonnet 5.5, esforço `medium`).** Aprovado em 4 dos 5 critérios.
- Ações: 3 corretas. Carlos em 07/10/2026, Participante 3 em 02/10/2026 e Marina com prazo "não definido". O prazo relativo foi convertido usando a data da reunião.
- Roberto não aparece como participante nem como responsável.
- Marina e Carlos com nome inferido e trecho de evidência. Participante 3 sem nome (ver nota sobre Ana no `expected.md`).
- Todos os IDs citados existem na transcrição. Nenhum item apareceu como "sem evidência".
- **Reprovado:** a antecipação para 05/10 apareceu como decisão ("foi descartado"), contra a regra do prompt. É discutível, porque Juliano diz "Antecipar está descartado", mas contraria o critério do plano.
- Observações: 3 pontos em aberto em vez de 1 (os dois extras são plausíveis, mas redundantes com ações). Cada item cita 4 a 7 trechos, o que polui a leitura. Esforço `high` e custo em tokens não foram medidos.
- Amostra em `tools/synthetic-meeting/sample/ata.md`.

**Resultado após ajustar o prompt (2026-09-30).** Aprovado em 5 dos 5 critérios, em 2 execuções completas.
- Mudanças no prompt: no máximo 3 trechos por item; proposta descartada fica fora de "decisões" e entra só no resumo por tema; pontos em aberto não repetem o que já virou ação.
- Nas duas execuções: 2 decisões (lançamento em 15/10 e acompanhamento em 08/10), 3 ações com responsável e prazo corretos e 1 ponto em aberto (tamanho do beta). A antecipação para 05/10 ficou só no resumo por tema.
- Nomes: em uma execução a Ana foi nomeada com base no resumo final do Juliano ("A Ana revisa o orçamento"), marcada como nome inferido; na outra ficou como Participante 3. Ambas aceitáveis (ver `expected.md`).
- Uma terceira execução falhou antes da ata: a camada gratuita do Google limita o `gemini-3.5-transcribe` a 3 pedidos por minuto, e cada reunião usa 2 (um por canal). O app mostrou o erro e a opção "Tentar novamente".
- Não medido: custo em tokens, tempo de execução e esforço `high`.

---

## Teste 6. Voz real com 3 ou mais participantes

**Pergunta.** A diarização e a ata se sustentam com voz real, compressão de videochamada e sobreposição natural?

**Decisão afetada.** ADR 0006 e ADR 0008. É o único teste que o áudio sintético não cobre.

**Passos.**
1. Combinar uma call de 10 a 15 minutos com 2 ou 3 pessoas, com tema não sensível e roteiro solto.
2. Avisar os participantes da gravação e do envio do áudio a serviços externos.
3. Gravar no Zoom com um arquivo de áudio por participante, como referência de quem falou.
4. Gravar também com o método aprovado no teste 1.
5. Repetir os testes 3 e 5 com esse áudio.

**Aprovação.** Os mesmos critérios dos testes 3 e 5, com a referência do Zoom no lugar do gabarito sintético.

**Se falhar.** Medir a taxa de troca e fusão de falantes. Decidir com o usuário se o erro é aceitável para uso próprio.

**Resultado.** Pendente.

---

## Teste 7. Termos de dados dos provedores

**Pergunta.** O que o Google e a Anthropic fazem com o áudio e o texto das reuniões?

**Decisão afetada.** ADR 0008 e ADR 0002. Nenhum dos dois foi lido até agora.

**Passos.** Ler os termos de dados da API do Gemini e da API da Anthropic e registrar:
- se o conteúdo é retido e por quanto tempo;
- se é usado para treinar modelos;
- se plano gratuito e plano pago diferem;
- se existe retenção zero.

**Aprovação.** Decisão do usuário, registrada com link e data da leitura. O critério é de política, não técnico.

**Se falhar.** Sem retenção aceitável, trocar de provedor ou restringir o uso a reuniões sem conteúdo sensível.

**Resultado.** Pendente.

---

## Como os resultados voltam ao projeto

- Cada teste aprovado marca a decisão do ADR como confirmada, com data.
- Cada teste reprovado abre revisão do ADR indicado.
- Números medidos (custo, CPU, memória, erros de diarização) entram no ADR correspondente e no `STATUS.md`.
