#!/usr/bin/env bash
# Führt die Laufzeit-Tests headless aus. GODOT=/pfad/zu/godot ./tests/run.sh
set -e
cd "$(dirname "$0")/.."
GODOT="${GODOT:-godot}"
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true
"$GODOT" --headless --path . --script res://tests/run_tests.gd
