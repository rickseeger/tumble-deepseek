#!/usr/bin/env bash
# Run the rendered smoke test (needs a GL context; auto-uses Xvfb if headless).
# Exit code 0 = pass.
set -euo pipefail
cd "$(dirname "$0")"
GODOT="$(tools/ensure_godot.sh)"
export GODOT_SILENCE_ROOT_WARNING=1

ARGS=(--audio-driver Dummy --path . --rendering-method gl_compatibility --rendering-driver opengl3 res://tests/SmokeTest.tscn)

if [ -n "${DISPLAY:-}" ]; then
  exec "$GODOT" "${ARGS[@]}"
elif command -v xvfb-run >/dev/null 2>&1; then
  exec xvfb-run -a -s "-screen 0 1280x720x24" "$GODOT" "${ARGS[@]}"
else
  echo "No DISPLAY and no xvfb-run available; cannot run the rendered smoke test." >&2
  exit 2
fi
