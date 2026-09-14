#!/usr/bin/env bash
# Run the full automated verification: physics stress test, destruction-core
# test, weapon+damage loop test, game-flow integration test, then the rendered
# smoke test. Exit code 0 only if all pass.
set -euo pipefail
cd "$(dirname "$0")"
GODOT="$(tools/ensure_godot.sh)"
export GODOT_SILENCE_ROOT_WARNING=1

echo "===== [1/5] physics stress test (250 rigid bodies, Jolt) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/StressTest.tscn

echo
echo "===== [2/5] destruction-core test (structure -> shatter -> debris) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/DestructionTest.tscn

echo
echo "===== [3/5] weapon + damage loop test (fire -> shatter, debris -> damage, death -> respawn) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/WeaponDamageTest.tscn

echo
echo "===== [4/5] game-flow integration test (HUD + death -> game-over -> auto-respawn) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/GameFlowTest.tscn

echo
echo "===== [5/5] rendered smoke test (first-person camera + movement) ====="
./smoke_test.sh

echo
echo "ALL TESTS PASSED"
