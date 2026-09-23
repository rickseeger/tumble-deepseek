extends Node
## Destruction-core automated test (headless, no vision).
## Run:  godot --headless --audio-driver Dummy --path . res://tests/DestructionTest.tscn
## Exit 0 on pass.
##
## Generates a structure, triggers a shatter, dumps per-frame per-block state to
## a CSV (path from $G16_DUMP_PATH, else user://destruction_frames.csv) and
## asserts programmatically that:
##   * Jolt physics engine is active (code-level)
##   * the intact structure is one StaticBody3D, and shatter spawns >= 30
##     independently simulated RigidBody3D blocks (code-level, no vision)
##   * block sizes and shapes vary (>= 3 distinct dimensions, >= 2 shape types)
##   * every debris body has non-zero random linear and angular velocity
##   * gravity is 9.8, and blocks accelerate downward under it
##   * velocity damping decays a moving block's speed over time
##   * blocks bounce/roll then decay to rest (velocity below threshold), none
##     falling through the ground plane.

const DESTRUCTIBLE_SCRIPT := preload("res://scripts/destruction/destructible_structure.gd")

const STRUCTURE_SEED := 4242
const MIN_DEBRIS := 30
const STEP_FRAMES := 900
const GROUND_Y := 0.0
const SETTLE_LIN := 0.25
const SETTLE_ANG := 0.35
const FALL_EPSILON := 0.5

var _checks := 0
var _failures: Array[String] = []
var _structure = null
var _dump_file: FileAccess = null


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
	print("=== G16 node_2 destruction-core test ===")

	var engine := str(ProjectSettings.get_setting("physics/3d/physics_engine"))
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity"))
	print("physics_engine=", engine)
	print("gravity=", gravity)
	_check(engine == "Jolt Physics", "Jolt Physics engine is active")
	_check(absf(gravity - 9.8) < 0.01, "gravity is 9.8 m/s^2")

	_open_dump()
	_build_ground()

	await _check_downward_acceleration()
	await _check_velocity_damping()

	_structure = DESTRUCTIBLE_SCRIPT.new()
	_structure.name = "Structure"
	add_child(_structure)
	_structure.build_structure(Vector3.ZERO, STRUCTURE_SEED)

	await get_tree().physics_frame
	await get_tree().physics_frame

	# --- pre-shatter integrity (code-level) ---
	_check(_structure.intact_body != null and _structure.intact_body is StaticBody3D,
		"intact structure is a single StaticBody3D (to be shattered into rigid bodies)")
	_check(_structure.block_specs.size() >= MIN_DEBRIS,
		"generated %d blocks (>= %d)" % [_structure.block_specs.size(), MIN_DEBRIS])

	var variety := _assess_variety(_structure.block_specs)
	_check(variety["distinct_sizes"] >= 3,
		"block sizes vary (%d distinct dimensions)" % variety["distinct_sizes"])
	_check(variety["distinct_shapes"] >= 2,
		"block shapes vary (%d distinct shapes: %s)" % [variety["distinct_shapes"], variety["shapes"]])

	var spawn_ys: Array[float] = []
	for spec in _structure.block_specs:
		spawn_ys.append(float(spec["position"].y))
	var max_spawn_y := 0.0
	for y in spawn_ys:
		max_spawn_y = maxf(max_spawn_y, y)

	# --- trigger shatter ---
	var debris: Array = _structure.shatter(Vector3.INF, 1.0)
	_check(debris.size() >= MIN_DEBRIS, "shatter spawned %d debris (>= %d)" % [debris.size(), MIN_DEBRIS])
	_check(_structure.blocks.size() == debris.size(), "blocks list exposed (%d bodies)" % _structure.blocks.size())
	_check(_structure.is_shattered, "is_shattered flag set")

	# --- independently simulated RigidBody3D (code-level) ---
	var all_rigid := true
	for b in debris:
		if not (b is RigidBody3D):
			all_rigid = false
	_check(all_rigid, "every debris is an independently simulated RigidBody3D (not one static mesh)")

	# --- launch state, sampled same frame before stepping ---
	var nonzero_lin := true
	var nonzero_ang := true
	for b in debris:
		if b.linear_velocity.length() < 0.01:
			nonzero_lin = false
		if b.angular_velocity.length() < 0.01:
			nonzero_ang = false
	_check(nonzero_lin, "every debris has non-zero random linear velocity at launch")
	_check(nonzero_ang, "every debris has non-zero random angular velocity at launch")

	# --- step the simulation, dumping per-frame per-block state ---
	for f in range(STEP_FRAMES):
		await get_tree().physics_frame
		if f % 15 == 0:
			_dump_frame(f, debris)

	# --- settle analysis ---
	var settled := true
	var fell_through := 0
	var min_y := INF
	var max_y := -INF
	var sleeping := 0
	for b in debris:
		var y: float = b.global_position.y
		min_y = minf(min_y, y)
		max_y = maxf(max_y, y)
		if b.sleeping:
			sleeping += 1
		var lin: float = b.linear_velocity.length()
		var ang: float = b.angular_velocity.length()
		if not b.sleeping and (lin >= SETTLE_LIN or ang >= SETTLE_ANG):
			settled = false
		if y < GROUND_Y - FALL_EPSILON:
			fell_through += 1

	print("debris=%d sleeping=%d min_y=%.3f max_y=%.3f" % [debris.size(), sleeping, min_y, max_y])
	_check(settled, "all debris settled (linear<%.2f & angular<%.2f, or sleeping)" % [SETTLE_LIN, SETTLE_ANG])
	_check(fell_through == 0, "no debris fell through the ground (fell_through=%d)" % fell_through)
	_check(min_y >= GROUND_Y - FALL_EPSILON, "no debris below ground plane (min_y=%.3f)" % min_y)
	_check(max_y < max_spawn_y, "debris fell under gravity (settled max_y %.2f < spawn max %.2f)" % [max_y, max_spawn_y])

	_close_dump()
	_finish()


## Contract (2): downward acceleration -- a freely released block gains
## downward speed over successive frames (gravity accelerates it downward).
func _check_downward_acceleration() -> void:
	var rb := _make_test_block(Vector3(0.0, 8.0, 0.0), Vector3(0.5, 0.5, 0.5))
	rb.linear_velocity = Vector3.ZERO
	rb.angular_velocity = Vector3.ZERO
	add_child(rb)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var v1: float = rb.linear_velocity.y
	for i in range(10):
		await get_tree().physics_frame
	var v2: float = rb.linear_velocity.y
	_check(v2 < v1, "downward acceleration: falling block's vy decreases (%.3f -> %.3f m/s)" % [v1, v2])
	_check(v1 < 0.0 and v2 < 0.0, "falling block moves downward under gravity (vy < 0)")
	rb.queue_free()


## Contract (2): velocity damping -- a block with the same linear/angular damp
## as debris (0.1 / 0.3) loses speed over time even with gravity disabled.
func _check_velocity_damping() -> void:
	var rb := _make_test_block(Vector3(0.0, 4.0, 0.0), Vector3(0.5, 0.5, 0.5))
	rb.gravity_scale = 0.0
	rb.linear_damp = 0.1     # matches debris blocks from _make_debris
	rb.angular_damp = 0.3    # matches debris blocks from _make_debris
	rb.linear_velocity = Vector3(6.0, 0.0, 0.0)
	rb.angular_velocity = Vector3.ZERO
	add_child(rb)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var s1: float = rb.linear_velocity.length()
	for i in range(30):
		await get_tree().physics_frame
	var s2: float = rb.linear_velocity.length()
	_check(s2 < s1, "velocity damping: moving block slows over time (%.3f -> %.3f m/s)" % [s1, s2])
	rb.queue_free()


func _make_test_block(pos: Vector3, size: Vector3) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.position = pos
	rb.mass = 1.0
	rb.continuous_cd = true
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	rb.add_child(col)
	return rb


func _assess_variety(specs: Array) -> Dictionary:
	var sizes := {}
	var shapes := {}
	for spec in specs:
		var s: Vector3 = spec["size"]
		var key := "%.2fx%.2fx%.2f" % [s.x, s.y, s.z]
		sizes[key] = true
		shapes[spec["shape"]] = true
	return {"distinct_sizes": sizes.size(), "distinct_shapes": shapes.size(), "shapes": shapes.keys()}


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


func _open_dump() -> void:
	var path := OS.get_environment("G16_DUMP_PATH")
	if path == "":
		path = "user://destruction_frames.csv"
	_dump_file = FileAccess.open(path, FileAccess.WRITE)
	if _dump_file == null:
		push_warning("could not open dump file: " + path)
	else:
		print("dumping per-frame state to ", path)
		_dump_file.store_line("frame,body,pos_x,pos_y,pos_z,lin_speed,ang_speed,sleeping")


func _dump_frame(f: int, debris: Array) -> void:
	if _dump_file == null:
		return
	for i in range(debris.size()):
		var b: RigidBody3D = debris[i]
		var p := b.global_position
		_dump_file.store_line("%d,%d,%.3f,%.3f,%.3f,%.3f,%.3f,%d" % [
			f, i, p.x, p.y, p.z,
			b.linear_velocity.length(), b.angular_velocity.length(), int(b.sleeping),
		])


func _close_dump() -> void:
	if _dump_file != null:
		_dump_file.close()
		_dump_file = null


func _finish() -> void:
	print("=== results: %d checks, %d failures ===" % [_checks, _failures.size()])
	if _failures.size() == 0:
		print("DESTRUCTION TEST PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("  FAILED: ", f)
		print("DESTRUCTION TEST FAIL")
		get_tree().quit(1)
