#!/usr/bin/env bash
# Run the full automated verification: physics stress test, destruction-core
# test, audio system test (wiring) + offline spectral analysis, weapon+damage
# loop test, game-flow integration test, level + difficulty-ramp test, then
# the rendered smoke test. Exit code 0 only if all pass.
set -euo pipefail
cd "$(dirname "$0")"
GODOT="$(tools/ensure_godot.sh)"
export GODOT_SILENCE_ROOT_WARNING=1

echo "===== [1/8] physics stress test (250 rigid bodies, Jolt) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/StressTest.tscn

echo
echo "===== [2/8] destruction-core test (structure -> shatter -> debris) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/DestructionTest.tscn

echo
echo "===== [3/8] audio wiring test (pew/crash/impact trigger mapping) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/AudioTest.tscn

echo
echo "===== [4/8] audio spectral analysis (low-end crashes, crisp pews) ====="
python3 tools/analyze_audio.py

echo
echo "===== [5/8] weapon + damage loop test (fire -> shatter, debris -> damage, death -> respawn) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/WeaponDamageTest.tscn

echo
echo "===== [6/8] game-flow integration test (HUD + death -> game-over -> auto-respawn) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/GameFlowTest.tscn

echo
echo "===== [7/8] level + difficulty-ramp test (monotonic difficulty, winnable full run) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/LevelProgressionTest.tscn

echo
echo "===== [8/8] rendered smoke test (first-person camera + movement) ====="
./smoke_test.sh

echo
echo "ALL TESTS PASSED"
