# 0003. Plataformas do MVP: macOS primeiro

Status: aceita
Data: 2026-09-30
Substitui: seção 1 (Plataformas Suportadas) de `docs/project-brief.md`.

## Contexto

O brief incluía Windows 10/11 e macOS 13+ no MVP. A captura de áudio do sistema difere por plataforma. No macOS exige ScreenCaptureKit (permissão de Gravação de Tela) ou driver virtual instalado pelo usuário. No Windows exige loopback WASAPI, que o `sounddevice` não expõe. O desenvolvimento ocorre em macOS.

## Decisão

O MVP cobre macOS 13+. Windows 10/11 entra em fase posterior. A captura fica atrás de uma interface por plataforma.

## Consequências

- O risco técnico mais alto (captura no macOS) é resolvido primeiro e pode ser testado no ambiente de desenvolvimento.
- Empacotamento e permissões se validam numa plataforma antes da segunda.
- A interface de captura precisa existir desde o início para o Windows não exigir refatoração.

## Alternativas descartadas

- Windows primeiro: sem ambiente de teste e com o risco do macOS adiado.
- As duas plataformas no MVP: dobra captura, permissões e empacotamento antes de validar o fluxo.
