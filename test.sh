#!/usr/bin/env bash
# Run the full automated verification: physics stress test (headless) then the
# rendered smoke test. Exit code 0 only if both pass.
set -euo pipefail
cd "$(dirname "$0")"
GODOT="$(tools/ensure_godot.sh)"
export GODOT_SILENCE_ROOT_WARNING=1

echo "===== [1/2] physics stress test (250 rigid bodies, Jolt) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/StressTest.tscn

echo
echo "===== [2/2] rendered smoke test (first-person camera + movement) ====="
./smoke_test.sh

echo
echo "ALL TESTS PASSED"
