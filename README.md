# Tumble (G16 node 1 — first-person 3D scaffold)

Linux-native first-person 3D game scaffold. This is node 1 of mission tree G16:
a first-person destruction game. This node delivers the foundation only:

- a real 3D engine project that builds and launches on Linux,
- a ground-level first-person camera that moves forward through a 3D world
  (mouse-look + WASD + jump),
- a flat ground plane with a few static test objects,
- proof that the physics engine steps 250 concurrently simulated rigid bodies
  without collapse (this de-risks the destruction core for later nodes).

Deliberately **not** included yet (separate nodes): the shatter/destruction
mechanic, the weapon, audio, procedural structures, difficulty ramp.

## Engine

- **Godot 4.7.2** (GDScript), GL Compatibility renderer (works on real GPUs and
  on software Mesa/llvmpipe for headless CI).
- **Jolt Physics** backend (built into Godot 4.4+, enabled via
  `physics/3d/physics_engine = "Jolt Physics"`). Chosen because it comfortably
  handles hundreds of concurrently simulated rigid bodies — the hardest
  requirement of the full game — plus first-person control, positional audio,
  and trivial Linux-native build/run.

## Build & run (single command)

Prerequisites: `git`, and either `curl` or `wget` (for the one-time Godot
download). No system Godot install required.

```sh
git clone git@github.com:rickseeger/tumble-deepseek.git
cd tumble-deepseek
./run.sh
```

`./run.sh` locates a `godot`/`godot4` on PATH, or downloads the official
Godot 4.7.2 Linux build once into `.godot-bin/` (cached, not committed), then
launches the game.

Controls:
- Mouse look (click to capture/release the pointer)
- W/A/S/D or arrow keys — move
- Space — jump
- Esc — release mouse

## Automated verification

```sh
./test.sh
```

Runs, in order:

1. **Physics stress test** (`godot --headless ... res://tests/StressTest.tscn`)
   — spawns 250 rigid bodies above the ground and steps the simulation for 360
   frames (6 s), then verifies none tunnel through the floor and the world is
   still sane. Exit 0 on pass.
2. **Rendered smoke test** (`./smoke_test.sh` → `res://tests/SmokeTest.tscn`)
   — loads the real game scene, verifies the first-person camera sits at head
   height, drives the player forward via the real input path, and confirms a
   3D scene actually renders by sampling viewport pixels in code (sky blue at
   top, ground green at bottom, colour variation) — no human vision involved.
   Uses Xvfb automatically when there is no display.

## Project layout

```
main.tscn                root scene (loads scripts/main.gd)
scripts/main.gd          builds environment, ground, props, player
scripts/player.gd        first-person controller (CharacterBody3D)
scripts/player.tscn      player scene (capsule + camera)
tests/stress_test.gd     250-body Jolt stress test
tests/smoke_test.gd      rendered first-person smoke test
run.sh / test.sh / smoke_test.sh   one-command entry points
tools/ensure_godot.sh    locates or downloads the Godot binary
```
