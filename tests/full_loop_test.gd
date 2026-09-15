extends Node
## G16 node_6 full-loop integration test (headless, no vision).
## Run:  godot --headless --audio-driver Dummy --path . res://tests/FullLoopTest.tscn
## Exit 0 on pass.
##
## Loads the real game scene and drives the whole loop end-to-end, in order:
##   start -> move -> shoot -> shatter -> debris damage -> difficulty ramp ->
##   sound -> win -> restart. Every check is code-level (state, health, counters,
##   node presence, rigid-body type) -- no vision, no audible output.

const MAIN_SCENE := "res://main.tscn"
const MAIN_SCRIPT := preload("res://scripts/main.gd")
const DIFF := preload("res://scripts/level/difficulty_curve.gd")

const RUN_LENGTH := 200.0
const MAX_RUN_FRAMES := 6000
const CAM_LOCAL_Y := 0.85
const STANDOFF := 6.0

var _checks := 0
var _failures: Array[String] = []
var _main = null
var _player: CharacterBody3D = null
var _level = null
var _hud = null
var _audio = null


func _ready() -> void:
	_run()


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS  ", label)
	else:
		_failures.append(label)
		print("  FAIL  ", label)


func _settle(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _run() -> void:
	print("=== G16 node_6 full-loop integration test ===")

	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		_failures.append("main scene loads")
		_finish()
		return
	_main = packed.instantiate()
	add_child(_main)
	await _settle(4)

	_player = _main.get_node_or_null("Player")
	_level = _main.get_node_or_null("LevelManager")
	_hud = _main.get_node_or_null("HUD")
	_audio = get_node_or_null("/root/AudioManager")

	_check(_player != null, "player present in the game scene")
	_check(_level != null, "level manager present in the game scene")
	_check(_hud != null, "HUD present in the game scene")
	_check(_audio != null, "AudioManager autoload present")
	if _player == null or _level == null or _hud == null:
		_finish()
		return

	await _phase_start()
	await _phase_difficulty_and_win()
	await _phase_restart()
	await _phase_shoot_and_shatter()
	await _phase_debris_damage()

	_finish()


func _phase_start() -> void:
	print("--- start flow ---")
	_check(_main.state == MAIN_SCRIPT.GameState.BOOT, "game boots into BOOT state")
	if _hud.start_panel != null:
		_check(_hud.start_panel.visible, "start screen shown at boot")
	_check(not _hud.game_over_label.visible, "game-over overlay hidden at boot")

	# Enter starts the game (exact same path the real input handler uses).
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ENTER
	ev.pressed = true
	_main._unhandled_input(ev)
	await _settle(2)

	_check(_main.state == MAIN_SCRIPT.GameState.PLAYING, "ENTER transitions BOOT -> PLAYING")
	if _hud.start_panel != null:
		_check(not _hud.start_panel.visible, "start screen hidden after start")
	_check(_player.health == _player.max_health, "player at full health on start (%.0f)" % _player.health)


func _phase_difficulty_and_win() -> void:
	print("--- difficulty ramp + streaming + win ---")
	_check(_level.records.size() >= 8, "level generated %d records" % _level.records.size())

	var first_t: float = float(_level.records[0].t)
	var last_t: float = float(_level.records[_level.records.size() - 1].t)
	_check(DIFF.danger(last_t) > DIFF.danger(first_t),
		"danger ramps from start to end (%.2f -> %.2f)" % [DIFF.danger(first_t), DIFF.danger(last_t)])

	_check(_level.structures.size() >= 2, "structures streamed ahead at spawn (%d)" % _level.structures.size())

	# Drive the player forward the whole level. Clean lane + no shooting means
	# no debris in the way, so the run is deterministic and winnable.
	var reached_end := false
	Input.action_press("move_forward")
	for i in range(MAX_RUN_FRAMES):
		await get_tree().physics_frame
		if _player.position.z <= -RUN_LENGTH:
			reached_end = true
			break
		if _player.is_dead:
			break
	Input.action_release("move_forward")
	await _settle(2)

	_check(reached_end, "player reached the far end of the level (z=%.1f)" % _player.position.z)
	_check(not _player.is_dead, "player survived the full run (health %.0f)" % _player.health)
	_check(_main.state == MAIN_SCRIPT.GameState.WON, "reaching the end transitions to WON")
	if _hud.win_panel != null:
		_check(_hud.win_panel.visible, "win screen shown on victory")


func _phase_restart() -> void:
	print("--- restart flow ---")
	var ev := InputEventKey.new()
	ev.physical_keycode = KEY_ENTER
	ev.pressed = true
	_main._unhandled_input(ev)  # WON -> start_game()
	await _settle(2)

	_check(_main.state == MAIN_SCRIPT.GameState.PLAYING, "ENTER transitions WON -> PLAYING (restart)")
	if _hud.win_panel != null:
		_check(not _hud.win_panel.visible, "win screen hidden after restart")
	_check(absf(_player.position.z) < 1.0, "player returned to spawn (z=%.2f)" % _player.position.z)
	_check(_player.health == _player.max_health, "health reset to full on restart (%.0f)" % _player.health)


func _phase_shoot_and_shatter() -> void:
	print("--- shoot -> shatter -> sound ---")
	var target_struct = _nearest_ahead_structure()
	_check(target_struct != null, "a structure is streamed ahead to shoot")
	if target_struct == null:
		return

	var pew0 := int(_audio.pew_played)
	var crash0 := int(_audio.crash_played)
	var target := _top_block_world(target_struct)
	_aim_at(target)
	await _settle(2)

	Input.action_press("fire")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("fire")
	await _settle(2)

	_check(_audio.pew_played == pew0 + 1, "firing played exactly one pew (%d -> %d)" % [pew0, _audio.pew_played])
	_check(target_struct.is_shattered, "shot shattered the aimed structure")
	_check(target_struct.blocks.size() >= 20, "shatter spawned debris (%d blocks)" % target_struct.blocks.size())
	_check(_audio.crash_played == crash0 + 1, "shatter played exactly one crash (%d -> %d)" % [crash0, _audio.crash_played])
	_check(_audio.last_crash_weight > 0.0, "crash weight recorded (%.1f kg)" % _audio.last_crash_weight)

	var all_rigid := true
	for b in target_struct.blocks:
		if not (b is RigidBody3D):
			all_rigid = false
	_check(all_rigid, "debris are independently simulated RigidBody3D blocks")


func _phase_debris_damage() -> void:
	print("--- debris -> damage ---")
	# Move the player to a clear spot and reset health, then fire a debris block
	# at them to prove the damage leg of the loop in the real scene.
	_player.global_position = Vector3(0.0, 0.85, 20.0)
	_player.health = _player.max_health
	_player.is_dead = false
	await _settle(2)

	var before: float = _player.health
	var block := _make_debris_block(Vector3(0.0, 0.85, 26.0), 5.0)
	add_child(block)
	block.linear_velocity = Vector3(0.0, 0.0, -14.0)
	await _settle(40)

	_check(_player.health < before, "moving debris collision reduced health (%.1f -> %.1f)" % [before, _player.health])
	_check(_player.health > 0.0, "a single debris hit is non-lethal (health %.1f)" % _player.health)


# --- helpers ---------------------------------------------------------------

func _nearest_ahead_structure():
	var best = null
	var best_z := -INF
	for s in _level.structures:
		if s.is_shattered:
			continue
		if s.position.z < _player.position.z and s.position.z > best_z:
			best_z = s.position.z
			best = s
	return best


func _top_block_world(s) -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_y := -INF
	for spec in s.block_specs:
		var p: Vector3 = spec["position"]
		if p.y > best_y:
			best_y = p.y
			best = p
	return s.global_position + best


func _aim_at(target: Vector3) -> void:
	var camera: Camera3D = _player.get_node("Camera3D") as Camera3D
	var cam_pos := target + Vector3(0.0, 0.0, STANDOFF)
	_player.global_position = cam_pos - Vector3(0.0, CAM_LOCAL_Y, 0.0)
	camera.look_at(target)


func _make_debris_block(pos: Vector3, mass: float) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.position = pos
	rb.mass = mass
	rb.gravity_scale = 0.0
	rb.continuous_cd = true
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.0, 1.0, 1.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	rb.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	rb.add_child(mi)
	return rb


func _finish() -> void:
	print("=== results: %d checks, %d failures ===" % [_checks, _failures.size()])
	if _failures.size() == 0:
		print("FULL-LOOP INTEGRATION TEST PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("  FAILED: ", f)
		print("FULL-LOOP INTEGRATION TEST FAIL")
		get_tree().quit(1)
