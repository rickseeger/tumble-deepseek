extends Node
## Physics stress test: spawn 250 rigid bodies above the ground and let them
## fall/settle, then verify none tunnel through the floor and the simulation
## still steps. Run headless:
##   godot --headless --path . res://tests/StressTest.tscn
## Exit code 0 on pass.

const BODY_COUNT := 250
const STEP_FRAMES := 360
const GROUND_Y := 0.0

var _bodies: Array[RigidBody3D] = []


func _ready() -> void:
	_run()


func _run() -> void:
	print("=== G16 stress test ===")
	print("physics_engine=", ProjectSettings.get_setting("physics/3d/physics_engine"))

	_build_ground()
	_spawn_bodies()

	var t0 := Time.get_ticks_msec()
	for i in range(STEP_FRAMES):
		await get_tree().physics_frame
	var elapsed_ms := Time.get_ticks_msec() - t0

	_analyze(elapsed_ms)


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


func _spawn_bodies() -> void:
	var side := int(ceil(sqrt(BODY_COUNT)))
	for i in range(BODY_COUNT):
		var rb := RigidBody3D.new()
		rb.name = "Debris_%03d" % i
		var row := i / side
		var coln := i % side
		var x := (coln - side / 2.0) * 1.4
		var z := (row - side / 2.0) * 1.4
		rb.position = Vector3(x, 8.0 + (i % 5) * 1.5, z)
		rb.rotation = Vector3(randf() * PI, randf() * PI, randf() * PI)

		var shape := BoxShape3D.new()
		var sx := 0.4 + randf() * 0.5
		var sy := 0.4 + randf() * 0.5
		var sz := 0.4 + randf() * 0.5
		shape.size = Vector3(sx, sy, sz)
		var colshape := CollisionShape3D.new()
		colshape.shape = shape
		rb.add_child(colshape)

		var mesh := BoxMesh.new()
		mesh.size = shape.size
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(randf(), randf(), randf())
		mi.material_override = mat
		rb.add_child(mi)

		add_child(rb)
		_bodies.append(rb)


func _analyze(elapsed_ms: int) -> void:
	var sleeping := 0
	var fell_through := 0
	var max_y := -INF
	var min_y := INF
	for rb in _bodies:
		var y := rb.global_position.y
		min_y = minf(min_y, y)
		max_y = maxf(max_y, y)
		if y < GROUND_Y - 2.0:
			fell_through += 1
		if rb.sleeping:
			sleeping += 1

	print("spawned=", BODY_COUNT)
	print("elapsed_ms=", elapsed_ms)
	print("sleeping=", sleeping)
	print("fell_through=", fell_through)
	print("min_y=", min_y)
	print("max_y=", max_y)
	print("physics_steps_survived=", STEP_FRAMES)

	var ok := true
	if _bodies.size() != BODY_COUNT:
		ok = false
	if fell_through > 0:
		ok = false
		print("FAIL: %d bodies fell through the floor" % fell_through)
	if max_y < 0.5:
		ok = false
		print("FAIL: bodies did not fall (max_y too low)")

	if ok:
		print("STRESS TEST PASS (%d bodies stepped for %d frames)" % [BODY_COUNT, STEP_FRAMES])
		get_tree().quit(0)
	else:
		print("STRESS TEST FAIL")
		get_tree().quit(1)

