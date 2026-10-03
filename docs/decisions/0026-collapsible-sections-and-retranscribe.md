# 0026. Seções colapsáveis e refazer a transcrição

Status: aceita; implementada
Data: 2026-10-02
Complementa: `docs/decisions/0019-collapsible-transcript-and-citation-balloons.md` e `docs/decisions/0022-keep-audio.md`.

## Contexto

O ADR 0019 tornou colapsável só a transcrição. As demais seções da ata ocupam a página inteira, mesmo quando o usuário procura uma só. São elas: resumo, participantes, seções do modelo, itens de ação e pontos em aberto. Separadamente, com o áudio guardado (ADR 0022), a transcrição pode ser refeita quando sai ruim, sem regravar.

## Decisão

**Seções colapsáveis.** Todo título `##` da janela de leitura é um alternador (`minuta://section/<título>`), com o chevron da transcrição. O estado fica por reunião (chave `inicio`) em `UserDefaults`, por título de seção. Tudo abre expandido, exceto a transcrição, que continua abrindo recolhida e mantém o estado do ADR 0019. Os subtítulos `###` (temas) acompanham a seção. O arquivo `.md` não muda.

**Refazer a transcrição.** Botão na barra da janela de leitura, ao lado de "Corrigir a transcrição". Fica ativo só quando a ata tem arquivo secundário e pelo menos um arquivo de áudio guardado na pasta de atas. Fica inativo durante um resumo ou outra transcrição da mesma ata.
- Pede confirmação antes, porque a operação é destrutiva e gera custo de STT.
- Transcreve de novo os arquivos guardados, com os mesmos deslocamentos (`audio_offsets`; zero em ata sem eles) e a mesma regra de menos de 10 palavras. Canal sem arquivo é omitido.
- Substitui `segments` no secundário. Descarta as correções (`originals`) e os nomes dados aos participantes, porque os trechos e os rótulos da diarização podem não corresponder aos antigos. Mantém título, classificação, modelo escolhido e resumos.
- Marca todos os resumos existentes como desatualizados (`outdated`), como em qualquer correção (ADR 0025). Os IDs que eles citam podem não existir na nova transcrição; a ata mostra "sem evidência na transcrição" nesses casos até o resumo ser refeito.
- Em falha (rede, chave, sem fala), a transcrição atual fica como está e um aviso mostra o motivo.

## Alternativas descartadas

- Guardar a transcrição anterior para desfazer: dobra o tamanho do secundário e a janela de correção já guarda o original de cada fala corrigida. O usuário confirma a substituição.
- Manter correções e nomes sobre a nova transcrição: exigiria casar falas e vozes entre duas transcrições, o que o ADR 0024 evita.
- Refazer também os resumos: custo de uma chamada ao LLM por modelo, sem o usuário pedir; o ícone de refazer da página já cobre.

## Consequências

- Chamada de STT a cada uso do botão, nos dois canais.
- A janela de correção e a página de leitura recarregam pela notificação `.ataChanged`.
- Nova peça: `Retranscriber` (`Sources/Minuta/Retranscriber.swift`); `Pipeline.transcribe` passa a aceitar URLs de arquivo.
