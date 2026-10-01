#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release
APP="build/Minuta.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/Minuta "$APP/Contents/MacOS/Minuta"
cp Resources/Info.plist "$APP/Contents/Info.plist"
codesign --force --sign - --identifier app.minuta.Minuta "$APP"
echo "Gerado: $APP"
