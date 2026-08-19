#!/usr/bin/env bash
# One-time: create a self-signed code-signing certificate in the login
# keychain, so the app keeps ONE identity across rebuilds.
#
# Why: ad-hoc signing (codesign -s -) bakes a fresh cdhash into the app on
# every build. TCC keys the Accessibility grant on the signing identity, so
# each rebuild looked like a brand-new app and macOS revoked the grant —
# hence the endless "would like to control this computer" prompts. With a
# certificate, the identity is the cert, which never changes.
set -euo pipefail

# The certificate keeps its original label from before the project was renamed
# to f1-claude-pet: the CN is cosmetic, and replacing the cert would create a
# new code identity — dropping the Accessibility grant it exists to preserve.
NAME="F1DockPet Dev"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning 2>/dev/null | grep -q "$NAME"; then
    echo "signing identity '$NAME' already exists — nothing to do"
    exit 0
fi

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# LibreSSL-safe: extensions via config file rather than -addext.
cat > "$TMP/ext.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
basicConstraints = critical,CA:FALSE
EOF

openssl req -newkey rsa:2048 -nodes -keyout "$TMP/key.pem" \
    -x509 -days 3650 -config "$TMP/ext.cnf" -out "$TMP/cert.pem" 2>/dev/null

openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -passout pass:f1dockpet -out "$TMP/cert.p12"

# -T pre-authorises codesign to use the key.
security import "$TMP/cert.p12" -k "$KEYCHAIN" -P f1dockpet -T /usr/bin/codesign

# Trust it for code signing (user domain — may pop a dialog to confirm).
security add-trusted-cert -p codeSign -k "$KEYCHAIN" "$TMP/cert.pem" \
    || echo "note: approve the trust dialog if one appeared"

echo "created:"
security find-identity -v -p codesigning | grep "$NAME" || true
