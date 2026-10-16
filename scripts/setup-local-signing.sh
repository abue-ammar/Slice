#!/bin/zsh
#
#  setup-local-signing.sh
#  Scripts
#
#  Created by rit3zh CX on 10/12/26.
#

# Signs local builds with a stable self-signed certificate instead of ad hoc, so macOS keeps Screen Recording,
# Camera and Microphone permissions across rebuilds (ad-hoc builds get a new signature, and so lose them, every time).
# Safe to run again: an existing certificate is reused. Not for distribution; use a Developer ID for that.
set -euo pipefail

NAME="Slice Local Signing"
ROOT="${0:A:h}/.."
CONFIG="$ROOT/Config/Signing.local.xcconfig"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if ! security find-certificate -c "$NAME" "$KEYCHAIN" >/dev/null 2>&1; then
    tmp=$(mktemp -d)
    trap 'rm -rf "$tmp"' EXIT
    cat > "$tmp/cert.cnf" <<EOF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature
extendedKeyUsage = critical, codeSigning
EOF
    openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$tmp/cert.cnf" \
        -keyout "$tmp/key.pem" -out "$tmp/cert.pem" 2>/dev/null
    openssl pkcs12 -export -inkey "$tmp/key.pem" -in "$tmp/cert.pem" -out "$tmp/id.p12" -passout pass:local
    security import "$tmp/id.p12" -k "$KEYCHAIN" -P local -T /usr/bin/codesign
    echo "Trusting the certificate for code signing (macOS may ask for your password)..."
    security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" "$tmp/cert.pem"
    echo "Created \"$NAME\" in your login keychain."
fi

if [[ -f "$CONFIG" ]] && ! grep -q "Written by scripts/setup-local-signing.sh" "$CONFIG"; then
    echo "$CONFIG already exists with other settings; leaving it alone." >&2
    exit 1
fi
cat > "$CONFIG" <<EOF
// Written by scripts/setup-local-signing.sh (ignored by git).
// A stable identity keeps macOS privacy permissions across rebuilds.
DEVELOPMENT_TEAM =
CODE_SIGN_IDENTITY = $NAME
// A self-signed identity has no Team ID, so the hardened runtime refuses to load Xcode's separate Debug dylib.
ENABLE_DEBUG_DYLIB = NO
EOF
echo "Wrote ${CONFIG:A}. Build as usual; grant Screen Recording once more and it will stick."
