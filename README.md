# Tumble (G16 node 2 - destruction core)

Linux-native first-person 3D destruction game. Mission tree G16 builds a game
node by node:

- node 1 - first-person 3D scaffold: movement, camera, ground, a 250-body Jolt
  physics stress test (proof the engine can handle the destruction load).
- node 2 (this node) - the destruction core: procedurally generated towers /
  buildings that shatter on demand into many independently simulated rigid-body
  blocks that bounce, roll and settle.

## What the destruction core does

- `StructureGenerator` procedurally builds a tower/building of varying
  footprint, height, shape mix (box / cylinder / sphere) and per-block size,
  deterministically for a given seed.
- `DestructibleStructure` renders that layout as a single intact `StaticBody3D`,
  then `shatter()` replaces it with one `RigidBody3D` per block - each given
  randomized outward linear velocity, random angular spin, mass scaled to its
  volume, and a friction/bounce physics material. They fall under real gravity
  and bounce/roll/settle (continuous collision detection so fast small blocks
  do not tunnel through the floor).

### Hook for later nodes

`scripts/destruction/destructible_structure.gd` exposes the contract the rest of
the tree depends on:

- `shatter(impulse_origin, power)` returns `Array[RigidBody3D]` - the
  deterministic trigger node 3 (the weapon) will call.
- `blocks: Array[RigidBody3D]` - the spawned debris list, for node 3 to detect
  player-collision damage.
- `block_specs: Array` - the generated layout (shape/size/color per block), so
  node 5 can scale audio to debris variety.
- `signal shattered(debris)` - emitted once, right after shatter.

Preload the script directly
(`preload("res://scripts/destruction/destructible_structure.gd")`) rather than
relying on the global class cache.

## Engine

- Godot 4.7.2 (GDScript), GL Compatibility renderer (real GPUs and software
  Mesa/llvmpipe for headless CI).
- Jolt Physics backend (`physics/3d/physics_engine = "Jolt Physics"`), 60
  ticks/s, gravity 9.8 - comfortably simulates hundreds of rigid bodies at once.

## Build and run (single command)

Prerequisites: `git`, and either `curl` or `wget` (one-time Godot download).
No system Godot install required.

```sh
git clone git@github.com:rickseeger/tumble-deepseek.git
cd tumble-deepseek
./run.sh
```

Controls:

- Mouse look (click to capture/release the pointer)
- W/A/S/D or arrow keys - move
- Space - jump
- Esc - release mouse
- F - shatter every intact destructible structure (debug stand-in for the
  node 3 weapon trigger)
- R - rebuild fresh structures

## Automated verification

```sh
./test.sh
```

Runs, in order:

1. Physics stress test (`res://tests/StressTest.tscn`) - 250 rigid bodies stepped
   for 360 frames, verifying none tunnel through the floor.
2. Destruction-core test (`res://tests/DestructionTest.tscn`) - generates a
   structure, triggers `shatter()`, dumps per-frame per-block state to a CSV
   (`$G16_DUMP_PATH`, else `user://destruction_frames.csv`), and asserts
   programmatically (no vision): Jolt is active, the intact structure is one
   StaticBody3D that shatters into 30 or more independently simulated
   RigidBody3D blocks of varied sizes/shapes, every block gets non-zero random
   linear and angular velocity, gravity is 9.8 and blocks fall, and after 900
   frames all debris has settled with none falling through the ground plane.
3. Rendered smoke test (`res://tests/SmokeTest.tscn`) - loads the real game
   scene, drives the player, and verifies rendering via code-level pixel
   sampling (sky/ground/colour variation), using Xvfb when headless.

## Project layout

```
main.tscn                     root scene (loads scripts/main.gd)
scripts/main.gd               environment, ground, props, player, destructibles + F/R debug keys
scripts/player.gd             first-person controller (CharacterBody3D)
scripts/player.tscn           player scene (capsule + camera)
scripts/destruction/structure_generator.gd     procedural block layout
scripts/destruction/destructible_structure.gd  shatter to rigid-body debris
tests/stress_test.gd          250-body Jolt stress test
tests/destruction_test.gd     destruction-core automated test
tests/smoke_test.gd           rendered first-person smoke test
run.sh / test.sh / smoke_test.sh   one-command entry points
tools/ensure_godot.sh         locates or downloads the Godot binary
```
