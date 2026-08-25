#!/bin/bash
# Creates a persistent self-signed code-signing identity named
# "AltTabber Self-Signed" in your login keychain. Once it exists, build.sh signs
# with it, so the app keeps a STABLE identity across rebuilds — meaning macOS
# won't ask you to re-grant Accessibility / Screen Recording every time.
#
# Run this ONCE:  ./make-identity.sh
# macOS may ask for your login password (to add the cert to your keychain).
set -euo pipefail

NAME="AltTabber Self-Signed"

if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "✓ L'identité '$NAME' existe déjà. Rien à faire."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# Use Apple's system openssl (LibreSSL). Homebrew's OpenSSL 3.x produces PKCS#12
# files with a modern MAC that macOS' `security import` rejects.
OPENSSL="/usr/bin/openssl"

echo "▸ Génération d'un certificat de signature auto-signé…"

# OpenSSL config with the codesigning extended key usage.
cat > "$TMP/cert.cnf" <<'CNF'
[ req ]
distinguished_name = dn
x509_extensions = v3
prompt = no
[ dn ]
CN = AltTabber Self-Signed
[ v3 ]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

"$OPENSSL" req -x509 -newkey rsa:2048 -nodes \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" \
    -days 3650 -config "$TMP/cert.cnf" >/dev/null 2>&1

# Bundle key+cert into a PKCS#12 for import. A non-empty passphrase avoids the
# "MAC verification failed" error that macOS' security tool throws on empty-pass
# PKCS#12 files produced by LibreSSL.
P12PASS="alttabber"
"$OPENSSL" pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -name "$NAME" -out "$TMP/identity.p12" -passout "pass:$P12PASS" >/dev/null 2>&1

KEYCHAIN="$HOME/Library/Keychains/login.keychain-db"

echo "▸ Import dans le trousseau (mot de passe de session possiblement demandé)…"
# -T codesign lets codesign use the key without a prompt each time.
security import "$TMP/identity.p12" -k "$KEYCHAIN" -P "$P12PASS" \
    -T /usr/bin/codesign -T /usr/bin/security

# Allow codesign to access the private key non-interactively.
security set-key-partition-list -S apple-tool:,apple:,codesign: \
    -k "" "$KEYCHAIN" >/dev/null 2>&1 || true

echo ""
if security find-identity -v -p codesigning | grep -q "$NAME"; then
    echo "✓ Identité '$NAME' créée."
    echo "  Reconstruis maintenant :  ./build.sh"
    echo "  (Tu devras ré-accorder les permissions UNE dernière fois, puis plus jamais.)"
else
    echo "✗ Échec. L'app restera signée en ad-hoc (ce n'est pas bloquant)."
    exit 1
fi
