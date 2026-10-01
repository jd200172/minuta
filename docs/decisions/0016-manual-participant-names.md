# 0016. Nomes de participantes informados pelo usuário

Status: aceita; implementada
Data: 2026-10-01
Complementa: `docs/decisions/0006-participant-identification.md`.

## Contexto

A diarização separa as vozes, mas só o texto da conversa dá os nomes, e muitas vezes ele não aparece. A ata ficava com "Participante N" sem como corrigir.

## Decisão

**Edição na janela de leitura, uma voz por vez.** Na lista "Participantes", cada voz (inclusive o canal do microfone) tem um lápis discreto, que fica azul ao passar o mouse e tem a dica "Renomear". Clicar nele transforma o nome num campo no mesmo lugar, como o rename do Finder: Return salva, Esc cancela, clicar fora salva se o nome for válido. O campo não traz texto de ajuda; só aparecem, ao lado dele, os erros (nome repetido, caractere inválido), em vermelho, e o Return não salva. Apagar o nome e confirmar volta ao rótulo. Salvar regrava o `.md` e recarrega a página, mantendo a rolagem.

**A página continua sem JavaScript.** O lápis é um link especial (`minuta://rename/N`) que o app intercepta. O app pergunta à página onde o nome está, com um comando fixo que só leva um número, e põe um campo de texto nativo, sobre um fundo opaco, exatamente em cima do nome. Rolar ou redimensionar a janela com o campo aberto cancela a edição, porque o campo deixaria de acompanhar o texto. Uma primeira versão, com uma folha única para todos os participantes aberta por um botão da barra de título, foi descartada pelo usuário por ser invasiva.

**O nome informado é fato, só naquela ata.** O rótulo é numerado por reunião, então um nome nunca vale para outras atas. Dentro da ata, o nome substitui o rótulo em todo o texto: lista de participantes, resumo, decisões, temas, tabela de ações e transcrição, sem repetir o rótulo entre parênteses. Na lista de participantes, a linha fica só com o nome, sem anotação ("- Marina"); o nome inferido pelo modelo continua marcado "nome inferido em [horário]" e "(sem nome identificado)" continua nos participantes sem nome. A linha do canal do microfone também é só o nome (o rótulo é o nome das configurações, então a anotação "(canal do microfone)" que as atas tinham foi retirada, a pedido do usuário). O editor reconhece a voz do microfone por não ser "Participante N": ao apagar o nome, "Participante N" volta com "(sem nome identificado)" e a voz do microfone volta como linha simples.

**Registro e desfazer.** O cabeçalho do arquivo ganha `participantes: {"Participante 2": "Marina"}`. É por ele que o rótulo original fica registrado no cabeçalho e que apagar o nome volta ao rótulo (troca o nome de volta em todo o texto). Voltar a um rótulo remove a entrada. Um nome inferido pelo modelo pode ser corrigido na mesma folha; apagá-lo volta ao rótulo.

**Dois participantes não podem ter o mesmo nome** na mesma ata, sem diferenciar maiúsculas, minúsculas e acentos, nem usar o rótulo de outra voz. Juntar duas vozes numa só fica para depois.

**Nomes aceitos:** até 60 caracteres, letras, números, espaço, ponto, hífen e apóstrofo. Isso evita caracteres que quebrariam a tabela ou o Markdown.

**Troca por palavra inteira.** "Participante 1" não altera "Participante 10". A troca passa por marcadores privados, para o novo nome de uma voz nunca ser trocado como nome antigo de outra.

## Consequências

- Os artigos do texto do modelo não são corrigidos: "O Participante 1 respondeu" vira "O Marina respondeu". Só regenerar o resumo com os nomes resolveria, e isso fica fora desta etapa.
- Desfazer troca o nome de volta em todo o texto. Se a ata já tinha o mesmo nome escrito por outro motivo, ele também muda; a dica ao lado do campo avisa quando o nome já aparece no texto.
- Atas antigas guardam "(canal do microfone)" na linha do usuário; a anotação some quando essa linha é editada, e as demais linhas ficam como estão.
- Atas editadas à mão fora do formato do app podem não ser reconhecidas pela folha; nesse caso ela mostra o que conseguir ler.
- Regra do `AGENTS.md` alterada: o nome informado pelo usuário vale como evidência, só na própria ata.

## Alternativas descartadas

- Manter o rótulo entre parênteses depois do nome: repete a informação.
- Sobrepor os nomes só na janela de leitura, sem mexer no arquivo: outros programas continuariam vendo os rótulos.
- Propagar o nome para outras atas: o rótulo muda de reunião para reunião.
- Edição por um campo dentro da página: exigiria ligar o JavaScript da janela de leitura.
- Folha única com todos os participantes, aberta por um botão da barra de título: o usuário a achou abrangente e invasiva.
