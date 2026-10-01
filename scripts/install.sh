#!/bin/bash
# Compila, instala o app em /Applications e o abre.
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build-app.sh
pkill -f "Minuta.app/Contents/MacOS/Minuta" || true
sleep 1
rm -rf /Applications/Minuta.app
ditto build/Minuta.app /Applications/Minuta.app
codesign --verify --strict /Applications/Minuta.app
echo "Instalado: /Applications/Minuta.app"
open /Applications/Minuta.app
