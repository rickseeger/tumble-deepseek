extends Node
## G16 node_5 audio test (headless, no vision, no audible output -- the Dummy
## audio driver makes play() a no-op, so everything here asserts on loaded
## sample data and on the wiring counters the AudioManager records per trigger).
##
## Run:  godot --headless --audio-driver Dummy --path . res://tests/AudioTest.tscn
## Exit 0 on pass.
##
## Asserts the node-5 completion contract programmatically:
##   1. all 8 generated WAVs load off disk and decode to non-empty PCM;
##   2. the pure size -> sound mapping is monotonic (bigger = deeper + louder +
##      more crash tiers + more debris layers);
##   3. firing the weapon triggers a pew (per shot);
##   4. shattering a structure triggers a crash whose recorded weight equals the
##      true total debris mass and whose variety matches the block layout;
##   5. firing at a loose debris block triggers a mass-scaled impact.

const PLAYER_SCENE := "res://scripts/player.tscn"
const DESTRUCTIBLE_SCRIPT := preload("res://scripts/destruction/destructible_structure.gd")

const STRUCTURE_SEED := 4242
const CAM_LOCAL_Y := 0.85
const STANDOFF := 6.0

var _checks := 0
var _failures: Array[String] = []
var _player: CharacterBody3D = null
var _camera: Camera3D = null
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
	print("=== G16 node_5 audio test ===")

	_audio = get_node_or_null("/root/AudioManager")
	_check(_audio != null, "AudioManager autoload is registered")

	if _audio == null:
		_finish()
		return

	_phase_streams()
	_phase_mapping()
	_phase_wiring()

	_finish()


func _phase_streams() -> void:
	print("--- phase 1: generated samples load + decode ---")
	_check(_audio._pew_streams.size() == 3, "3 pew streams loaded (%d)" % _audio._pew_streams.size())
	_check(_audio._crash_streams.size() == 4, "4 crash tiers loaded (%d)" % _audio._crash_streams.size())
	_check(_audio._impact_stream != null, "impact stream loaded")

	var all_ok := true
	for s in _audio._pew_streams:
		if s == null or s.get_length() <= 0.0 or s.data.size() == 0:
			all_ok = false
	for s in _audio._crash_streams:
		if s == null or s.get_length() <= 0.0 or s.data.size() == 0:
			all_ok = false
	if _audio._impact_stream == null or _audio._impact_stream.get_length() <= 0.0 or _audio._impact_stream.data.size() == 0:
		all_ok = false
	_check(all_ok, "every stream decodes to non-empty 16-bit PCM")

	# Crash tiers get longer as size grows (a structure-size length cue).
	var lens: Array[float] = []
	for s in _audio._crash_streams:
		lens.append(s.get_length())
	_check(lens[0] < lens[1] and lens[1] < lens[2] and lens[2] < lens[3],
		"crash tiers lengthen with size (%s)" % [lens])


func _phase_mapping() -> void:
	print("--- phase 2: size -> sound mapping (pure functions) ---")
	_check(AudioManager.tier_for_weight(500.0) == 0, "small weight -> tier 0 (small)")
	_check(AudioManager.tier_for_weight(2000.0) == 1, "medium weight -> tier 1 (medium)")
	_check(AudioManager.tier_for_weight(3000.0) == 2, "large weight -> tier 2 (large)")
	_check(AudioManager.tier_for_weight(5000.0) == 3, "huge weight -> tier 3 (huge)")

	var p_small: float = AudioManager.pitch_for_weight(500.0)
	var p_huge: float = AudioManager.pitch_for_weight(5000.0)
	_check(p_huge < p_small, "heavier -> lower pitch (%.3f < %.3f)" % [p_huge, p_small])

	var v_small: float = AudioManager.volume_for_weight(500.0)
	var v_huge: float = AudioManager.volume_for_weight(5000.0)
	_check(v_huge > v_small, "heavier -> louder (%.1f dB > %.1f dB)" % [v_huge, v_small])

	_check(AudioManager.layers_for_variety(3) == 1 and AudioManager.layers_for_variety(12) == 2,
		"more block variety -> more crash layers")

	var pi_light: float = AudioManager.pitch_for_impact(1.0)
	var pi_heavy: float = AudioManager.pitch_for_impact(30.0)
	_check(pi_heavy < pi_light, "heavier debris -> lower impact pitch (%.3f < %.3f)" % [pi_heavy, pi_light])


func _phase_wiring() -> void:
	print("--- phase 3: triggers map to the correct events ---")
	_build_ground()
	_build_player()
	await _settle(3)

	# 3a. weapon fire -> pew (per shot).
	var pew0 := int(_audio.pew_played)
	Input.action_press("fire")
	await _settle(2)
	Input.action_release("fire")
	_check(_audio.pew_played == pew0 + 1, "firing triggers exactly one pew (%d -> %d)" % [pew0, _audio.pew_played])

	# 3b. structure shatter -> crash, weight == true total debris mass.
	var structure = DESTRUCTIBLE_SCRIPT.new()
	structure.name = "AudioStructure"
	add_child(structure)
	structure.build_structure(Vector3.ZERO, STRUCTURE_SEED)
	await _settle(2)

	var crash0 := int(_audio.crash_played)
	var debris: Array = structure.shatter(Vector3.INF, 1.0)
	var expected_weight := 0.0
	for b in debris:
		expected_weight += b.mass
	_check(_audio.crash_played == crash0 + 1, "shatter triggers exactly one crash (%d -> %d)" % [crash0, _audio.crash_played])
	_check(absf(_audio.last_crash_weight - expected_weight) < 0.01,
		"crash weight == total debris mass (%.1f kg)" % _audio.last_crash_weight)
	_check(_audio.last_crash_weight > 0.0, "crash weight is positive")
	_check(_audio.last_crash_variety >= 3, "crash variety reflects the varied block layout (%d distinct size/shape combos)" % _audio.last_crash_variety)

	# 3c. firing at a loose debris block -> mass-scaled impact.
	structure.queue_free()
	await _settle(2)

	var block := _make_debris_block(Vector3(0.0, 0.85, -8.0), 5.0)
	add_child(block)
	await _settle(2)
	_aim_at(block.global_position)

	var impact0 := int(_audio.impact_played)
	Input.action_press("fire")
	await _settle(2)
	Input.action_release("fire")
	_check(_audio.impact_played == impact0 + 1, "firing at loose debris triggers an impact (%d -> %d)" % [impact0, _audio.impact_played])
	_check(_audio.last_impact_mass > 0.0, "impact mass recorded (%.2f kg)" % _audio.last_impact_mass)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var shape := BoxShape3D.new()
	shape.size = Vector3(200.0, 2.0, 200.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, -1.0, 0.0)
	ground.add_child(col)
	add_child(ground)


func _build_player() -> void:
	var packed: PackedScene = load(PLAYER_SCENE)
	_player = packed.instantiate()
	_player.name = "Player"
	_player.position = Vector3(0.0, 0.85, 0.0)
	add_child(_player)
	_player.set_spawn_point(Vector3(0.0, 0.85, 0.0))
	_camera = _player.get_node("Camera3D") as Camera3D


func _aim_at(target: Vector3) -> void:
	var cam_pos := target + Vector3(0.0, 0.0, STANDOFF)
	_player.global_position = cam_pos - Vector3(0.0, CAM_LOCAL_Y, 0.0)
	_camera.look_at(target)


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
		print("AUDIO TEST PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("  FAILED: ", f)
		print("AUDIO TEST FAIL")
		get_tree().quit(1)
