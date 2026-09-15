class_name DifficultyCurve
## G16 node 4 -- the difficulty ramp, expressed as pure, monotonic functions of
## progress t in [0, 1] (0 = start of the level, 1 = the far end).
##
## Every function is static + pure (no scene tree, no RNG) so the automated
## test can assert monotonicity directly by sampling t, without running the game.
##
##   structure_spacing(t)     -- metres between consecutive structures; SHRINKS
##                               as t rises, so density (structures per metre)
##                               grows.
##   footprint_scale(t)       -- horizontal size multiplier (bigger structures).
##   height_scale(t)          -- vertical size multiplier (taller structures).
##   debris_speed_scale(t)    -- shatter launch-speed multiplier (faster debris).
##   debris_quantity_scale(t) -- block-count multiplier (more debris per break).
##
## params_for(t) bundles the four structure/debris scalars into the Dictionary
## that StructureGenerator.generate() consumes. All four are monotonic in t.

static func _c(t: float) -> float:
	return clampf(t, 0.0, 1.0)

static func structure_spacing(t: float) -> float:
	return lerpf(16.0, 4.0, _c(t))

static func footprint_scale(t: float) -> float:
	return lerpf(1.0, 1.35, _c(t))

static func height_scale(t: float) -> float:
	return lerpf(1.0, 1.6, _c(t))

static func debris_speed_scale(t: float) -> float:
	return lerpf(1.0, 2.0, _c(t))

static func debris_quantity_scale(t: float) -> float:
	return lerpf(1.0, 2.0, _c(t))

## A single scalar "danger" for tools/tests to eyeball the whole ramp at once.
static func danger(t: float) -> float:
	t = _c(t)
	return footprint_scale(t) * height_scale(t) * debris_speed_scale(t) * debris_quantity_scale(t)

static func params_for(t: float) -> Dictionary:
	t = _c(t)
	return {
		"footprint_scale": footprint_scale(t),
		"height_scale": height_scale(t),
		"block_count_scale": debris_quantity_scale(t),
		"debris_speed_scale": debris_speed_scale(t),
	}
