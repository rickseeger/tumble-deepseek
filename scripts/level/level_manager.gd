class_name LevelManager
extends Node3D
## G16 node 4 -- streams the generated linear level around the advancing player.
##
## Spawns structures as they come into range ahead of the player and despawns
## them once they fall behind, so the level feels continuous but keeps live
## physics bounded. main.gd's forward loop calls update(player_z) each frame
## with the player's world z (forward = -Z).

const Destructible := preload("res://scripts/destruction/destructible_structure.gd")
const LevelGen := preload("res://scripts/level/level_generator.gd")

const SPAWN_AHEAD := 60.0     # spawn structures up to this far ahead (metres)
const DESPAWN_BEHIND := 25.0  # free structures more than this far behind

var seed := 0
var length := 200.0

var generator = null
var records: Array = []
var structures: Array = []    # live DestructibleStructure nodes, in spawn order


func configure(p_seed: int, p_length: float) -> void:
	seed = p_seed
	length = p_length
	generator = LevelGen.new(seed, length)
	records = generator.generate()


func reset(p_seed: int, p_length: float) -> void:
	for s in structures:
		s.queue_free()
	structures.clear()
	configure(p_seed, p_length)


## Stream the level for a player at world z `player_z` (forward = -Z).
func update(player_z: float) -> void:
	# Spawn records whose z is ahead of (or level with) the player and within
	# the spawn window, if they are not already live.
	for r in records:
		var rz: float = r.z
		if rz <= player_z and rz >= player_z - SPAWN_AHEAD and not _is_live(r):
			_spawn(r)

	# Despawn structures that have fallen more than DESPAWN_BEHIND behind.
	var stale: Array = []
	for s in structures:
		if s.position.z > player_z + DESPAWN_BEHIND:
			stale.append(s)
	for s in stale:
		structures.erase(s)
		s.queue_free()


func _is_live(r: Dictionary) -> bool:
	var key: int = r.seed
	for s in structures:
		if s.structure_seed == key:
			return true
	return false


func _spawn(r: Dictionary) -> void:
	var d = Destructible.new()
	d.name = "Structure_%04d" % structures.size()
	d.position = Vector3(float(r.x), 0.0, float(r.z))
	add_child(d)
	d.build_structure(Vector3.ZERO, int(r.seed), r.params)
	structures.append(d)
