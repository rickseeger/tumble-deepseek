extends Node
## G16 node_3 weapon + damage loop test (headless, no vision).
## Run:  godot --headless --audio-driver Dummy --path . res://tests/WeaponDamageTest.tscn
## Exit 0 on pass.
##
## Asserts the completion contract programmatically:
##   1. Firing (via input injection) reduces ammo and hitting a structure
##      triggers its shatter -- deterministic and scriptable, no vision.
##   2. A moving debris block colliding with the player reduces player health
##      (scaled by mass/speed via DamageZone.impact_damage).
##   3. Health at zero triggers death, and respawn restores full health.

const PLAYER_SCENE := "res://scripts/player.tscn"
const DESTRUCTIBLE_SCRIPT := preload("res://scripts/destruction/destructible_structure.gd")
const DAMAGE_ZONE_SCRIPT := preload("res://scripts/damage/damage_zone.gd")

const STRUCTURE_SEED := 4242
const MIN_DEBRIS := 30
const CAM_LOCAL_Y := 0.85   # camera local offset above the player origin
const PLAYER_SPAWN := Vector3(0.0, 0.85, 0.0)
const STANDOFF := 6.0       # metres behind (toward +Z) the aim target

var _checks := 0
var _failures: Array[String] = []
var _player: CharacterBody3D = null
var _camera: Camera3D = null
var _structure = null
var _fired_count := 0
var _shot_landed_count := 0
var _died_count := 0
var _respawned_count := 0


func _ready() -> void:
	_run()


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS  ", label)
	else:
		_failures.append(label)
		print("  FAIL  ", label)


func _run() -> void:
	print("=== G16 node_3 weapon + damage loop test ===")

	# Pure damage-model assertions (deterministic, no physics required).
	_check(DAMAGE_ZONE_SCRIPT.impact_damage(5.0, 14.0) > 0.0, "impact_damage positive for a fast moving block")
	_check(DAMAGE_ZONE_SCRIPT.impact_damage(5.0, 1.0) == 0.0, "impact_damage zero below the impact-speed threshold")
	_check(DAMAGE_ZONE_SCRIPT.impact_damage(5.0, 14.0) == clampf(5.0 * 14.0 * 0.4, 2.0, 45.0),
		"impact_damage == mass*speed*0.4 (clamped)")
	_check(DAMAGE_ZONE_SCRIPT.impact_damage(10.0, 14.0) > DAMAGE_ZONE_SCRIPT.impact_damage(5.0, 14.0),
		"impact_damage scales with mass")
	_check(DAMAGE_ZONE_SCRIPT.impact_damage(5.0, 20.0) > DAMAGE_ZONE_SCRIPT.impact_damage(5.0, 10.0),
		"impact_damage scales with speed")

	_build_ground()
	_build_player()
	await _settle(3)

	await _phase_weapon()
	await _phase_damage()
	await _phase_death_restart()

	_finish()


func _settle(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


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
	_player.position = PLAYER_SPAWN
	add_child(_player)
	_player.set_spawn_point(PLAYER_SPAWN)
	_camera = _player.get_node("Camera3D") as Camera3D
	_player.weapon.fired.connect(func(_h): _fired_count += 1)
	_player.weapon.shot_landed.connect(func(_t, _p, _n): _shot_landed_count += 1)
	_player.died.connect(func(): _died_count += 1)
	_player.respawned.connect(func(): _respawned_count += 1)


func _phase_weapon() -> void:
	print("--- phase 1: weapon fire (ammo + structure shatter) ---")

	_structure = DESTRUCTIBLE_SCRIPT.new()
	_structure.name = "Structure"
	add_child(_structure)
	_structure.build_structure(Vector3.ZERO, STRUCTURE_SEED)
	await _settle(2)

	# Aim the camera dead-on at the top-most block's centre from a +Z standoff,
	# so the ray is guaranteed to pass through a real block.
	var target := _top_block_global()
	_aim_at(target)

	var ammo0 := int(_player.weapon.ammo)
	_check(_player.weapon.can_fire(), "weapon starts ready to fire (ammo=%d)" % ammo0)
	_check(not _structure.is_shattered, "structure starts intact")

	# Input injection: press the fire action for one physics frame.
	Input.action_press("fire")
	await get_tree().physics_frame
	await get_tree().physics_frame
	Input.action_release("fire")

	_check(_player.weapon.ammo == ammo0 - 1, "firing reduces ammo (%d -> %d)" % [ammo0, _player.weapon.ammo])
	_check(_fired_count >= 1, "fired signal emitted on shot")
	_check(_structure.is_shattered, "firing at a structure triggers its shatter")
	_check(_structure.blocks.size() >= MIN_DEBRIS,
		"shattered structure spawned %d debris (>= %d)" % [_structure.blocks.size(), MIN_DEBRIS])
	_check(_shot_landed_count >= 1, "shot_landed signal emitted on a hit")


func _phase_damage() -> void:
	print("--- phase 2: debris damage ---")

	# Isolate from phase-1 debris and reset the player.
	if _structure != null:
		_structure.queue_free()
		_structure = null
	await _settle(2)

	_player.global_position = PLAYER_SPAWN
	_player.health = _player.max_health
	_player.is_dead = false

	var before: float = _player.health
	var block := _make_debris_block(Vector3(0.0, 0.85, 4.0), 5.0)
	add_child(block)
	block.linear_velocity = Vector3(0.0, 0.0, -14.0)
	await _settle(40)

	_check(_player.health < before, "moving debris collision reduced health (%.1f -> %.1f)" % [before, _player.health])
	_check(_player.health > 0.0, "a single debris hit is non-lethal (health %.1f)" % _player.health)
	_check(_player.health <= before - 2.0, "damage is meaningful (>= min damage)")


func _phase_death_restart() -> void:
	print("--- phase 3: death / restart ---")

	_player.health = 1.0
	_player.take_damage(100.0)

	_check(_player.is_dead, "health at zero sets is_dead")
	_check(_player.health <= 0.0, "health clamped to zero on lethal damage")
	_check(_died_count >= 1, "died signal emitted on lethal damage")

	_player.respawn()

	_check(not _player.is_dead, "respawn clears is_dead")
	_check(_player.health == _player.max_health, "respawn restores full health (%.1f)" % _player.health)
	_check(_respawned_count >= 1, "respawned signal emitted")


func _top_block_global() -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_y := -INF
	for spec in _structure.block_specs:
		var p: Vector3 = spec["position"]
		if p.y > best_y:
			best_y = p.y
			best = p
	return _structure.global_position + best


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
		print("WEAPON + DAMAGE TEST PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("  FAILED: ", f)
		print("WEAPON + DAMAGE TEST FAIL")
		get_tree().quit(1)
