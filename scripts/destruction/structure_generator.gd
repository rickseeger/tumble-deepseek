extends RefCounted
## StructureGenerator -- procedurally produces a list of destructible block
## specs describing a tower/building of varying footprint, height, shape mix
## and per-block size. Deterministic for a given seed.
##
## Node 4 extends generate() with an optional `params` Dictionary carrying the
## difficulty scalars from DifficultyCurve.params_for(t):
##   footprint_scale   -- physical horizontal size (cell spacing + block size)
##   height_scale      -- physical vertical size (floor height + floor count)
##   block_count_scale -- how many cells wide/deep the footprint is (more blocks)
## Missing keys default to 1.0, which reproduces the node-2 base behaviour
## exactly (same RNG draw order).
##
## A spec is a Dictionary:
##   position : Vector3 -- centre of the block (relative to the structure origin
##                         passed to generate()).
##   size     : Vector3 -- bounding size. For "box" it is the box extent; for
##                         "cylinder"/"sphere" x is the diameter and y the height.
##   shape    : String  -- "box" | "cylinder" | "sphere"
##   rotation : Vector3 -- Euler rotation in radians (boxes only, small yaw jitter)
##   color    : Color   -- albedo for the debris material
##
## Static functions only; no scene tree required.

class_name StructureGenerator

const BOX := "box"
const CYLINDER := "cylinder"
const SPHERE := "sphere"


## Generate the block layout. `params` (optional) carries difficulty scalars.
static func generate(origin: Vector3, rng: RandomNumberGenerator, params: Dictionary = {}) -> Array:
	var layout := _roll_layout(rng, params)
	var rx: int = layout.rx
	var rz: int = layout.rz
	var floors: int = layout.floors
	var style: int = layout.style
	var hspace: float = layout.hspace
	var vspace: float = layout.vspace

	var specs: Array = []
	var palette := _palette()

	for f in range(floors):
		var fx := rx
		var fz := rz
		if style == 2:
			# Taper the footprint on upper floors for a spire silhouette.
			fx = maxi(1, rx - f)
			fz = maxi(1, rz - f)

		var y := (float(f) + 0.5) * vspace

		for xi in range(-fx, fx + 1):
			for zi in range(-fz, fz + 1):
				var is_edge := absi(xi) == fx or absi(zi) == fz
				var is_corner := absi(xi) == fx and absi(zi) == fz

				# Shape-variety skips: hollow interiors for column style, and a
				# little random removal so no two structures look identical.
				if style == 1 and not is_edge:
					continue
				if is_corner and rng.randf() < 0.30:
					continue
				if not is_edge and rng.randf() < 0.12:
					continue

				var shape := BOX
				var r := rng.randf()
				if is_corner and (style == 1 or (f == floors - 1 and rng.randf() < 0.5)):
					shape = CYLINDER  # corner pillars / rooftop finials
				elif r < 0.05:
					shape = SPHERE
				elif r < 0.15:
					shape = CYLINDER

				var sx := hspace * rng.randf_range(0.70, 0.95)
				var sy := vspace * rng.randf_range(0.70, 0.95)
				var sz := hspace * rng.randf_range(0.70, 0.95)
				var size := Vector3(sx, sy, sz)
				if shape == SPHERE:
					var d := hspace * rng.randf_range(0.55, 0.80)
					size = Vector3(d, d, d)

				var rotation := Vector3.ZERO
				if shape == BOX and rng.randf() < 0.30:
					rotation = Vector3(0.0, rng.randf_range(-0.35, 0.35), 0.0)

				var color: Color = palette[rng.randi_range(0, palette.size() - 1)]

				specs.append({
					"position": origin + Vector3(float(xi) * hspace, y, float(zi) * hspace),
					"size": size,
					"shape": shape,
					"rotation": rotation,
					"color": color,
				})

	return specs


## Deterministic bounds for a structure rolled with the same rng + params that
## generate() would use. Consumes exactly the same layout draws as generate(),
## so a caller can measure a structure's footprint (to place it) and later re-
## roll the identical layout from the same seed at build time.
static func layout_bounds(rng: RandomNumberGenerator, params: Dictionary = {}) -> Dictionary:
	var layout := _roll_layout(rng, params)
	var half_x: float = (float(layout.rx) + 0.5) * float(layout.hspace)
	var half_z: float = (float(layout.rz) + 0.5) * float(layout.hspace)
	var height: float = float(layout.floors) * float(layout.vspace)
	return {
		"half_x": half_x,
		"half_z": half_z,
		"height": height,
		"floors": layout.floors,
		"rx": layout.rx,
		"rz": layout.rz,
	}


## Rolls the top-level layout choices (footprint cells, floor count, style,
## cell spacing) exactly once, in the same order generate() consumes them.
static func _roll_layout(rng: RandomNumberGenerator, params: Dictionary) -> Dictionary:
	var footprint_scale: float = params.get("footprint_scale", 1.0)
	var height_scale: float = params.get("height_scale", 1.0)
	var block_count_scale: float = params.get("block_count_scale", 1.0)

	# block_count_scale widens the footprint in cell-count (more blocks per
	# floor). round() maps the monotonic [1,2] range to a non-decreasing cell
	# count: rx,rz in [2,3] at the start -> [2,4] from the mid-level onward.
	var rx_hi := 2 + int(round(block_count_scale))
	var rz_hi := 2 + int(round(block_count_scale))
	var rx := rng.randi_range(2, rx_hi)
	var rz := rng.randi_range(2, rz_hi)

	# height_scale drives both the floor height (vspace) and the floor count,
	# so taller structures also have more blocks to shatter.
	var floors := maxi(2, int(round(rng.randi_range(3, 5) * height_scale)))
	var style := rng.randi_range(0, 2)  # 0 solid, 1 hollow/columns, 2 tapered
	var hspace := 1.0 * footprint_scale
	var vspace := 1.0 * height_scale
	return {
		"rx": rx, "rz": rz, "floors": floors, "style": style,
		"hspace": hspace, "vspace": vspace,
	}


static func _palette() -> Array:
	return [
		Color(0.72, 0.33, 0.26),  # brick red
		Color(0.62, 0.28, 0.22),  # darker brick
		Color(0.55, 0.55, 0.55),  # grey stone
		Color(0.45, 0.45, 0.48),  # darker stone
		Color(0.78, 0.65, 0.42),  # sandstone
		Color(0.38, 0.42, 0.50),  # slate blue
	]
