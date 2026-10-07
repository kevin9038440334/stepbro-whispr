#!/bin/bash
# Compila stepbro whispr y lo empaqueta como "build/stepbro whispr.app"
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"
APP="build/stepbro whispr.app"
# El identificador conserva el nombre antiguo: si cambia, macOS la trata como
# otra app y pierde los permisos, el historial y los ajustes.
BUNDLE_ID="com.susurro.Susurro"

# El sistema de compilación nuevo de SwiftPM graba en el binario el SDK 26 en vez
# del instalado, y macOS aplica entonces el aspecto de esa versión. El clásico lo hace bien.
BUILD=(swift build -c "$CONFIG" --build-system native)
"${BUILD[@]}" 2> >(grep -v "has been deprecated" >&2)
BIN="$("${BUILD[@]}" --show-bin-path 2>/dev/null)/StepbroWhispr"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/StepbroWhispr"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
# La licencia viaja con la app: quien la reciba debe recibir también sus términos.
cp LICENSE.md "$APP/Contents/Resources/LICENSE.md"

# Firma estable para que macOS recuerde los permisos entre compilaciones.
IDENTITY="$(./scripts/signing-identity.sh)"
codesign --force --sign "$IDENTITY" --identifier "$BUNDLE_ID" "$APP"

echo "Listo: $APP (firma: ${IDENTITY/-/ad-hoc})"
