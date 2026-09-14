extends Node3D
## DestructibleStructure -- a procedurally generated tower/building that, on
## demand, shatters into many independently simulated RigidBody3D blocks.
##
## Public API for downstream nodes (node 3 = weapon, node 5 = audio):
##   build_structure(origin, seed)  -- generate and build the intact structure
##   shatter(impulse_origin, power) -- destroy it; returns the spawned debris
##   blocks: Array[RigidBody3D]     -- the spawned debris (populated by shatter)
##   block_specs: Array             -- the generated layout (shape/size/color per
##                                     block) so node 5 can scale audio to variety
##   is_shattered: bool             -- whether shatter() has already run
##   signal shattered(debris)       -- emitted once, right after shatter
##
## Node 3 can either connect to `shattered` or simply call `shatter(...)` and
## keep the returned Array. Node 5 can read `block_specs` (pre-shatter) or the
## RigidBody3D list in `blocks` (post-shatter) to drive audio variety.

const Generator := preload("res://scripts/destruction/structure_generator.gd")

signal shattered(debris: Array)

var blocks: Array[RigidBody3D] = []
var block_specs: Array = []
var is_shattered := false
var intact_body: StaticBody3D = null

var _origin := Vector3.ZERO
var _seed := -1
var _rng := RandomNumberGenerator.new()
var _physics_material: PhysicsMaterial = null


func build_structure(origin: Vector3 = Vector3.ZERO, seed: int = -1) -> void:
	_origin = origin
	_seed = seed
	if seed >= 0:
		_rng.seed = seed
	else:
		_rng.randomize()
	block_specs = Generator.generate(origin, _rng)
	_physics_material = _make_physics_material()
	_build_intact()


func shatter(impulse_origin: Vector3 = Vector3.INF, power: float = 1.0) -> Array[RigidBody3D]:
	if is_shattered:
		return blocks
	is_shattered = true

	var center := impulse_origin
	if center == Vector3.INF:
		center = _origin + _bounds_center()

	if intact_body != null:
		remove_child(intact_body)
		intact_body.queue_free()
		intact_body = null

	for spec in block_specs:
		var rb := _make_debris(spec)

		var offset: Vector3 = spec["position"] - center
		var dir := offset.normalized()
		if dir == Vector3.ZERO or dir.length() < 0.001:
			dir = Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(0.2, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()

		var speed := _rng.randf_range(4.0, 12.0) * power
		var up_boost := _rng.randf_range(1.5, 5.0)
		rb.linear_velocity = dir * speed + Vector3.UP * up_boost
		rb.angular_velocity = Vector3(
			_rng.randf_range(-6.0, 6.0),
			_rng.randf_range(-6.0, 6.0),
			_rng.randf_range(-6.0, 6.0),
		)

		add_child(rb)
		blocks.append(rb)

	shattered.emit(blocks)
	return blocks


func _build_intact() -> void:
	intact_body = StaticBody3D.new()
	intact_body.name = "IntactStructure"
	for spec in block_specs:
		var col := CollisionShape3D.new()
		col.shape = _make_shape(spec)
		col.position = spec["position"]
		col.rotation = spec["rotation"]
		intact_body.add_child(col)

		var mi := _make_mesh(spec)
		mi.position = spec["position"]
		mi.rotation = spec["rotation"]
		intact_body.add_child(mi)
	add_child(intact_body)


func _make_debris(spec: Dictionary) -> RigidBody3D:
	var rb := RigidBody3D.new()
	rb.name = "Debris_%04d" % blocks.size()
	rb.position = spec["position"]
	rb.rotation = spec["rotation"]
	rb.mass = _mass_for(spec)
	rb.linear_damp = 0.1
	rb.angular_damp = 0.3
	rb.physics_material_override = _physics_material
	rb.continuous_cd = true  # fast small blocks should not tunnel through the floor

	var col := CollisionShape3D.new()
	col.shape = _make_shape(spec)
	rb.add_child(col)

	rb.add_child(_make_mesh(spec))
	return rb


func _make_shape(spec: Dictionary) -> Shape3D:
	var size: Vector3 = spec["size"]
	match spec["shape"]:
		"cylinder":
			var c := CylinderShape3D.new()
			c.radius = size.x * 0.5
			c.height = size.y
			return c
		"sphere":
			var s := SphereShape3D.new()
			s.radius = size.x * 0.5
			return s
		_:
			var b := BoxShape3D.new()
			b.size = size
			return b


func _make_mesh(spec: Dictionary) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = spec["color"]
	mat.roughness = 0.75
	match spec["shape"]:
		"cylinder":
			var cm := CylinderMesh.new()
			cm.top_radius = spec["size"].x * 0.5
			cm.bottom_radius = spec["size"].x * 0.5
			cm.height = spec["size"].y
			mi.mesh = cm
		"sphere":
			var sm := SphereMesh.new()
			sm.radius = spec["size"].x * 0.5
			sm.height = spec["size"].x
			mi.mesh = sm
		_:
			var bm := BoxMesh.new()
			bm.size = spec["size"]
			mi.mesh = bm
	mi.material_override = mat
	return mi


func _mass_for(spec: Dictionary) -> float:
	var s: Vector3 = spec["size"]
	var vol := s.x * s.y * s.z
	return clampf(vol * 700.0, 0.3, 30.0)


func _bounds_center() -> Vector3:
	var mn := Vector3.INF
	var mx := -Vector3.INF
	for spec in block_specs:
		var p: Vector3 = spec["position"]
		mn = mn.min(p)
		mx = mx.max(p)
	return (mn + mx) * 0.5


func _make_physics_material() -> PhysicsMaterial:
	var pm := PhysicsMaterial.new()
	pm.friction = 0.6
	pm.bounce = 0.28
	return pm
