#!/bin/bash
# Crea el instalador: "build/stepbro-whispr-<versión>.dmg", con la app y un acceso a Aplicaciones.
set -euo pipefail
cd "$(dirname "$0")/.."

./scripts/build.sh

VERSION="$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Resources/Info.plist)"
APP="build/stepbro whispr.app"
DMG="build/stepbro-whispr-$VERSION.dmg"

# dmgbuild coloca los iconos y el fondo sin abrir el Finder. Se instala una vez, dentro de build/.
TOOLS="build/dmg-tools"
if [ ! -x "$TOOLS/bin/dmgbuild" ]; then
    echo "Instalando dmgbuild en $TOOLS…"
    python3 -m venv "$TOOLS"
    "$TOOLS/bin/pip" install --quiet --disable-pip-version-check dmgbuild
fi

swift scripts/make-dmg-background.swift build/dmg

rm -f "$DMG"
"$TOOLS/bin/dmgbuild" \
    -s scripts/dmg-settings.py \
    -D app="$APP" \
    -D background=build/dmg/background.png \
    -D icon=Resources/AppIcon.icns \
    "stepbro whispr" "$DMG"

IDENTITY="$(./scripts/signing-identity.sh)"
if [ "$IDENTITY" != "-" ]; then
    codesign --force --sign "$IDENTITY" --identifier "com.susurro.Susurro.dmg" "$DMG"
fi

echo "Instalador listo: $DMG ($(du -h "$DMG" | cut -f1 | xargs))"
