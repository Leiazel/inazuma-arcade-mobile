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

if [[ ! -f "$DIR/.godot/global_script_class_cache.cfg" ]]; then
	echo "[INIT] Generando caché global de clases GDScript (--import)..."
	"$GODOT_BIN" --headless --path "$DIR" --import
fi

echo "[1/2] Ejecutando suite E2E principal (tests/test_runner.gd)..."
"$GODOT_BIN" --headless --path "$DIR" --script tests/test_runner.gd

echo ""
echo "[2/2] Ejecutando suite Adversarial de concurrencia y límites (tests/test_adversarial_m5.gd)..."
"$GODOT_BIN" --headless --path "$DIR" --script tests/test_adversarial_m5.gd

echo ""
echo "✔ Todas las suites de pruebas finalizaron exitosamente sin fallos."
