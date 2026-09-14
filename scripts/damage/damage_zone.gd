extends Area3D
## DamageZone (G16 node 3) -- the player's hazard hitbox. Detects debris
## RigidBody3D blocks entering the player's body and converts each impact into
## damage scaled by the block's mass and speed ("don't get crushed").
##
##   damage = clamp(mass * speed * DAMAGE_PER_MS, MIN_DAMAGE, MAX_DAMAGE)
##
## Slow blocks (below MIN_IMPACT_SPEED, e.g. one settling onto you) deal no
## damage, so only genuine moving debris hurts. A per-body cooldown stops a
## single tumbling block from re-damaging on every re-entry.

signal damaged(amount: float, source: Node)

const MIN_IMPACT_SPEED := 2.0     # m/s below which contact is harmless
const MIN_DAMAGE := 2.0
const MAX_DAMAGE := 45.0
const DAMAGE_PER_MS := 0.4        # damage = mass * speed * this
const BODY_COOLDOWN := 0.6        # seconds before the same block can hurt again
const HITBOX_RADIUS := 0.55       # slightly larger than the player capsule (0.4)
const HITBOX_HEIGHT := 1.7        # matches the player capsule height

var enabled := true
var _last_hit: Dictionary = {}    # body instance id -> msec of last hit


func _ready() -> void:
	monitoring = true
	collision_layer = 0            # the hitbox itself need not be detected
	collision_mask = 0x1           # detect physics bodies on layer 1 (debris)
	body_entered.connect(_on_body_entered)
	_build_hitbox_shape()


## Pure, deterministic damage model -- exposed so tests can assert the scaling
## directly without a full physics run.
static func impact_damage(mass: float, speed: float) -> float:
	if speed < MIN_IMPACT_SPEED:
		return 0.0
	return clampf(mass * speed * DAMAGE_PER_MS, MIN_DAMAGE, MAX_DAMAGE)


func _build_hitbox_shape() -> void:
	var shape := CapsuleShape3D.new()
	shape.radius = HITBOX_RADIUS
	shape.height = HITBOX_HEIGHT
	var col := CollisionShape3D.new()
	col.shape = shape
	add_child(col)


func _on_body_entered(body: Node) -> void:
	if not enabled or not (body is RigidBody3D):
		return
	var rb := body as RigidBody3D
	var speed: float = rb.linear_velocity.length()
	var dmg := impact_damage(rb.mass, speed)
	if dmg <= 0.0:
		return
	var id := body.get_instance_id()
	var now := Time.get_ticks_msec()
	if _last_hit.has(id) and (now - int(_last_hit[id])) < int(BODY_COOLDOWN * 1000.0):
		return
	_last_hit[id] = now
	damaged.emit(dmg, body)
