#!/usr/bin/env bash
set -e

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
GODOT_BIN="${GODOT_BIN:-/home/damian/.local/bin/godot}"
OUTPUT_DIR="$DIR/build/android"
OUTPUT_APK="$OUTPUT_DIR/InazumaArcadeMobile.apk"

mkdir -p "$OUTPUT_DIR"
echo "================================================================="
echo "  INAZUMA ARCADE MOBILE — ANDROID APK EXPORT PIPELINE"
echo "================================================================="
echo "Directorio del proyecto: $DIR"
echo "Destino del APK:        $OUTPUT_APK"
echo "Binario de Godot:       $GODOT_BIN"
echo "-----------------------------------------------------------------"

"$GODOT_BIN" --headless --path "$DIR" --export-debug "Android" "$OUTPUT_APK"

echo "-----------------------------------------------------------------"
echo "✔ APK compilado y firmado correctamente:"
ls -lh "$OUTPUT_APK"
echo "================================================================="

