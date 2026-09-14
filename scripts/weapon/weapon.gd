extends Node3D
## Weapon -- a deterministic hitscan "pew-pew" blaster (G16 node 3).
##
## Lives as a child of the player's Camera3D, so it inherits the camera
## transform and always fires from the view centre. A shot is a single
## physics ray from the camera along its forward (-Z) axis:
##   * hitting an intact DestructibleStructure triggers its existing
##     shatter() destruction path at the hit point;
##   * hitting a loose debris RigidBody3D blasts it away (the "blast through"
##     half of the core tension).
##
## Firing is deterministic and scriptable: `fire()` is a pure function of the
## scene state, and the same code path is reached by holding the "fire" input
## action (so `Input.action_press("fire")` in a test drives a real shot/hit).
##
## Audio is deliberately NOT implemented here -- node 5 owns sound. This node
## provides crisp visual/mechanical feedback (muzzle flash + recoil kick) and
## emits `fired` / `shot_landed` so node 5 can hang audio on them.

signal fired(hit: Dictionary)                       # every shot, even a miss
signal shot_landed(target: Node, hit_point: Vector3, hit_normal: Vector3)
signal ammo_changed(ammo: int)
signal reload_started
signal reload_finished

const RANGE := 200.0
const FIRE_COOLDOWN := 0.18        # seconds between shots (auto-fire rate)
const MAGAZINE_SIZE := 30
const SHATTER_POWER := 1.0         # passed through to DestructibleStructure.shatter
const DEBRIS_IMPULSE := 9.0         # blast applied to a loose debris block on hit
const RELOAD_TIME := 1.2            # seconds
const MUZZLE_FLASH_TIME := 0.06     # seconds the flash mesh stays visible
const RECOIL_KICK := 0.022          # radians of one-shot camera pitch-up
const COLLISION_MASK := 0x1         # layer 1: ground, structures, debris

var ammo := MAGAZINE_SIZE

var _cooldown_left := 0.0
var _reloading := false
var _reload_left := 0.0
var _recoil_velocity := 0.0
var _player: CharacterBody3D = null
var _camera: Camera3D = null
var _flash: MeshInstance3D = null
var _flash_left := 0.0


func configure(player: CharacterBody3D) -> void:
	_player = player
	_camera = get_parent() as Camera3D
	_build_muzzle_flash()


func _ready() -> void:
	if _camera == null:
		_camera = get_parent() as Camera3D
	if _flash == null:
		_build_muzzle_flash()


func _process(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)

	if _reloading:
		_reload_left -= delta
		if _reload_left <= 0.0:
			_reloading = false
			ammo = MAGAZINE_SIZE
			ammo_changed.emit(ammo)
			reload_finished.emit()

	if _flash_left > 0.0:
		_flash_left -= delta
		if _flash_left <= 0.0 and _flash != null:
			_flash.visible = false

	# Decay the recoil pitch kick back to zero.
	if _recoil_velocity > 0.0 and _camera != null:
		_camera.rotation.x = clampf(
			_camera.rotation.x + _recoil_velocity * delta,
			deg_to_rad(-89.0), deg_to_rad(89.0))
		_recoil_velocity = maxf(_recoil_velocity - 0.4 * delta, 0.0)


func can_fire() -> bool:
	return not _reloading and ammo > 0 and _cooldown_left <= 0.0


## Fire one shot. Returns the physics ray hit Dictionary (empty on miss or
## when unable to fire). Deterministic: same scene -> same result.
func fire() -> Dictionary:
	if not can_fire():
		if ammo <= 0 and not _reloading:
			_start_reload()
		return {}

	_cooldown_left = FIRE_COOLDOWN
	ammo -= 1
	ammo_changed.emit(ammo)

	_show_muzzle_flash()
	_apply_recoil()

	var hit := _raycast()
	fired.emit(hit)

	if not hit.is_empty():
		_apply_hit(hit)
		var collider = hit.get("collider")
		if collider != null:
			shot_landed.emit(collider, hit["position"], hit["normal"])

	if ammo <= 0:
		_start_reload()
	return hit


func _raycast() -> Dictionary:
	if _camera == null or not _camera.is_inside_tree():
		return {}

	var from := _camera.global_position
	var dir := -_camera.global_transform.basis.z
	var to := from + dir * RANGE

	var exclude: Array[RID] = []
	if _player != null and _player.is_inside_tree():
		exclude.append(_player.get_rid())

	var params := PhysicsRayQueryParameters3D.create(from, to, COLLISION_MASK, exclude)
	params.collide_with_bodies = true
	params.collide_with_areas = false
	return _camera.get_world_3d().direct_space_state.intersect_ray(params)


func _apply_hit(hit: Dictionary) -> void:
	var collider = hit.get("collider")
	if collider == null:
		return
	var hit_point: Vector3 = hit["position"]

	var structure := _resolve_structure(collider)
	if structure != null and not structure.is_shattered:
		# Hit a structure: run its existing destruction path.
		structure.shatter(hit_point, SHATTER_POWER)
	elif collider is RigidBody3D:
		# Hit loose debris: blast it out of the way.
		var dir := -_camera.global_transform.basis.z
		collider.apply_central_impulse(dir * DEBRIS_IMPULSE)


## Walk up from the hit collider to the owning DestructibleStructure (the node
## exposing shatter() + is_shattered), if any. Duck-typed so the weapon stays
## decoupled from the destruction module.
func _resolve_structure(node: Node) -> Node:
	var n := node
	while n != null:
		if n.has_method("shatter") and "is_shattered" in n:
			return n
		n = n.get_parent()
	return null


func _start_reload() -> void:
	if _reloading:
		return
	_reloading = true
	_reload_left = RELOAD_TIME
	reload_started.emit()


func _show_muzzle_flash() -> void:
	if _flash == null:
		return
	_flash.visible = true
	_flash_left = MUZZLE_FLASH_TIME


func _apply_recoil() -> void:
	_recoil_velocity = RECOIL_KICK


func _build_muzzle_flash() -> void:
	if _flash != null:
		return
	_flash = MeshInstance3D.new()
	_flash.name = "MuzzleFlash"
	var mesh := SphereMesh.new()
	mesh.radius = 0.06
	mesh.height = 0.12
	_flash.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.95, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.3)
	mat.emission_energy_multiplier = 4.0
	_flash.material_override = mat
	_flash.position = Vector3(0.0, -0.15, -0.5)
	_flash.visible = false
	add_child(_flash)
