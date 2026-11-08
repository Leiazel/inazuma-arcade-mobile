#!/usr/bin/env bash
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# 1. Detectar o verificar el binario de Godot 4.3
if [[ -z "${GODOT_BIN:-}" ]]; then
	if command -v godot >/dev/null 2>&1; then
		GODOT_BIN="$(command -v godot)"
	elif [[ -x "$HOME/.local/bin/godot" ]]; then
		GODOT_BIN="$HOME/.local/bin/godot"
	elif [[ -x "/usr/local/bin/godot" ]]; then
		GODOT_BIN="/usr/local/bin/godot"
	else
		echo "Error: No se encontró el binario de Godot 4.3 (definí GODOT_BIN o instalalo en PATH / ~/.local/bin/godot)." >&2
		exit 1
	fi
fi

OUTPUT_DIR="$DIR/build/android"
OUTPUT_APK="${1:-$OUTPUT_DIR/InazumaArcadeMobile.apk}"
mkdir -p "$OUTPUT_DIR"

# 2. Localizar o restaurar el keystore de debug
KEYSTORE_PATH="$DIR/android/debug.keystore"
if [[ ! -f "$KEYSTORE_PATH" && -f "$HOME/.android/debug.keystore" ]]; then
	mkdir -p "$DIR/android"
	cp "$HOME/.android/debug.keystore" "$KEYSTORE_PATH"
fi

if [[ -f "$KEYSTORE_PATH" && ! -f "$HOME/.android/debug.keystore" ]]; then
	mkdir -p "$HOME/.android"
	cp "$KEYSTORE_PATH" "$HOME/.android/debug.keystore" || true
fi

# Compatibilidad con rutas heredadas /home/damian
if [[ -f "$KEYSTORE_PATH" && -w "/home" ]]; then
	mkdir -p /home/damian/.android 2>/dev/null || true
	cp "$KEYSTORE_PATH" /home/damian/.android/debug.keystore 2>/dev/null || true
elif [[ -f "$KEYSTORE_PATH" && -x "$(command -v sudo 2>/dev/null)" ]]; then
	sudo mkdir -p /home/damian/.android 2>/dev/null || true
	sudo cp "$KEYSTORE_PATH" /home/damian/.android/debug.keystore 2>/dev/null || true
fi

# 3. Detectar SDK de Android y configurar Editor Settings de Godot si es necesario
SDK_CANDIDATES=(
	"${ANDROID_HOME:-}"
	"${ANDROID_SDK_ROOT:-}"
	"/usr/local/lib/android/sdk"
	"$HOME/Android/Sdk"
	"$HOME/android-sdk"
)
RESOLVED_SDK=""
for candidate in "${SDK_CANDIDATES[@]}"; do
	if [[ -n "$candidate" && -d "$candidate" ]]; then
		RESOLVED_SDK="$candidate"
		break
	fi
done

GODOT_CONFIG_DIR="$HOME/.config/godot"
mkdir -p "$GODOT_CONFIG_DIR"
if [[ -n "$RESOLVED_SDK" ]]; then
	echo "Configurando Android SDK en Godot Editor Settings ($RESOLVED_SDK)..."
	cat > "$GODOT_CONFIG_DIR/editor_settings-4.3.tres" << EOF
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$RESOLVED_SDK"
export/android/shutdown_adb_on_exit = true
export/android/force_system_user = false
export/android/debug_keystore = "$KEYSTORE_PATH"
export/android/debug_keystore_user = "androiddebugkey"
export/android/debug_keystore_pass = "android"
EOF
	cp "$GODOT_CONFIG_DIR/editor_settings-4.3.tres" "$GODOT_CONFIG_DIR/editor_settings-4.tres"
fi

echo "================================================================="
echo "  INAZUMA ARCADE MOBILE — ANDROID APK EXPORT PIPELINE"
echo "================================================================="
echo "Directorio del proyecto: $DIR"
echo "Destino del APK:        $OUTPUT_APK"
echo "Binario de Godot:       $GODOT_BIN"
echo "Keystore de debug:      $KEYSTORE_PATH"
if [[ -n "$RESOLVED_SDK" ]]; then
	echo "Android SDK:            $RESOLVED_SDK"
fi
echo "-----------------------------------------------------------------"

# 4. Asegurar caché de clases GDScript (--import previo para evitar crash en headless)
if [[ ! -f "$DIR/.godot/global_script_class_cache.cfg" ]]; then
	echo "Inicializando caché de clases GDScript (--import)..."
	"$GODOT_BIN" --headless --path "$DIR" --import
fi

# 5. Compilar APK debug
echo "Compilando APK con preset 'Android'..."
"$GODOT_BIN" --headless --path "$DIR" --export-debug "Android" "$OUTPUT_APK"

echo "-----------------------------------------------------------------"
echo "✔ APK compilado y firmado correctamente:"
ls -lh "$OUTPUT_APK"
echo "================================================================="
