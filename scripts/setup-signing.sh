#!/bin/bash
# Cria uma identidade de assinatura local e estável, num chaveiro separado do seu chaveiro de login.
# Com ela, o macOS reconhece o app como o mesmo a cada build e não pede as permissões de novo.
set -euo pipefail
KC="$HOME/Library/Keychains/minuta-dev.keychain-db"
NAME="Minuta Dev"

if [ -f "$KC" ] && security find-identity -p codesigning "$KC" | grep -q "$NAME"; then
  echo "Identidade \"$NAME\" já existe."
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cat > "$tmp/cert.conf" <<CONF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CONF
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.conf" \
  -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -name "$NAME" \
  -out "$tmp/cert.p12" -passout pass:minuta

[ -f "$KC" ] || security create-keychain -p "" "$KC"
security set-keychain-settings "$KC"
security unlock-keychain -p "" "$KC"
security import "$tmp/cert.p12" -k "$KC" -P minuta -T /usr/bin/codesign >/dev/null
security set-key-partition-list -S apple-tool:,apple: -s -k "" "$KC" >/dev/null
echo "Identidade \"$NAME\" criada em $KC."
