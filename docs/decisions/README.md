# Decisões

Um arquivo por decisão, numerado na ordem em que foi tomada. Decisão substituída continua no repositório como registro; o que vale é a coluna Situação. Onde houver divergência com `docs/project-brief.md`, vale a decisão.

| ADR | Decisão | Situação |
|---|---|---|
| [0001](0001-local-markdown-destination.md) | Atas em Markdown numa pasta local | Em vigor; o 0017 acrescenta o `.resumos.json` |
| [0002](0002-stt-plus-text-llm.md) | STT dedicado e LLM de texto | Em vigor |
| [0003](0003-macos-first.md) | macOS primeiro | Em vigor |
| [0004](0004-two-channel-capture.md) | Captura em dois canais | Em vigor; formato pelo 0009; confirmada pelo 0024 |
| [0005](0005-minutes-structure-and-traceability.md) | Estrutura da ata e rastreabilidade | Rastreabilidade em vigor; prompt e estrutura únicos substituídos pelo 0017 |
| [0006](0006-participant-identification.md) | Identificação de participantes | Em vigor; ampliada pelo 0016; confirmada pelo 0024 |
| [0007](0007-defer-meeting-types-and-notes.md) | Tipos de reunião e notas adiados | Notas continuam adiadas; tipos substituídos pelo 0017 |
| [0008](0008-stt-provider-gemini-transcribe.md) | STT: Gemini 3.5 Transcribe | Em vigor; falta voz real e termos de dados |
| [0009](0009-native-swift-stack.md) | App nativo em Swift, sem dependências | Em vigor; bandeja pelo 0014 |
| [0010](0010-recording-limit-30-minutes.md) | Limite de gravação de 30 minutos | Proposta, aguarda confirmação |
| [0011](0011-minimal-menu-and-install.md) | Menu mínimo, erros por aviso, instalação | Em vigor em parte; chaves pelo 0012, atas pelo 0015, configurações em página única |
| [0012](0012-env-file-and-provider-seams.md) | Chaves no `.env` e provedores trocáveis | Em vigor |
| [0013](0013-pause-resume-end-recording.md) | Pausar, continuar e encerrar | Em vigor; ícones pelo 0014 |
| [0014](0014-colored-menu-bar-states.md) | Estado pela cor do botão da barra de menus | Em vigor (desvio das HIG) |
| [0015](0015-minutes-library.md) | Janela de atas, leitura e nome do arquivo | Em vigor |
| [0016](0016-manual-participant-names.md) | Nomes de participantes dados pelo usuário | Em vigor |
| [0017](0017-summary-models-on-demand.md) | Resumos por tipo de reunião, guardados por modelo | Em vigor; modelos redefinidos pelo 0018; chips de modelo substituídas pelo 0027 (desvio das HIG no balão) |
| [0018](0018-four-summary-models.md) | Quatro modelos de resumo | Em vigor |
| [0019](0019-collapsible-transcript-and-citation-balloons.md) | Transcrição colapsável e balão de citação | Em vigor |
| 0020 | Envio da ata por e-mail | Descartada antes do registro; arquivo removido |
| [0021](0021-echo-removal-in-transcript.md) | Filtro de eco pelo texto da transcrição | Substituída pelo 0024; código retirado |
| [0022](0022-keep-audio.md) | Guardar o áudio de todas as reuniões (na pasta de atas desde 2026-10-02) | Em vigor |
| [0023](0023-echo-cancellation-at-capture.md) | Cancelamento de eco na captura | Em vigor; falta chamada real |
| [0024](0024-follow-market-practice-for-capture.md) | Captura e atribuição pelo padrão de mercado | Em vigor |
| [0025](0025-transcript-correction-window.md) | Janela de correção da transcrição | Em vigor |
| [0026](0026-collapsible-sections-and-retranscribe.md) | Seções colapsáveis e refazer a transcrição | Em vigor |
| [0027](0027-model-menu-section-chips-and-export.md) | Menu de modelo, chips de seção e exportação da ata | Em vigor (desvio das HIG no botão de modelo e nas chips de seção) |

Formato de cada arquivo: título com número, `Status`, `Data`, relação com outras decisões (`Substitui`, `Complementa`, `Confirma`), Contexto, Decisão, Alternativas descartadas e Consequências. Decisão nova recebe o próximo número e uma linha nesta tabela; a substituída tem a linha `Status` atualizada.
