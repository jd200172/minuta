# 0006. Identificação de participantes

Status: aceita
Data: 2026-09-30
Complementa: `docs/decisions/0004-two-channel-capture.md`.

## Contexto

O app atende reuniões virtuais. Nelas, o canal do microfone contém só o usuário, e os demais participantes chegam pelo áudio do sistema. Tratar todos os demais como um bloco único mistura falantes e impede atribuir decisões e responsáveis.

## Decisão

- Canal do microfone: rótulo com o nome configurado em "Seu nome" nas configurações. Com o campo vazio, o rótulo é "Eu".
- Canal do sistema: diarização pelo STT, com rótulos "Participante 1", "Participante 2" etc., estáveis ao longo da reunião.
- Nunca agrupar participantes num rótulo coletivo ("Outros", "Demais", "Convidados"). Cada voz distinta tem um rótulo próprio.
- Substituição por nome: o LLM propõe o nome de um participante quando a transcrição o identifica (saudação, apresentação, vocativo). Cada substituição cita os IDs de segmento que a sustentam. Sem evidência, o rótulo "Participante N" permanece.
- O nome inferido aparece marcado como tal na seção Participantes, com a origem da evidência.
- Reuniões presenciais e híbridas estão fora do escopo: nelas o microfone captaria mais de uma voz, e o rótulo do usuário absorveria os demais.

## Consequências

- O provedor de STT precisa oferecer diarização no canal do sistema, além de multicanal e timestamps por segmento.
- A diarização erra em voz parecida, sobreposição de fala e participantes que compartilham o mesmo dispositivo de áudio. O resultado pode trocar ou fundir falantes. Responsável e prazo herdam esse erro.
- Nome inferido errado atribui ação à pessoa errada. Por isso a substituição exige evidência citada e fica sinalizada na ata.
- Dois participantes remotos que falam pelo mesmo dispositivo (sala de conferência) aparecem como uma só voz.
- O número de participantes é desconhecido de antemão e vem da diarização.
- As configurações ganham o campo "Seu nome".

## Alternativas descartadas

- "Outros" como bloco único: mistura falantes e impede responsável por ação.
- Lista de participantes informada pelo usuário ao gerar a ata: custo de interação e nenhum ganho de alinhamento com a voz.
- Rótulo fixo "Você" ou "Eu": ambíguo em ata compartilhada.
- Diarização também no canal do microfone: só se justifica em reunião presencial, fora do escopo.
