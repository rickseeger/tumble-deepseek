extends Node3D
## G16 scene builder: flat ground + props + destructible structures + the
## first-person player. Node 3 wires the weapon/damage/death loop into this
## scene: a HUD (health bar + ammo), death -> game-over overlay -> respawn, and
## a keyboard fire path. Structures are destroyed by the weapon now (the old
## debug "shatter all" key moved from F to T; F is the weapon trigger).

const PLAYER_SCENE := "res://scripts/player.tscn"
const DESTRUCTIBLE_SCRIPT := preload("res://scripts/destruction/destructible_structure.gd")
const HUD_SCRIPT := preload("res://scripts/ui/hud.gd")

const RESPAWN_DELAY := 2.0

var _destructibles: Array = []
var _player: CharacterBody3D = null
var _hud: CanvasLayer = null


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_props()
	_build_destructibles()
	_build_player()
	_build_hud()


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
	for d in _destructibles:
		d.queue_free()
	_destructibles.clear()
	_build_destructibles()
