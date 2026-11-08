#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -z "${GODOT_BIN:-}" ]]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT_BIN="$(command -v godot)"
	elif [[ -x "$HOME/.local/bin/godot" ]]; then
		GODOT_BIN="$HOME/.local/bin/godot"
	else
		echo "Error: No se encontró el binario de Godot 4.3 (definí GODOT_BIN o instalalo en PATH / ~/.local/bin/godot)." >&2
		exit 1
	fi
fi

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

if [[ ! -f "$DIR/.godot/global_script_class_cache.cfg" ]]; then
	echo "Inicializando caché de clases GDScript (--import)..."
	"$GODOT_BIN" --headless --path "$DIR" --import
fi

"$GODOT_BIN" --headless --path "$DIR" --export-debug "Android" "$OUTPUT_APK"

echo "-----------------------------------------------------------------"
echo "✔ APK compilado y firmado correctamente:"
ls -lh "$OUTPUT_APK"
echo "================================================================="
