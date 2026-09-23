#!/usr/bin/env bash
# One-command verification entrypoint for G16 Tumble (node 8).
#
# Runs the full automated suite on Linux, headless, and exits 0 only if every
# assertion passes. The five core contracts are each covered:
#   (1) shatter -> many blocks, varied sizes/shapes, non-zero velocity + spin  [step 2]
#   (2) gravity -> downward acceleration, velocity damping, settle, no tunnel  [step 2]
#   (3) debris -> player damage -> health reduced                              [step 5, 9]
#   (4) difficulty curve monotonic                                             [step 8]
#   (5) hitscan weapon deterministic for identical inputs                      [step 6]
# Steps 1/3/4/7/10 cover stress, audio, game-flow, and rendered smoke checks.
#
# Run after clone:  ./run_tests.sh
set -euo pipefail
cd "$(dirname "$0")"
GODOT="$(tools/ensure_godot.sh)"
export GODOT_SILENCE_ROOT_WARNING=1

echo "===== [1/10] physics stress test (250 rigid bodies, Jolt) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/StressTest.tscn

echo
echo "===== [2/10] destruction-core + physics-contract test (shatter -> debris -> gravity/damping/settle) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/DestructionTest.tscn

echo
echo "===== [3/10] audio wiring test (pew/crash/impact trigger mapping) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/AudioTest.tscn

echo
echo "===== [4/10] audio spectral analysis (low-end crashes, crisp pews) ====="
python3 tools/analyze_audio.py

echo
echo "===== [5/10] weapon + damage loop test (fire -> shatter, debris -> damage, death -> respawn) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/WeaponDamageTest.tscn

echo
echo "===== [6/10] weapon determinism test (identical inputs -> identical hitscan) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/WeaponDeterminismTest.tscn

echo
echo "===== [7/10] game-flow integration test (HUD + death -> game-over -> auto-respawn) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/GameFlowTest.tscn

echo
echo "===== [8/10] level + difficulty-ramp test (monotonic difficulty, winnable full run) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/LevelProgressionTest.tscn

echo
echo "===== [9/10] full-loop integration test (start -> move -> shoot -> shatter -> debris damage -> ramp -> sound -> win -> restart) ====="
"$GODOT" --headless --audio-driver Dummy --path . res://tests/FullLoopTest.tscn

echo
echo "===== [10/10] rendered smoke test (first-person camera + movement) ====="
./smoke_test.sh

echo
echo "ALL TESTS PASSED"
