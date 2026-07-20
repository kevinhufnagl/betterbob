#!/bin/bash
# One-time setup: create the self-signed "BetterBob Signing" certificate in the
# login keychain. build.sh prefers this identity over ad-hoc signing — a stable
# certificate keeps the app's code-signing requirement identical across builds,
# so users' Keychain ("Always Allow") and Location grants survive updates
# instead of re-prompting after every release.
#
# Run this interactively (it needs your password once, to mark the certificate
# trusted for code signing):
#   ./Scripts/make-signing-cert.sh
set -euo pipefail

NAME="BetterBob Signing"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
  echo "'$NAME' already exists in the keychain — nothing to do."
  exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/ext.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = v3
prompt = no
[dn]
CN = $NAME
[v3]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:false
EOF

echo "==> Generating key + certificate (valid 10 years)"
openssl req -x509 -newkey rsa:2048 -days 3650 -nodes \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/ext.cnf" 2>/dev/null

openssl pkcs12 -export -name "$NAME" -passout pass:betterbob \
  -inkey "$TMP/key.pem" -in "$TMP/cert.pem" -out "$TMP/cert.p12"

echo "==> Importing into the login keychain"
security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
  -P betterbob -T /usr/bin/codesign

echo "==> Trusting it for code signing (macOS asks for your password here)"
security add-trusted-cert -p codeSign \
  -k "$HOME/Library/Keychains/login.keychain-db" "$TMP/cert.pem"

echo ""
echo "Done — build.sh and release.sh will now sign as '$NAME'."
echo "Users get one final permission re-prompt on the first update with this"
echo "signature; after that, grants survive every release."
