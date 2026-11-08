#!/usr/bin/env bash
set -euo pipefail

TAG="latest"
APK_PATH="build/android/InazumaArcadeMobile.apk"

if [[ ! -f "$APK_PATH" ]]; then
  echo "Error: No se encontró el archivo APK en '$APK_PATH'." >&2
  exit 1
fi

COMMIT_HASH="${GITHUB_SHA:-$(git rev-parse HEAD)}"
SHORT_SHA=$(git rev-parse --short "$COMMIT_HASH")
COMMIT_MSG=$(git log -1 --pretty=%B "$COMMIT_HASH" | head -n 1)
REPO="${GITHUB_REPOSITORY:-Leiazel/mf-champions-mobile}"
DATE_STR=$(date -u +"%Y-%m-%d %H:%M UTC")

DIRECT_DOWNLOAD_URL="https://github.com/${REPO}/releases/latest/download/InazumaArcadeMobile.apk"
QR_URL="https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=${DIRECT_DOWNLOAD_URL}"

NOTES_FILE=$(mktemp)
cat > "$NOTES_FILE" << EOF
## ⚽ Inazuma Arcade Mobile — Última Versión

**Fecha de compilación**: \`${DATE_STR}\`  
**Commit**: [\`${SHORT_SHA}\`](https://github.com/${REPO}/commit/${COMMIT_HASH}) — *${COMMIT_MSG}*  
**Archivo**: \`InazumaArcadeMobile.apk\`  

---

### 📲 Descarga directa para tu celular
1. **Abrí este enlace desde el navegador de tu celular**:  
   👉 [**Descargar InazumaArcadeMobile.apk (${SHORT_SHA})**](${DIRECT_DOWNLOAD_URL})

2. **O escaneá este código QR directamente con la cámara de tu teléfono**:  
   <p align="center">
     <img src="${QR_URL}" width="220" height="220" alt="Código QR de descarga APK" />
   </p>

---

### 📱 Cómo instalar en Android:
1. Al terminar la descarga, tocá la notificación o el archivo \`InazumaArcadeMobile.apk\` en la carpeta de **Descargas**.
2. Si Android te avisa que la app proviene de fuentes desconocidas, tocá **Configuración** y activá **Permitir desde esta fuente**.
3. Presioná **Instalar** o **Actualizar**. (Todas las versiones usan la misma clave de firma, por lo que podés actualizar directamente sobre la versión anterior sin borrar datos).
EOF

echo "===> Publicando / actualizando Release '$TAG'..."
if gh release view "$TAG" --repo "$REPO" >/dev/null 2>&1; then
  echo "Actualizando release existente '$TAG'..."
  gh release upload "$TAG" "$APK_PATH" --repo "$REPO" --clobber
  gh release edit "$TAG" --repo "$REPO" --title "Inazuma Arcade Mobile (Última Versión)" --notes-file "$NOTES_FILE"
  git tag -f "$TAG" "$COMMIT_HASH"
  git push -f origin "$TAG" || true
else
  echo "Creando release inicial '$TAG'..."
  gh release create "$TAG" "$APK_PATH" \
    --repo "$REPO" \
    --target "$COMMIT_HASH" \
    --title "Inazuma Arcade Mobile (Última Versión)" \
    --notes-file "$NOTES_FILE" \
    --latest
fi

if [[ "${GITHUB_REF:-}" == refs/tags/v* ]]; then
  SPECIFIC_TAG="${GITHUB_REF#refs/tags/}"
  echo "Publicando release versionado para $SPECIFIC_TAG..."
  if gh release view "$SPECIFIC_TAG" --repo "$REPO" >/dev/null 2>&1; then
    gh release upload "$SPECIFIC_TAG" "$APK_PATH" --repo "$REPO" --clobber
    gh release edit "$SPECIFIC_TAG" --repo "$REPO" --title "Inazuma Arcade Mobile $SPECIFIC_TAG" --notes-file "$NOTES_FILE"
  else
    gh release create "$SPECIFIC_TAG" "$APK_PATH" \
      --repo "$REPO" \
      --title "Inazuma Arcade Mobile $SPECIFIC_TAG" \
      --notes-file "$NOTES_FILE"
  fi
fi

if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  cat >> "$GITHUB_STEP_SUMMARY" << EOF
# 📱 ¡APK Compilado y Disponible para Descarga!

La última versión de **Inazuma Arcade Mobile** ya está lista para instalar en tu celular.

### ⬇️ Enlace Directo
[📲 Descargar InazumaArcadeMobile.apk](${DIRECT_DOWNLOAD_URL})

### 📷 Escanear con tu teléfono
Escaneá este código QR con la cámara de tu celular para iniciar la descarga automáticamente:

<img src="${QR_URL}" width="200" height="200" alt="QR Descarga APK" />

- **Archivo**: \`InazumaArcadeMobile.apk\`
- **Commit**: \`${COMMIT_HASH}\`
- **Engine**: Godot 4.3 Stable
EOF
fi

rm -f "$NOTES_FILE"
echo "✔ Release publicado y actualizado con éxito."
