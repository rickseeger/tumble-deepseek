extends CharacterBody3D
## First-person controller for Tumble (G16). Mouse-look + WASD movement, jump,
## head-height camera. Also carries the node-3 additions:
##   * the hitscan weapon (child of the camera, fires on the "fire" action);
##   * health/damage state with a hazard hitbox (DamageZone) that converts
##     debris impacts into damage;
##   * death (game-over) and respawn flow.
##
## Two fire paths both land on the same `weapon.fire()`:
##   * keyboard "fire" action (F), polled in _physics_process -- this is what
##     automated tests drive with `Input.action_press("fire")`;
##   * left mouse click while the pointer is captured.
##
## apply_look() is kept so automated tests can drive the exact same code path
## as the input handler. Health is a plain float so logic tests can assert on
## it without vision.

const MOUSE_SENSITIVITY := 0.002
const WALK_SPEED := 6.0
const GRAVITY := 9.8
const JUMP_VELOCITY := 4.5
const CAPSULE_HALF_HEIGHT := 0.85
const HEAD_HEIGHT := 1.7

const WEAPON_SCRIPT := preload("res://scripts/weapon/weapon.gd")
const DAMAGE_ZONE_SCRIPT := preload("res://scripts/damage/damage_zone.gd")

signal health_changed(current: float, max: float)
signal died
signal respawned

@onready var camera: Camera3D = $Camera3D

var max_health := 100.0
var health := 100.0
var is_dead := false
var weapon: Node3D = null
var damage_zone: Area3D = null
var spawn_point := Vector3.ZERO


func _ready() -> void:
	_register_input_actions()
	if DisplayServer.get_name() != "headless":
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	camera.position = Vector3(0.0, HEAD_HEIGHT - CAPSULE_HALF_HEIGHT, 0.0)
	spawn_point = global_position

	weapon = WEAPON_SCRIPT.new()
	weapon.name = "Weapon"
	camera.add_child(weapon)
	weapon.configure(self)

	damage_zone = DAMAGE_ZONE_SCRIPT.new()
	damage_zone.name = "DamageZone"
	add_child(damage_zone)
	damage_zone.damaged.connect(_on_damaged)

	health_changed.emit(health, max_health)


func _register_input_actions() -> void:
	_add_action("move_forward", [KEY_W, KEY_UP])
	_add_action("move_back", [KEY_S, KEY_DOWN])
	_add_action("move_left", [KEY_A, KEY_LEFT])
	_add_action("move_right", [KEY_D, KEY_RIGHT])
	_add_action("jump", [KEY_SPACE])
	_add_action("fire", [KEY_F])
	_add_action("ui_cancel", [KEY_ESCAPE])


func _add_action(action: StringName, physical_keys: Array) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action)
	for key in physical_keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = key
		InputMap.action_add_event(action, ev)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		apply_look(event.relative)
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if is_dead:
			return
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			if weapon != null:
				weapon.fire()
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func apply_look(relative: Vector2) -> void:
	rotate_y(-relative.x * MOUSE_SENSITIVITY)
	camera.rotate_x(-relative.y * MOUSE_SENSITIVITY)
	camera.rotation.x = clampf(camera.rotation.x, deg_to_rad(-89.0), deg_to_rad(89.0))


func _physics_process(delta: float) -> void:
	if is_dead:
		return

	# Keyboard fire (and the test injection path): hold F to auto-fire at the
	# weapon's cooldown rate.
	if Input.is_action_pressed("fire") and weapon != null:
		weapon.fire()

	if not is_on_floor():
		velocity += Vector3.DOWN * GRAVITY * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	if Input.is_action_just_pressed("jump") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := (transform.basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()

	if direction != Vector3.ZERO:
		velocity.x = direction.x * WALK_SPEED
		velocity.z = direction.z * WALK_SPEED
	else:
		velocity.x = move_toward(velocity.x, 0.0, WALK_SPEED)
		velocity.z = move_toward(velocity.z, 0.0, WALK_SPEED)

	move_and_slide()


func take_damage(amount: float, source: Node = null) -> void:
	if is_dead:
		return
	health = clampf(health - amount, 0.0, max_health)
	health_changed.emit(health, max_health)
	if health <= 0.0:
		die()


func heal(amount: float) -> void:
	if is_dead:
		return
	health = clampf(health + amount, 0.0, max_health)
	health_changed.emit(health, max_health)


func die() -> void:
	if is_dead:
		return
	is_dead = true
	died.emit()


func respawn() -> void:
	health = max_health
	is_dead = false
	velocity = Vector3.ZERO
	global_position = spawn_point
	camera.rotation = Vector3.ZERO
	health_changed.emit(health, max_health)
	respawned.emit()


func set_spawn_point(pos: Vector3) -> void:
	spawn_point = pos


func _on_damaged(amount: float, source: Node) -> void:
	take_damage(amount, source)
