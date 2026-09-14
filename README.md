# Tumble (G16 node 3 - weapon + damage loop)

Linux-native first-person 3D destruction game. Mission tree G16 builds a game
node by node:

- node 1 - first-person 3D scaffold: movement, camera, ground, a 250-body Jolt
  physics stress test (proof the engine can handle the destruction load).
- node 2 - the destruction core: procedurally generated towers / buildings that
  shatter on demand into many independently simulated rigid-body blocks that
  bounce, roll and settle.
- node 3 (this node) - the weapon and damage loop: a first-person hitscan
  "pew-pew" weapon that shatters structures on hit, debris that damages the
  player on contact (scaled by mass/speed), a health/death/restart flow, and a
  HUD.

## What the destruction core does (node 2)

- `StructureGenerator` procedurally builds a tower/building of varying
  footprint, height, shape mix (box / cylinder / sphere) and per-block size,
  deterministically for a given seed.
- `DestructibleStructure` renders that layout as a single intact `StaticBody3D`,
  then `shatter()` replaces it with one `RigidBody3D` per block - each given
  randomized outward linear velocity, random angular spin, mass scaled to its
  volume, and a friction/bounce physics material. They fall under real gravity
  and bounce/roll/settle (continuous collision detection so fast small blocks
  do not tunnel through the floor).

## What node 3 adds

- **Weapon** (`scripts/weapon/weapon.gd`): a deterministic hitscan blaster,
  child of the player camera. `fire()` raycasts from the camera forward axis:
  hitting an intact structure triggers its existing `shatter()` path at the hit
  point; hitting a loose debris block blasts it away (the "blast through" half
  of the tension). Finite magazine (30) with auto-reload, a fire-rate cooldown,
  a muzzle-flash mesh, and a recoil kick. Emits `fired` / `shot_landed` /
  `ammo_changed` so node 5 can hang audio on it.
- **Damage** (`scripts/damage/damage_zone.gd`): an `Area3D` hitbox around the
  player that converts each debris `RigidBody3D` impact into damage via
  `impact_damage(mass, speed) = clamp(mass * speed * 0.4, 2, 45)`. Slow blocks
  (below 2 m/s) deal no damage, so only genuine moving debris hurts. A per-body
  cooldown stops a single tumbling block from re-damaging every frame.
- **Health / death / restart** (`scripts/player.gd`): `health`/`max_health`,
  `take_damage()`, `die()`, `respawn()`, plus `health_changed`/`died`/
  `respawned` signals. At zero health the player dies; `main.gd` shows a
  game-over overlay and auto-respawns after 2 s with full health and fresh
  structures.
- **HUD** (`scripts/ui/hud.gd`): health bar + ammo readout + game-over overlay,
  built in code (diffable and testable by asserting on node values, not pixels).

The weapon and damage model are fully deterministic and scriptable: holding the
"fire" action (or clicking) drives the exact same `fire()` code path, so the
whole loop is testable without vision.

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
- Left click (captured) or F - fire the weapon
- W/A/S/D or arrow keys - move
- Space - jump
- Esc - release mouse
- T - shatter every intact structure at once (debug stand-in)
- R - rebuild fresh structures (and revive the player if dead)

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
3. Weapon + damage loop test (`res://tests/WeaponDamageTest.tscn`) - asserts the
   node-3 completion contract headless, no vision: firing via input injection
   reduces ammo and shatters the aimed-at structure; a moving debris block
   colliding with the player reduces health (scaled by mass/speed); health at
   zero triggers death and respawn restores full health.
4. Game-flow integration test (`res://tests/GameFlowTest.tscn`) - loads the real
   game scene and verifies the HUD wiring, then lethal damage -> game-over
   overlay -> auto-respawn restores health and rebuilds structures.
5. Rendered smoke test (`res://tests/SmokeTest.tscn`) - loads the real game
   scene, drives the player, and verifies rendering via code-level pixel
   sampling (sky/ground/colour variation), using Xvfb when headless.

## Project layout

```
main.tscn                     root scene (loads scripts/main.gd)
scripts/main.gd               environment, ground, props, player, destructibles, HUD, death/restart
scripts/player.gd             first-person controller + weapon + health/damage/death
scripts/player.tscn           player scene (capsule + camera)
scripts/weapon/weapon.gd      hitscan "pew-pew" weapon (raycast, ammo, recoil, muzzle flash)
scripts/damage/damage_zone.gd player hazard hitbox (debris -> damage)
scripts/ui/hud.gd             health bar + ammo + game-over overlay
scripts/destruction/structure_generator.gd     procedural block layout
scripts/destruction/destructible_structure.gd  shatter to rigid-body debris
tests/stress_test.gd          250-body Jolt stress test
tests/destruction_test.gd     destruction-core automated test
tests/weapon_damage_test.gd   weapon + damage loop automated test
tests/game_flow_test.gd       HUD + death/restart integration test
tests/smoke_test.gd           rendered first-person smoke test
run.sh / test.sh / smoke_test.sh   one-command entry points
tools/ensure_godot.sh         locates or downloads the Godot binary
```
