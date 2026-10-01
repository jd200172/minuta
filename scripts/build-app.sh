#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Minuta.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Minuta "$APP/Contents/MacOS/Minuta"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

KC="$HOME/Library/Keychains/minuta-dev.keychain-db"
NAME="Minuta Dev"
if [ -f "$KC" ] && security find-identity -p codesigning "$KC" | grep -q "$NAME"; then
  security unlock-keychain -p "" "$KC"
  codesign --force --sign "$NAME" --keychain "$KC" --identifier app.minuta.Minuta "$APP"
else
  echo "Aviso: sem identidade estável. Rode scripts/setup-signing.sh. Com assinatura ad hoc, o macOS pede as permissões de novo a cada build."
  codesign --force --sign - --identifier app.minuta.Minuta "$APP"
fi
echo "Gerado: $APP"
