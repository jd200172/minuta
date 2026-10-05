# 0028. Aparência: sistema, claro ou escuro

Status: aceita; implementada
Data: 2026-10-05
Complementa: `docs/decisions/0011-minimal-menu-and-install.md` (configurações em página única).

## Contexto

O app segue a aparência do macOS. O usuário pediu escolher claro, escuro ou sistema nas configurações.

## Decisão

Decisão: o bloco Preferências ganha o seletor "Aparência" (Sistema, Claro, Escuro), em controle segmentado, com Sistema como padrão. Motivo: é o controle padrão do macOS para escolha excludente de poucas opções.

A escolha fica em `UserDefaults` (chave `appearance`) e vale para o app inteiro por `NSApp.appearance`. `nil` segue o sistema. Aplica na hora e na inicialização. A página de leitura (`WKWebView`) herda a aparência do app, e o `prefers-color-scheme` do CSS acompanha. A exportação em PDF continua em aparência clara (`Export.swift`).

## Alternativas descartadas

- Aparência por janela: mais código, sem uso que a justifique.
- Menu suspenso: esconde três opções que cabem na linha.

## Consequências

- Forçar um modo diferente do sistema pode afetar o ícone da barra de menus; verificar no app.
- Sem teste automatizado de interface.
