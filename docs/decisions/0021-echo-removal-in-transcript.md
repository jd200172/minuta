# 0021. Remoção do eco do microfone na montagem da transcrição

Status: substituída pelo `docs/decisions/0024-follow-market-practice-for-capture.md` em 2026-10-02; o filtro e a seção de eco foram retirados do código
Data: 2026-10-02
Complementa: `docs/decisions/0004-two-channel-capture.md` e `docs/decisions/0006-participant-identification.md`.

## Contexto

Em chamada com o alto-falante ligado, o microfone capta a voz dos outros participantes. O app transcreve os dois canais por separado, então a mesma fala sai duas vezes: limpa no canal do sistema ("Participante N") e abafada, com palavras trocadas, no canal do microfone, sob o nome do usuário. Na reunião de 2026-10-01 às 19:06, cerca de um terço das palavras do canal do microfone (palavras de 5 letras ou mais) tinham cópia no canal do sistema nos 15 s ao redor, contra 1% a 3% ao deslocar os tempos (acaso). O resumo atribuiu falas da outra pessoa ao usuário. O ADR 0004 já previa tratar o eco comparando os canais; não havia sido feito.

## Decisão

`EchoFilter` remove do canal do microfone, antes de agrupar as falas, as palavras que repetem o canal do sistema:
- Uma palavra do microfone é candidata quando o canal do sistema tem uma palavra igual (ou, de 5 letras em diante, com uma letra de diferença) até 3 s antes ou depois, já com os deslocamentos de cada canal. Palavras com menos de 3 letras nunca são candidatas.
- A palavra é eco quando a janela de 3 palavras para cada lado tem pelo menos 3 candidatas e pelo menos 50% das palavras da janela. Isso leva junto as palavras que o modelo ouviu errado na cópia abafada e deixa passar coincidências curtas ("pode ser" dos dois lados).
- Uma palavra vizinha (até 2 posições) de um trecho de eco que também existe no canal do sistema, mesmo curta, é eco: o trecho não deixa "Então o" para trás.
- Se todas as palavras do microfone são eco, o microfone não gera segmento (o texto corrido, que também é eco, não substitui as palavras). Sem palavras com tempo no microfone, ou sem palavras no sistema, nada é removido.

**Nada some em silêncio** (atualização de 2026-10-02). O que o filtro retira da transcrição não é apagado: o app o guarda como trechos de eco (`Transcript.echoes`, ids `e-<segundos>`, com o rótulo do microfone) no arquivo secundário (`echoes`, ausente nas atas anteriores). A ata ganha, depois da transcrição, a seção "Eco do microfone", com uma nota e as falas retiradas; a página de leitura a mostra recolhida (`<details>`), com a contagem de trechos. O eco não conta como segmento, não é alvo de citação e não entra no pedido dos resumos. Restaurar um trecho de eco que não era eco (falso positivo) fica para a janela de correção.

Calibragem: os limiares saíram de um protótipo sobre a reunião real, com tempos de palavra estimados a partir dos segmentos (o áudio e os tempos reais foram descartados). Nessa estimativa o filtro remove 18% das palavras do microfone e reduz o vazamento restante de 34% para 17%. Com os tempos reais de cada palavra o resultado deve ser melhor, e os limiares precisam de nova conferência numa gravação real.

## Consequências

- Fala do usuário que repete, em até 3 s, 4 ou mais palavras ditas pelo outro lado também é removida. É o custo de não depender do áudio.
- O eco que o modelo transcreveu de forma muito diferente do canal do sistema não é pego.
- Atas já geradas não mudam: a transcrição guardada não tem os tempos das palavras. Só gravações novas passam pelo filtro.
- O cancelamento de eco no microfone (voz processada do macOS) e o uso de fone continuam sendo as correções na origem; este filtro as complementa e não as substitui.
- Testes: `EchoFilterTests` (eco removido, fala do usuário mantida, palavra mal ouvida, coincidência isolada, palavras curtas, tempos distantes, deslocamentos, canal do sistema vazio, montagem da transcrição).
