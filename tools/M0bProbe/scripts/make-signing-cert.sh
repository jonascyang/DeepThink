#!/bin/zsh
# Creates the fixed self-signed code-signing certificate "ThinkMyDay Local Signing" and
# imports it into your login keychain. Run it yourself once: macOS will ask for your password
# when the certificate is marked as trusted for code signing.
#
# Files go to <repo>/signing-local/ (git-ignored). Never commit them.
set -euo pipefail

NAME="ThinkMyDay Local Signing"
OPENSSL=/usr/bin/openssl   # system LibreSSL: its .p12 output imports cleanly into the keychain
DIR="$(cd "$(dirname "$0")/../../.." && pwd)/signing-local"
KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

if security find-identity -v -p codesigning | grep -q "\"$NAME\""; then
  echo "Certificate \"$NAME\" already exists; nothing to do."
  exit 0
fi

mkdir -p "$DIR"
chmod 700 "$DIR"
cd "$DIR"

cat > cert.cnf <<EOF
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
EOF

$OPENSSL req -x509 -newkey rsa:2048 -nodes -days 3650 -config cert.cnf -keyout key.pem -out cert.pem
P12_PASS=$($OPENSSL rand -hex 12)
$OPENSSL pkcs12 -export -inkey key.pem -in cert.pem -name "$NAME" -out cert.p12 -passout "pass:$P12_PASS"

security import cert.p12 -k "$KEYCHAIN" -P "$P12_PASS" -T /usr/bin/codesign
security add-trusted-cert -r trustRoot -p codeSign -k "$KEYCHAIN" cert.pem
rm -f key.pem cert.p12

echo
security find-identity -v -p codesigning | grep "$NAME"
echo "Done. Build with:  SIGN_IDENTITY=\"$NAME\" ./scripts/build-app.sh"
