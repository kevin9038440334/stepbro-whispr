#!/bin/bash
# Crea un certificado de firma local "Susurro Dev" en tu llavero.
# Con una firma estable, macOS recuerda los permisos (micrófono, accesibilidad)
# aunque recompiles. Para borrarlo: Acceso a Llaveros > Mis certificados.
set -euo pipefail

NAME="Susurro Dev"
if security find-identity -p codesigning | grep -q "\"$NAME\""; then
    echo "El certificado \"$NAME\" ya existe."
    exit 0
fi

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/cert.cnf" <<CNF
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
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 \
    -keyout "$TMP/key.pem" -out "$TMP/cert.pem" -config "$TMP/cert.cnf" 2>/dev/null
# Algoritmos clásicos: el llavero de macOS no lee los que usa OpenSSL 3 por defecto.
openssl pkcs12 -export -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
    -out "$TMP/cert.p12" -passout pass:susurro -name "$NAME" \
    -keypbe PBE-SHA1-3DES -certpbe PBE-SHA1-3DES -macalg sha1 2>/dev/null
security import "$TMP/cert.p12" -k "$HOME/Library/Keychains/login.keychain-db" \
    -P susurro -T /usr/bin/codesign >/dev/null

echo "Certificado \"$NAME\" creado."
