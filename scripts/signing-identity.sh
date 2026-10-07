#!/bin/bash
# Escribe la identidad con la que firmar. Por orden: SIGN_IDENTITY, tu certificado
# "Apple Development" (Xcode > Ajustes > Cuentas), el certificado local "Susurro Dev"
# (scripts/create-certificate.sh) o "-" (firma ad-hoc).
IDENTITY="${SIGN_IDENTITY:-}"
if [ -z "$IDENTITY" ]; then
    IDENTITY="$(security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $2; exit}')"
fi
if [ -z "$IDENTITY" ] && security find-identity -p codesigning 2>/dev/null | grep -q '"Susurro Dev"'; then
    IDENTITY="Susurro Dev"
fi
echo "${IDENTITY:--}"
