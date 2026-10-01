# Documento de Projeto: Agente de Sumarização de Reuniões (MVP)

> Documento original, mantido como histórico. As decisões em `docs/decisions/` (ADRs 0001 a 0007) prevalecem onde divergem: destino, pipeline de IA, plataformas, captura, estrutura da ata, participantes, e tipos de reunião e notas adiados.

## 1. Escopo e Restrições

* Plataformas Suportadas: Windows (10/11) e macOS (13+).
* Interface de Usuário (UI): Aplicação executada exclusivamente na bandeja do sistema (System Tray). Sem interface de janela contínua. Contém apenas um menu de contexto para ações rápidas, uma janela de formulário nativa para entrada de configurações e uma barra efêmera para inserção de notas.
* Restrição de Captura (Hard Limit): O tempo de gravação ininterrupta é limitado a 60 minutos. Atingido o teto de 1 hora, o sistema intercepta o áudio, encerra a captura automaticamente e inicia a requisição para a IA, evitando estouro de limite de payload, falhas de alocação de memória ou rejeição pela API.
* Personalização de Contexto: O menu do System Tray exibe categorias de reunião predefinidas no momento do disparo (ex: 1-a-1, Sincronização Diária, Sessão de Brainstorming) que alteram dinamicamente a instrução base (system prompt) enviada ao motor de sumarização.

## 2. Arquitetura e Stack Definitiva

* Motor da Aplicação: Python com a biblioteca `pystray` (para gestão do ícone e menu na bandeja) e `customtkinter` (para renderizar exclusivamente a tela de configurações de credenciais).
* Captura de Áudio: `sounddevice` operando em WASAPI (Windows) e via ScreenCaptureKit ou driver virtual (macOS). A gravação unifica microfone e saída do sistema em um arquivo temporário leve (`.m4a` ou `.ogg`).
* Processamento de IA: API de um provedor de LLM (Large Language Model) multimodal. O modelo recebe o áudio bruto e o array de anotações manuais no mesmo prompt.
* Persistência: API do Notion (ou Supabase REST API). Apenas os derivativos textuais formatados em Markdown são transmitidos e armazenados na nuvem.

## 3. Máquina de Estados e Fluxo de Execução

* Estado Ocioso: Ícone neutro na bandeja. Módulo de áudio desativado.
* Estado Gravando: O usuário clica no ícone e seleciona "Iniciar > [Categoria]". A captura local é iniciada para o diretório temporário do SO (`/tmp` ou `%TEMP%`). O ícone alterna para a cor vermelha.
* Estado de Intervenção (Nota): O usuário clica em "Inserir Nota" no menu (ou utiliza o atalho de teclado em redundância). A barra de comando sobrepõe a tela, captura a palavra-chave, acopla o timestamp no array em memória e fecha instantaneamente.
* Estado Processando: O usuário seleciona "Parar e Gerar Ata" (ou o cronômetro atinge 60 minutos). A gravação cessa. O arquivo de áudio e as notas são enviados para a API de inteligência artificial. O ícone alterna para amarelo indicando atividade de rede.
* Estado Sincronizando e Limpeza: O payload JSON retornado pela IA é enviado via requisição HTTP POST para o banco de dados final. Mediante confirmação de sucesso (Status 200 OK) da nuvem, a aplicação executa um comando de exclusão (`os.remove()`) no arquivo de áudio local. O ícone retorna ao estado ocioso.

## 4. Contratos de Dados (Data Contracts)

* Formulário de Configurações (Armazenamento Local Criptografado):
   * `LLM_API_KEY`: Chave de autenticação do provedor de inteligência artificial.
   * `DESTINATION_API_KEY`: Chave da base de dados em nuvem.
   * `TARGET_DATABASE_ID`: Identificador da tabela de destino.
* Payload de Sincronização (Envio para a Nuvem):

```json
{
  "data_hora_execucao": "2026-10-01T14:00:00Z",
  "categoria_selecionada": "Sessão de Brainstorming",
  "notas_contextuais": ["falado sobre token limit", "ideia de usar supabase"],
  "ata_markdown": "# Resumo Executivo\n...\n## Itens de Ação\n...",
  "transcricao_bruta": "Participante 1: Vamos iniciar a análise..."
}
```

## 5. Mitigação de Riscos Técnicos

* Falha de Rede / Timeout de API: Se a requisição para o LLM ou para o banco de dados falhar, o script bloqueia a execução da limpeza local. O arquivo de áudio temporário é mantido em disco e o ícone altera para um estado de "Falha", habilitando uma opção "Tentar Novamente" no menu suspenso para reprocessar o cache sem perda de dados.
* Desconexão Abrupta de Hardware: Caso o dispositivo de saída (ex: monitor com alto-falante) ou fone de ouvido Bluetooth seja desconectado antes do limite de 1 hora, o script deve capturar a exceção de perda de stream de áudio, fechar o buffer de gravação atual com um cabeçalho válido (impedindo a corrupção do arquivo) e encerrar a gravação de forma controlada.
