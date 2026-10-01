# 0009. Stack: app nativo em Swift, sem dependências externas

Status: aceita
Data: 2026-09-30
Substitui: stack Python do brief (`pystray`, `customtkinter`, `sounddevice`) e o formato de arquivo do ADR 0004 (Ogg/Opus em um arquivo de dois canais).

## Contexto

O usuário pediu a solução mais simples possível, com o menor consumo de recursos, e delegou a escolha da stack. Com macOS como única plataforma do MVP (ADR 0003), a razão do Python no brief, multiplataforma, deixa de valer. O ambiente tem Swift 6.4 e Xcode 27.

Problemas do Python para este caso:
- O áudio do sistema no macOS só vem por ScreenCaptureKit, que em Python exige `pyobjc`.
- `pystray` e `customtkinter` disputam a thread principal no macOS.
- Empacotar e assinar um app Python com permissões de microfone e de gravação de tela é mais frágil.
- Exige runtime, ambiente virtual e uma lista de dependências de terceiros.

## Decisão

App nativo em Swift, como pacote SwiftPM, sem dependências de terceiros.

- Interface: SwiftUI `MenuBarExtra` para a bandeja e uma `Window` para as configurações. Sem ícone no Dock (`LSUIElement`).
- Captura: ScreenCaptureKit para o áudio do sistema e `AVAudioEngine` para o microfone. Cada canal vai para um arquivo mono separado.
- Formato: AAC em `.m4a`, 16 kHz mono, 32 kbps (cerca de 14 MB por hora por canal). O AVFoundation codifica nativamente, sem biblioteca externa. O Gemini aceita `audio/m4a`.
- Credenciais: Keychain pela API Security.
- Rede: `URLSession` direto para as APIs do Google (Files e Interactions) e da Anthropic (Messages). A Anthropic não tem SDK oficial em Swift.
- Jobs pendentes: em `~/Library/Application Support/Minuta/pending/`, não no diretório temporário do SO, para sobreviver a reinício.
- Build: `scripts/build-app.sh` monta o `.app` a partir do SwiftPM, sem projeto Xcode, e assina de forma ad hoc.

## Consequências

- Um só binário, sem runtime. Memória medida em repouso: cerca de 79 MB de RSS e 0% de CPU, o piso de um app SwiftUI.
- O arquivo `.m4a` não é legível se o app travar no meio da gravação, porque o índice só é escrito ao fechar. Ogg toleraria isso. O app trata perda de stream (fone desconectado, parada do ScreenCaptureKit) fechando os arquivos, mas uma queda do processo perde aquela gravação. Aceito no MVP.
- Assinatura ad hoc muda a identidade do binário a cada build. O macOS pode pedir as permissões de novo, e o Keychain pode pedir autorização a cada build. Um certificado de desenvolvimento estável resolve; não há nenhum instalado neste Mac.
- O Windows exigiria um segundo app. Está fora do escopo do MVP.
- Não há teste de captura automatizado: depende de permissões do macOS concedidas por uma pessoa.

## Alternativas descartadas

- Python com `pystray`, `pyobjc` e `customtkinter`: mais dependências, mais memória, empacotamento frágil e sem ganho com uma só plataforma.
- Híbrido (Python com auxiliar em Swift para captura): soma dois ambientes para o mesmo resultado.
