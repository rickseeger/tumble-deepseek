# Tumble (G16 node 6 - integrated full game loop)

Linux-native first-person 3D destruction game. Mission tree G16 builds a game
node by node:

- node 1 - first-person 3D scaffold: movement, camera, ground, a 250-body Jolt
  physics stress test (proof the engine can handle the destruction load).
- node 2 - the destruction core: procedurally generated towers / buildings that
  shatter on demand into many independently simulated rigid-body blocks that
  bounce, roll and settle.
- node 3 - the weapon and damage loop: a first-person hitscan "pew-pew" weapon
  that shatters structures on hit, debris that damages the player on contact
  (scaled by mass/speed), a health/death/restart flow, and a HUD.
- node 4 - the linear level and difficulty ramp: a forward-
  advancing stream of seeded structures whose density/size/height and debris
  danger ramp up monotonically with progress, with a guaranteed clear lane so
  the run stays winnable.
- node 5 - the destruction sound system: procedurally generated
  deep, rumbly, resonant crash/explosion audio scaled to debris size and
  variety, plus crisp high-pitched pew-pew weapon fire, wired to the real
  shatter and fire events and verified by code-level spectral analysis.
- node 6 (this node) - the integration/hardening pass: the whole loop is wired
  into one coherent, playable game with a start screen, a win condition, and a
  restart flow, plus a headless full-loop test that drives the complete
  start -> move -> shoot -> shatter -> debris -> damage -> ramp -> sound ->
  win -> restart sequence end-to-end.

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

## What node 4 adds

- **Difficulty curve** (`scripts/level/difficulty_curve.gd`): every difficulty
  scalar is a pure, monotonic function of progress `t` in `[0,1]` -- structure
  spacing shrinks (density grows), footprint/height grow (bigger, taller
  structures), and debris launch-speed / block-count multipliers grow (more,
  faster, more dangerous debris). `params_for(t)` feeds the structure generator.
- **Level generator** (`scripts/level/level_generator.gd`): a deterministic,
  seedable layout running forward along -Z. Each record carries its progress,
  the rolled difficulty params, and the measured footprint, and is placed so its
  inner edge stays outside a guaranteed clear centre lane -- the player can
  always advance, so the level is winnable start-to-finish.
- **Streaming** (`scripts/level/level_manager.gd`): spawns structures as they
  enter a window ahead of the player and despawns them once they fall behind,
  keeping live physics bounded while the level feels continuous.
- **Structure generator** now accepts the difficulty scalars (footprint/height/
  block-count), and `DestructibleStructure.shatter()` applies `debris_speed_scale`
  to the debris launch speed -- the "debris danger" knob.

## What node 5 adds

- **Audio manager** (`scripts/audio/audio_manager.gd`, autoload singleton):
  loads the generated WAVs straight off disk with `FileAccess` (no Godot import
  step, no editor metadata to commit) and plays them from a small pooled set of
  `AudioStreamPlayer`s. Exposes `play_pew()`, `play_crash(weight, variety)`
  and `play_impact(mass)`.
- **Destruction sound** (`audio/crash_small|medium|large|huge.wav`): four
  procedurally synthesised crash/explosion tiers with real low-end weight
  (sub-bass rumble, resonant partials, low-passed noise body, an impact
  transient). A structure's shatter picks the tier and scales pitch/volume by
  the total debris mass, and stacks extra layers when the block layout is more
  varied -- bigger structures crash deeper, longer and heavier.
- **Weapon fire** (`audio/pew_0|1|2.wav`): three crisp, high-pitched laser
  "pew" variants (saw/square down-chirp plus a noise zap), one per shot, with
  slight random pitch/volume variation. A small single-debris impact uses
  `audio/impact.wav`, pitched and gained by the block's mass.
- **Wiring**: the weapon's `fire()` triggers a pew on every shot and a
  mass-scaled impact when it blasts loose debris; `DestructibleStructure.shatter()`
  triggers a crash whose recorded weight is the true total debris mass and whose
  variety is the number of distinct block size/shape combinations. No timers --
  audio fires on the real shatter/fire code paths.

## What node 6 adds (integration / hardening)

- **Game-state machine** (`scripts/main.gd`): the game boots into a title/start
  screen (`BOOT`), plays (`PLAYING`), dies with a game-over overlay and an
  automatic restart after 2 s (`DEAD`, or press Enter to restart immediately),
  and wins on reaching the far end of the level (`WON`). `start_game()` is the
  single public entry point that resets the player and the level and clears
  every overlay, so a test can drive the exact same transitions the input
  handler uses.
- **Start / win / restart flow**: Enter (or a click) starts from the title
  screen; Enter on the victory screen starts a fresh run. Death restarts the
  run from the beginning (roguelike: lose your progress). Esc releases the
  mouse pointer.
- **Victory screen** (`scripts/ui/hud.gd`): a "LEVEL CLEARED" overlay with a
  play-again prompt, reached by surviving to z = -200 with the difficulty ramp
  at full tilt.
- **Full-loop integration test** (`tests/full_loop_test.gd`): a headless,
  no-vision run of the real game scene that starts the game, drives the player
  the whole level to the win, restarts, then shoots a structure to shatter it
  into rigid-body debris (asserting the pew/crash audio counters), and finally
  fires a debris block at the player to prove the damage leg — then exits
  cleanly with code 0.

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

- Enter (or click) - start the game / play again / skip the respawn wait
- Mouse look (click to capture the pointer; Esc releases it)
- Left click (captured) or F - fire the weapon
- W/A/S/D or arrow keys - move
- Space - jump
- T - shatter every intact structure at once (debug stand-in)
- R - restart the run from the beginning

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
3. Audio wiring test (`res://tests/AudioTest.tscn`) - headless (Dummy driver):
   asserts all 8 generated WAVs load and decode to non-empty 16-bit PCM, the
   pure size->sound mapping is monotonic (bigger = deeper + louder + more tiers
   + more layers), firing triggers exactly one pew, shattering triggers exactly
   one crash whose weight equals the true total debris mass, and firing at a
   loose debris block triggers a mass-scaled impact.
4. Audio spectral analysis (`tools/analyze_audio.py`) - pure-Python FFT over the
   generated samples: crash/explosion files carry >= 30% of spectral energy
   below 250 Hz (real low-end weight), pew files carry >= 30% above 1 kHz
   (crisp high end), and crash tiers scale (longer + deeper as size grows).
5. Weapon + damage loop test (`res://tests/WeaponDamageTest.tscn`) - asserts the
   node-3 completion contract headless, no vision: firing via input injection
   reduces ammo and shatters the aimed-at structure; a moving debris block
   colliding with the player reduces health (scaled by mass/speed); health at
   zero triggers death and respawn restores full health.
6. Game-flow integration test (`res://tests/GameFlowTest.tscn`) - loads the real
   game scene and verifies the HUD wiring, then lethal damage -> game-over
   overlay -> auto-respawn restores health and rebuilds structures.
7. Level + difficulty-ramp test (`res://tests/LevelProgressionTest.tscn`) -
   asserts (headless, no vision) that every difficulty scalar is monotonic in
   progress, the generator is seedable/deterministic, per-record difficulty
   params rise along the level, the clear lane is never violated, generated
   block count / height / debris launch-speed grow with progress, and a seeded
   full run of the real scene reaches the end without dying while structures
   stream ahead and despawn behind.
8. Full-loop integration test (`res://tests/FullLoopTest.tscn`) - the node-6
   contract, headless and vision-free: boots the real game scene into the start
   screen, starts the game, drives the player the full level to the win,
   restarts, shoots a structure to shatter it into rigid-body debris (asserting
   the pew/crash audio counters fire exactly once each), fires a debris block at
   the player to prove damage, and exits cleanly with code 0.
9. Rendered smoke test (`res://tests/SmokeTest.tscn`) - loads the real game
   scene, starts the run, drives the player, and verifies rendering via
   code-level pixel sampling (sky/ground/colour variation), using Xvfb when
   headless.

Subjective audio quality (how the crashes feel and the pews read) is judged by
the human playtester at node 7 -- the automated checks only prove the audio is
non-silent, spectrally correct, and wired to the right events.

## Project layout

```
main.tscn                     root scene (loads scripts/main.gd)
scripts/main.gd               environment, ground, props, player, destructibles, HUD, death/restart
scripts/player.gd             first-person controller + weapon + health/damage/death
scripts/player.tscn           player scene (capsule + camera)
scripts/weapon/weapon.gd      hitscan "pew-pew" weapon (raycast, ammo, recoil, muzzle flash, pew audio)
scripts/damage/damage_zone.gd player hazard hitbox (debris -> damage)
scripts/audio/audio_manager.gd  autoload sound system (loads WAVs, plays pew/crash/impact)
audio/*.wav                   procedurally generated 16-bit mono 44.1 kHz samples
tools/gen_audio.py            deterministic sample synthesis (reproduces audio/*.wav)
tools/analyze_audio.py        FFT spectral analysis of the generated samples
scripts/ui/hud.gd             health bar + ammo + game-over overlay
scripts/destruction/structure_generator.gd     procedural block layout
scripts/level/difficulty_curve.gd   pure monotonic difficulty ramp
scripts/level/level_generator.gd    deterministic seeded level layout
scripts/level/level_manager.gd      streams structures ahead / despawns behind
scripts/destruction/destructible_structure.gd  shatter to rigid-body debris
tests/stress_test.gd          250-body Jolt stress test
tests/destruction_test.gd     destruction-core automated test
tests/weapon_damage_test.gd   weapon + damage loop automated test
tests/game_flow_test.gd       HUD + death/restart integration test
tests/level_progression_test.gd  level + difficulty-ramp automated test
tests/audio_test.gd           audio wiring + size->sound mapping test
tests/smoke_test.gd           rendered first-person smoke test
run.sh / test.sh / smoke_test.sh   one-command entry points
tools/ensure_godot.sh         locates or downloads the Godot binary
```
