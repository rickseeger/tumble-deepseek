extends Node
## G16 node_8 -- weapon determinism test (headless, no vision).
## Contract (5): the hitscan weapon is deterministic for identical inputs.
##
## Two identically-seeded structures, two identically-aimed cameras, two
## identical shots -> identical local hit point, identical hit normal, and
## identical ammo consumption. Plus a direct check that the underlying physics
## ray query is a pure function of the scene: two back-to-back raycasts from
## the same camera transform return the identical hit.
##
## Run:  godot --headless --audio-driver Dummy --path . res://tests/WeaponDeterminismTest.tscn
## Exit 0 on pass.

const PLAYER_SCENE := "res://scripts/player.tscn"
const DESTRUCTIBLE_SCRIPT := preload("res://scripts/destruction/destructible_structure.gd")

const STRUCTURE_SEED := 4242
const CAM_LOCAL_Y := 0.85   # camera local offset above the player origin
const STANDOFF := 6.0       # metres behind (toward +Z) the aim target
const HIT_EPS := 0.005
const NORMAL_EPS := 0.001

var _checks := 0
var _failures: Array[String] = []


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
	print("=== G16 node_8 weapon determinism test ===")

	_build_ground()

	var p1 := _build_player(Vector3(0.0, 0.85, 0.0))
	var s1 = _build_structure(Vector3(0.0, 0.0, 0.0), "StructA")
	var p2 := _build_player(Vector3(0.0, 0.85, -80.0))
	var s2 = _build_structure(Vector3(0.0, 0.0, -80.0), "StructB")

	await _settle(3)

	# --- direct raycast determinism: two identical queries, no stepping ---
	_aim_at(p1, _top_block_world(s1))
	var r1: Dictionary = p1.weapon._raycast()
	var r2: Dictionary = p1.weapon._raycast()
	_check(not r1.is_empty() and not r2.is_empty(), "raycast hits the aimed structure")
	_check(_hit_same(r1, r2), "ray query is a pure function of the scene (two back-to-back raycasts identical)")

	# --- end-to-end: two identical shots -> identical outcome ---
	var ammo_a := int(p1.weapon.ammo)
	var ammo_b := int(p2.weapon.ammo)
	_check(ammo_a == ammo_b and ammo_a > 0, "both weapons start with identical ammo (%d)" % ammo_a)

	_aim_at(p1, _top_block_world(s1))
	_aim_at(p2, _top_block_world(s2))

	var hit_a: Dictionary = p1.weapon.fire()
	var hit_b: Dictionary = p2.weapon.fire()

	_check(not hit_a.is_empty() and not hit_b.is_empty(), "both shots land on a structure")
	var local_a: Vector3 = (hit_a["position"] as Vector3) - (s1.global_position as Vector3)
	var local_b: Vector3 = (hit_b["position"] as Vector3) - (s2.global_position as Vector3)
	_check(_vec_close(local_a, local_b, HIT_EPS),
		"identical inputs -> identical local hit point (%s vs %s)" % [str(local_a), str(local_b)])
	_check(_vec_close(hit_a["normal"] as Vector3, hit_b["normal"] as Vector3, NORMAL_EPS),
		"identical inputs -> identical hit normal (%s vs %s)" % [hit_a["normal"], hit_b["normal"]])
	_check(int(p1.weapon.ammo) == ammo_a - 1 and int(p2.weapon.ammo) == ammo_b - 1,
		"identical inputs -> identical ammo consumption (%d -> %d)" % [ammo_a, int(p1.weapon.ammo)])
	_check(s1.is_shattered and s2.is_shattered, "identical inputs -> both shots shattered their target identically")

	_finish()


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var shape := BoxShape3D.new()
	shape.size = Vector3(400.0, 2.0, 400.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, -1.0, -40.0)
	ground.add_child(col)
	add_child(ground)


func _build_player(pos: Vector3) -> CharacterBody3D:
	var packed: PackedScene = load(PLAYER_SCENE)
	var p: CharacterBody3D = packed.instantiate()
	p.name = "Player"
	p.position = pos
	add_child(p)
	p.set_spawn_point(pos)
	return p


func _build_structure(pos: Vector3, node_name: String):
	var s = DESTRUCTIBLE_SCRIPT.new()
	s.name = node_name
	s.position = pos
	add_child(s)
	s.build_structure(Vector3.ZERO, STRUCTURE_SEED)
	return s


func _top_block_world(s) -> Vector3:
	var best: Vector3 = Vector3.ZERO
	var best_y := -INF
	for spec in s.block_specs:
		var p: Vector3 = spec["position"]
		if p.y > best_y:
			best_y = p.y
			best = p
	return s.global_position + best


func _aim_at(player: CharacterBody3D, target: Vector3) -> void:
	var camera: Camera3D = player.get_node("Camera3D") as Camera3D
	var cam_pos := target + Vector3(0.0, 0.0, STANDOFF)
	player.global_position = cam_pos - Vector3(0.0, CAM_LOCAL_Y, 0.0)
	camera.look_at(target)


func _hit_same(a: Dictionary, b: Dictionary) -> bool:
	if a.is_empty() or b.is_empty():
		return a.is_empty() and b.is_empty()
	return _vec_close(a["position"], b["position"], HIT_EPS) \
		and _vec_close(a["normal"], b["normal"], NORMAL_EPS) \
		and int(a.get("collider_id", -1)) == int(b.get("collider_id", -1))


func _vec_close(a: Vector3, b: Vector3, eps: float) -> bool:
	return (a - b).length() < eps


func _finish() -> void:
	print("=== results: %d checks, %d failures ===" % [_checks, _failures.size()])
	if _failures.size() == 0:
		print("WEAPON DETERMINISM TEST PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("  FAILED: ", f)
		print("WEAPON DETERMINISM TEST FAIL")
		get_tree().quit(1)
