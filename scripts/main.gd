extends Node3D
## G16 scene builder: flat ground + props + destructible structures + the
## first-person player. Node 4 replaces the two hard-coded structures with a
## streaming linear level: the player advances forward (-Z) through a seeded,
## generated sequence of structures whose density/size/height and debris danger
## ramp up monotonically with progress (see scripts/level/). Structures stream
## in ahead of the player and despawn behind, while a guaranteed clear centre
## lane keeps the run winnable. The weapon/damage/death loop (node 3) and the
## audio system (node 5) are unchanged.

const PLAYER_SCENE := "res://scripts/player.tscn"
const DESTRUCTIBLE_SCRIPT := preload("res://scripts/destruction/destructible_structure.gd")
const HUD_SCRIPT := preload("res://scripts/ui/hud.gd")
const LEVEL_MANAGER_SCRIPT := preload("res://scripts/level/level_manager.gd")

const LEVEL_SEED := 20260915
const LEVEL_LENGTH := 200.0
const RESPAWN_DELAY := 2.0

var _destructibles: Array = []
var _level = null
var _player: CharacterBody3D = null
var _hud: CanvasLayer = null


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_props()
	_build_level()
	_build_player()
	_build_hud()


func _process(_delta: float) -> void:
	# Forward-advance loop: stream structures ahead of the player and despawn
	# them once they fall behind.
	if _player != null and _level != null:
		_level.update(_player.position.z)


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
	shape.size = Vector3(400.0, 2.0, 600.0)
	var col := CollisionShape3D.new()
	col.shape = shape
	col.position = Vector3(0.0, -1.0, -150.0)
	ground.add_child(col)

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(400.0, 600.0)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = Vector3(0.0, 0.0, -150.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.36, 0.47, 0.30, 1.0)
	mat.roughness = 1.0
	mi.material_override = mat
	ground.add_child(mi)
	add_child(ground)


func _build_props() -> void:
	# Decorative props, all kept OUTSIDE the clear forward lane (|x| >= 4) so
	# they never block the player's advance.
	_add_box(Vector3(6.0, 1.0, -12.0), Vector3(2.0, 2.0, 2.0), Color(0.78, 0.33, 0.24))
	_add_box(Vector3(-6.0, 0.75, -16.0), Vector3(1.5, 1.5, 1.5), Color(0.85, 0.66, 0.20))
	_add_box(Vector3(5.5, 1.5, -20.0), Vector3(1.5, 3.0, 1.5), Color(0.27, 0.45, 0.72))
	_add_box(Vector3(-5.0, 0.5, -26.0), Vector3(1.0, 1.0, 1.0), Color(0.55, 0.55, 0.55))
	_add_cylinder(Vector3(-7.0, 1.0, -14.0), 1.0, 2.0, Color(0.70, 0.50, 0.80))


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


func _build_level() -> void:
	_level = LEVEL_MANAGER_SCRIPT.new()
	_level.name = "LevelManager"
	add_child(_level)
	_destructibles = _level.structures  # alias so tests/debug keys see live structures
	_level.configure(LEVEL_SEED, LEVEL_LENGTH)
	_level.update(0.0)


func _build_player() -> void:
	var packed := load(PLAYER_SCENE) as PackedScene
	if packed == null:
		push_error("player scene not found: " + PLAYER_SCENE)
		return
	var player := packed.instantiate()
	player.name = "Player"
	player.position = Vector3(0.0, 0.85, 0.0)
	add_child(player)
	_player = player
	_player.set_spawn_point(player.position)
	_player.health_changed.connect(_on_health_changed)
	_player.died.connect(_on_player_died)
	if _player.weapon != null:
		_player.weapon.ammo_changed.connect(_on_ammo_changed)


func _build_hud() -> void:
	_hud = HUD_SCRIPT.new()
	_hud.name = "HUD"
	add_child(_hud)
	_on_health_changed(_player.health, _player.max_health)
	if _player.weapon != null:
		_on_ammo_changed(_player.weapon.ammo)


func _on_health_changed(current: float, max_value: float) -> void:
	if _hud != null:
		_hud.set_health(current, max_value)


func _on_ammo_changed(ammo: int) -> void:
	if _hud != null:
		_hud.set_ammo(ammo)


func _on_player_died() -> void:
	if _hud != null:
		_hud.show_game_over()
	var timer := get_tree().create_timer(RESPAWN_DELAY)
	timer.timeout.connect(_respawn)


func _respawn() -> void:
	if _player == null:
		return
	_player.respawn()
	_reset_destructibles()
	if _hud != null:
		_hud.hide_game_over()


func _unhandled_input(event: InputEvent) -> void:
	# Debug keys for exercising the core by hand:
	#   T  -- shatter every intact destructible structure (the weapon does this
	#         per-structure now; T is the all-at-once debug stand-in).
	#   R  -- rebuild fresh structures (and revive the player if dead).
	if event is InputEventKey and event.pressed and not event.echo:
		if event.physical_keycode == KEY_T:
			for d in _destructibles:
				if not d.is_shattered:
					d.shatter(d.global_position + Vector3(0.0, 2.0, 0.0), 1.1)
		elif event.physical_keycode == KEY_R:
			_reset_destructibles()
			if _player != null and _player.is_dead:
				_player.respawn()
				if _hud != null:
					_hud.hide_game_over()


func _reset_destructibles() -> void:
	if _level == null:
		_build_level()
		return
	_level.reset(LEVEL_SEED, LEVEL_LENGTH)
	_level.update(_player.position.z if _player != null else 0.0)
