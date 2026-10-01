# 0012. Chaves em arquivo `.env` e provedores trocáveis

Status: aceita
Data: 2026-10-01
Substitui, em parte: `docs/decisions/0011-minimal-menu-and-install.md` (aba "Chaves de API" e Keychain).

## Contexto

O Keychain pedia autorização para ler as chaves a cada versão do app. A autorização vale para a assinatura do código que criou o item, e qualquer build com outra assinatura (ad hoc, debug, `swift run`) reabre o aviso. O app é de uso próprio, num Mac de um usuário só. Além disso, o Gemini (transcrição) e o Claude (ata) estavam fixos no código, e o usuário quer poder trocar de modelo no futuro.

## Decisão

**Chaves e escolhas em arquivo.** `~/Library/Application Support/Minuta/.env`, permissão `600`, formato `NOME=valor`:

```
GOOGLE_API_KEY=
ANTHROPIC_API_KEY=
TRANSCRIBER=gemini
TRANSCRIBER_MODEL=gemini-3.5-transcribe
MINUTER=claude
MINUTER_MODEL=claude-sonnet-5-5
```

O app lê o arquivo a cada uso, então editar dispensa reiniciar. Na primeira abertura sem o arquivo, o app o cria e copia as chaves que estiverem no Keychain (serviço `app.minuta.Minuta.keys`); só depois de gravar o arquivo apaga os itens do Keychain. Chave ausente ou recusada gera um aviso com "Abrir arquivo de chaves". As configurações têm uma linha "Chaves e modelos de IA" com o botão que abre o arquivo no TextEdit. A aba "Chaves de API" e o botão Verificar foram removidos.

**Provedores atrás de dois protocolos.** `Transcriber` (áudio em palavras com tempo e falante) e `Minuter` (transcrição em `MinutesData`). `Providers` escolhe a implementação pelo `.env`. Hoje: `gemini` e `claude`. Provedor novo entra quando for necessário, como um struct novo e um `case` na fábrica.

**Regras dos modelos.** O prompt, o schema JSON e a decodificação da ata ficam em `MinutesPrompt`, neutros em relação ao provedor. Cada adaptador só trata do transporte e do mecanismo de saída estruturada do seu provedor. A validação continua no app (`TranscriptBuilder`, `MinutesRenderer`): IDs inexistentes viram "sem evidência na transcrição". O prompt reduz erros; a validação os impede de chegar na ata.

**Teste de conformidade.** Um provedor novo roda uma vez sobre a reunião sintética (`tools/synthetic-meeting/`) e é comparado com `expected.md` antes do uso.

## Consequências

- A chave fica em texto puro: qualquer processo do usuário a lê e o Time Machine a copia. O risco é aceito num Mac de uso pessoal. A regra do `AGENTS.md` sobre credenciais mudou.
- O aviso do Keychain deixa de existir. A migração lê o Keychain uma vez e pode gerar o aviso nessa leitura.
- Um STT novo precisa entregar palavras com tempo e, no canal do sistema, rótulo de falante, ou ganhar um adaptador que converta. Um LLM novo precisa de saída estruturada equivalente.
- A chave de um provedor sem adaptador não tem efeito: o nome em `TRANSCRIBER`/`MINUTER` precisa existir na fábrica.

## Alternativas descartadas

- Manter o Keychain e corrigir a ACL: funciona enquanto a assinatura não muda, mas o aviso volta em qualquer build fora do `install.sh`.
- Variáveis de ambiente do processo: app aberto pelo Finder não herda as do shell.
- Configuração dos provedores na janela de configurações: mais interface para algo que muda raramente.
