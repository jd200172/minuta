# 0011. Menu mínimo, erros por aviso e instalação em /Applications

Status: aceita; parcialmente substituída pelos ADRs 0012 e 0015 e pela configuração em página única (ver abaixo)
Data: 2026-09-30
Complementa: `docs/decisions/0009-native-swift-stack.md`. Parcialmente substituída pelo ADR 0012 (a aba Chaves de API e o botão Verificar saíram). O item "Abrir pasta de atas" foi substituído pelo ADR 0015. A janela de configurações deixou de ter abas em 2026-10-01: página única com os blocos Chaves e modelos de IA, Permissões (com o teste de captura) e Preferências, sem verde, 640 pt de largura e a versão no rodapé.

## Contexto

O menu da bandeja listava estados e falhas de gravações antigas ("Pronto para gravar", "Falha ao transcrever", "Interrompido antes de terminar", "Tentar novamente"). Uma gravação cortada por uma queda do app deixava uma pasta pendente, e o menu a mostrava a cada abertura. Sem ícone no Dock, não havia como reabrir o app depois de fechá-lo. A janela de configurações era estreita, sem estrutura de abas e sem retorno ao salvar.

## Decisão

**Menu.** Quatro comandos: Iniciar gravação (Parar gravação durante a gravação), Abrir pasta de atas, Configurações… e Sair do minuta. O estado fica no ícone da bandeja (microfone, ponto de gravação, setas de processamento). O fim do processamento é avisado por notificação.

**Erros.** Falhas viram um aviso do macOS com a causa em português, sem texto técnico de API. O aviso oferece "Abrir Configurações" quando a correção está lá (chave ausente ou recusada, permissão).

**Falha no processamento.** O áudio (ou a transcrição) fica guardado e o aviso pergunta: Tentar de novo, Depois ou Descartar. "Depois" mantém a gravação pendente. Ao abrir o app, cada gravação pendente gera um aviso com Processar, Depois ou Descartar.

**Gravação interrompida no meio.** O arquivo `.m4a` é ilegível. O app a descarta ao abrir, sem perguntar.

**Instalação.** `scripts/install.sh` compila, assina e copia o app para `/Applications`. O app continua sem ícone no Dock. Abrir o app já em execução (Spotlight, Applications) abre as configurações. A opção "Abrir ao iniciar o Mac" usa `SMAppService`.

**Configurações.** Janela do AppKit com abas na barra de ferramentas (Geral, Chaves de API, Permissões), 640 pt de largura, alterações aplicadas na hora, sem botão Salvar. Cada chave tem o botão Verificar, que faz uma consulta de leitura ao provedor.

## Consequências

- A cena `Settings` do SwiftUI foi tentada primeiro e descartada: num app sem Dock a janela era criada com tamanho 0 por 0 e não aparecia. A janela do AppKit com `NSTabViewController` em estilo de barra de ferramentas funcionou.
- Quem aperta ⌘Q durante uma gravação a perde. Não há confirmação de saída.
- O "Tentar de novo" só existe dentro do aviso de falha, não no menu.

## Alternativas descartadas

- Descartar o áudio ao falhar: perderia uma reunião inteira por uma falha de rede passageira.
- Mostrar o app também no Dock: ocupa um espaço do Dock o tempo todo.
