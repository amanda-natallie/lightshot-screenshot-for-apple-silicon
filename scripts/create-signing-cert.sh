#!/usr/bin/env bash
# Creates a self-signed code-signing certificate in the login keychain so local builds keep a stable
# signature (macOS ties the Screen Recording permission to it). Local use only; not valid for distribution.
# Remove later in Keychain Access. Usage: scripts/create-signing-cert.sh ["Certificate Name"]
set -euo pipefail
NAME=${1:-Shotmark Local Signing}
if security find-identity -p codesigning | grep -qF "\"$NAME\""; then echo "\"$NAME\" already exists"; exit 0; fi
D=$(mktemp -d); trap 'rm -rf "$D"' EXIT
cat > "$D/cfg.cnf" <<CNF
[req]
distinguished_name=dn
x509_extensions=ext
prompt=no
[dn]
CN=$NAME
[ext]
basicConstraints=critical,CA:false
keyUsage=critical,digitalSignature
extendedKeyUsage=critical,codeSigning
CNF
PASS=$(openssl rand -hex 16)
openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -keyout "$D/key.pem" -out "$D/cert.pem" -config "$D/cfg.cnf" 2>/dev/null
openssl pkcs12 -export -inkey "$D/key.pem" -in "$D/cert.pem" -out "$D/id.p12" -passout "pass:$PASS" -name "$NAME"
security import "$D/id.p12" -k ~/Library/Keychains/login.keychain-db -P "$PASS" -T /usr/bin/codesign
echo "Created \"$NAME\". On the first build, allow codesign to use the key (\"Always Allow\")."
