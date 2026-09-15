class_name LevelGenerator
## G16 node 4 -- deterministic linear level layout.
##
## Generates a sequence of structure spawn records running forward along -Z,
## with density/size/height and debris danger scaling monotonically with
## progress via DifficultyCurve. Pure (no scene tree) and seedable: the same
## seed reproduces the exact same record stream, so tests and the seeded full
## run are reproducible.
##
## A record is a Dictionary:
##   z       : float      -- forward position (more negative = further ahead)
##   x       : float      -- lateral offset (left or right of the clear lane)
##   seed    : int        -- per-structure seed for StructureGenerator
##   t       : float      -- progress at this record (0..1)
##   params  : Dictionary -- DifficultyCurve.params_for(t)
##   half_x / half_z / height : float -- rolled footprint/height bounds
##
## Placement guarantees a winnable level: every structure is pushed sideways so
## its inner edge stays at least CLEAR_LANE_HALF metres from x=0, leaving a
## guaranteed open corridor the player can advance through (no unwinnable wall).

const Difficulty := preload("res://scripts/level/difficulty_curve.gd")
const StructureGen := preload("res://scripts/destruction/structure_generator.gd")

const CLEAR_LANE_HALF := 1.2   # metres of guaranteed-clear corridor around x=0
const LANE_GAP := 1.0          # extra gap between lane edge and a structure
const SIDE_JITTER := 2.0       # random outward push so the two sides don't line up
const SPACING_JITTER := 0.2    # +/- 20% spacing variation (kept deterministic)

var seed := 0
var length := 200.0
var start_dist := 8.0

var records: Array = []


func _init(p_seed: int = 0, p_length: float = 200.0) -> void:
	seed = p_seed
	length = p_length


func generate() -> Array:
	records = []
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var z := -start_dist
	var index := 0
	while z > -length:
		var t := clampf((-z) / length, 0.0, 1.0)
		var params: Dictionary = Difficulty.params_for(t)

		# Roll this structure's layout to learn its footprint (deterministic;
		# the same per-structure seed re-rolls identically at build time), then
		# place it so the clear forward lane stays unobstructed.
		var measure_rng := RandomNumberGenerator.new()
		measure_rng.seed = _struct_seed(index)
		var bounds: Dictionary = StructureGen.layout_bounds(measure_rng, params)

		var side := 1 if (index % 2 == 0) else -1
		var x := side * (CLEAR_LANE_HALF + float(bounds.half_x) + LANE_GAP + rng.randf_range(0.0, SIDE_JITTER))

		records.append({
			"z": z,
			"x": x,
			"seed": _struct_seed(index),
			"t": t,
			"params": params,
			"half_x": bounds.half_x,
			"half_z": bounds.half_z,
			"height": bounds.height,
		})

		var spacing := Difficulty.structure_spacing(t)
		z -= spacing * rng.randf_range(1.0 - SPACING_JITTER, 1.0 + SPACING_JITTER)
		index += 1
	return records


func _struct_seed(index: int) -> int:
	return int(seed) * 1000003 + index * 7919 + 1
