#!/usr/bin/env bash
# Run the game. One command after clone:  ./run.sh
set -euo pipefail
cd "$(dirname "$0")"
GODOT="$(tools/ensure_godot.sh)"
export GODOT_SILENCE_ROOT_WARNING=1
exec "$GODOT" --path . "$@"
