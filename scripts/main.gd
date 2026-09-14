extends Node3D
## G16 node 1 scene builder: flat ground + a few static test objects +
## the first-person player. Builds the scene in code so it is easy to
## reason about and diff.

const PLAYER_SCENE := "res://scripts/player.tscn"
const DESTRUCTIBLE_SCRIPT := preload("res://scripts/destruction/destructible_structure.gd")

var _destructibles: Array = []


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_props()
	_build_destructibles()
	_build_player()


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.53, 0.81, 0.92, 1.0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.58, 0.62, 1.0)
	env.ambient_light_energy = 1.0
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-50.0, -30.0, 0.0)
	sun.light_energy = 1.1
	sun.shadow_enabled = true
	add_child(sun)


func _build_ground() -> void:
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	var shape := BoxShape3D.new()
	shape.size = Vector3(200.0, 2.0, 200.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, -1.0, 0.0)
	ground.add_child(col)

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(200.0, 200.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.47, 0.30, 1.0)
	mat.roughness = 1.0
	mi.material_override = mat
	ground.add_child(mi)
	add_child(ground)


func _build_props() -> void:
	_add_box(Vector3(0.0, 1.0, -12.0), Vector3(2.0, 2.0, 2.0), Color(0.78, 0.33, 0.24))
	_add_box(Vector3(4.0, 0.75, -16.0), Vector3(1.5, 1.5, 1.5), Color(0.85, 0.66, 0.20))
	_add_box(Vector3(-3.5, 1.5, -20.0), Vector3(1.5, 3.0, 1.5), Color(0.27, 0.45, 0.72))
	_add_box(Vector3(1.5, 0.5, -26.0), Vector3(1.0, 1.0, 1.0), Color(0.55, 0.55, 0.55))
	_add_cylinder(Vector3(-6.0, 1.0, -14.0), 1.0, 2.0, Color(0.70, 0.50, 0.80))


func _add_box(pos: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := BoxShape3D.new()
	shape.size = size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := BoxMesh.new()
	mesh.size = size
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)


func _add_cylinder(pos: Vector3, radius: float, height: float, color: Color) -> void:
	var body := StaticBody3D.new()
	body.position = pos
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = height
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.7
	mi.material_override = mat
	body.add_child(mi)
	add_child(body)


func _build_player() -> void:
	var packed := load(PLAYER_SCENE) as PackedScene
	if packed == null:
		push_error("player scene not found: " + PLAYER_SCENE)
		return
	var player := packed.instantiate()
	player.name = "Player"
	player.position = Vector3(0.0, 0.85, 0.0)
	add_child(player)

func _build_destructibles() -> void:
	_add_destructible(Vector3(0.0, 0.0, -22.0), 4242)
	_add_destructible(Vector3(11.0, 0.0, -30.0), 7777)


func _add_destructible(pos: Vector3, seed: int) -> void:
	var d = DESTRUCTIBLE_SCRIPT.new()
	d.name = "Destructible_%d" % _destructibles.size()
	d.position = pos
	add_child(d)
	d.build_structure(Vector3.ZERO, seed)
	_destructibles.append(d)


func _unhandled_input(event: InputEvent) -> void:
	# Debug trigger keys so the destruction core can be exercised by hand:
	#   F  -- shatter every intact destructible structure (weapon node will call
	#         shatter() itself later; this is the stand-in trigger).
	#   R  -- rebuild fresh structures.
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_F:
			for d in _destructibles:
				if not d.is_shattered:
					d.shatter(d.global_position + Vector3(0.0, 2.0, 0.0), 1.1)
		elif event.physical_keycode == KEY_R:
			_reset_destructibles()


func _reset_destructibles() -> void:
	for d in _destructibles:
		d.queue_free()
	_destructibles.clear()
	_build_destructibles()

