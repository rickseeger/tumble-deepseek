extends RefCounted
## StructureGenerator -- procedurally produces a list of destructible block
## specs describing a tower/building of varying footprint, height, shape mix
## and per-block size. Deterministic for a given seed.
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


static func generate(origin: Vector3, rng: RandomNumberGenerator) -> Array:
	var specs: Array = []
	var rx := rng.randi_range(2, 3)
	var rz := rng.randi_range(2, 3)
	var floors := rng.randi_range(3, 5)
	var style := rng.randi_range(0, 2)  # 0 solid, 1 hollow/columns, 2 tapered
	var cell := 1.0
	var palette := _palette()

	for f in range(floors):
		var fx := rx
		var fz := rz
		if style == 2:
			# Taper the footprint on upper floors for a spire silhouette.
			fx = maxi(1, rx - f)
			fz = maxi(1, rz - f)

		var y := (float(f) + 0.5) * cell

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

				var sx := cell * rng.randf_range(0.70, 0.95)
				var sy := cell * rng.randf_range(0.70, 0.95)
				var sz := cell * rng.randf_range(0.70, 0.95)
				var size := Vector3(sx, sy, sz)
				if shape == SPHERE:
					var d := cell * rng.randf_range(0.55, 0.80)
					size = Vector3(d, d, d)

				var rotation := Vector3.ZERO
				if shape == BOX and rng.randf() < 0.30:
					rotation = Vector3(0.0, rng.randf_range(-0.35, 0.35), 0.0)

				var color: Color = palette[rng.randi_range(0, palette.size() - 1)]

				specs.append({
					"position": origin + Vector3(float(xi) * cell, y, float(zi) * cell),
					"size": size,
					"shape": shape,
					"rotation": rotation,
					"color": color,
				})

	return specs


static func _palette() -> Array:
	return [
		Color(0.72, 0.33, 0.26),  # brick red
		Color(0.62, 0.28, 0.22),  # darker brick
		Color(0.55, 0.55, 0.55),  # grey stone
		Color(0.45, 0.45, 0.48),  # darker stone
		Color(0.78, 0.65, 0.42),  # sandstone
		Color(0.38, 0.42, 0.50),  # slate blue
	]
