extends Node
## G16 node_4 level + difficulty-ramp test (headless, no vision).
## Run:  godot --headless --audio-driver Dummy --path . res://tests/LevelProgressionTest.tscn
## Exit 0 on pass.
##
## Part A (pure, no scene): DifficultyCurve monotonicity, LevelGenerator
## determinism, per-record difficulty monotonicity, the clear-lane guarantee,
## and that generated structure size / block count grow with progress.
## Part B (full run): loads the real main scene, drives the player forward the
## whole level with input injection, and asserts the run is winnable -- the
## player reaches the end without dying, structures stream ahead and despawn
## behind, and the forward lane stays clear.

const MAIN_SCENE := "res://main.tscn"
const DIFF := preload("res://scripts/level/difficulty_curve.gd")
const LEVELGEN := preload("res://scripts/level/level_generator.gd")
const LEVELMANAGER := preload("res://scripts/level/level_manager.gd")
const STRUCTGEN := preload("res://scripts/destruction/structure_generator.gd")
const DESTRUCTIBLE := preload("res://scripts/destruction/destructible_structure.gd")

const RUN_SEED := 20260915
const RUN_LENGTH := 200.0
const MAX_RUN_FRAMES := 6000

var _checks := 0
var _failures: Array[String] = []


func _ready() -> void:
	_run()


func _check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  PASS  ", label)
	else:
		_failures.append(label)
		print("  FAIL  ", label)


func _run() -> void:
	print("=== G16 node_4 level + difficulty-ramp test ===")
	_part_a_pure()
	await _part_b_full_run()
	_finish()


# ---------------------------------------------------------------------------
# Part A -- pure, deterministic assertions on the ramp + generator.
# ---------------------------------------------------------------------------

func _part_a_pure() -> void:
	print("--- part A: pure difficulty curve + generator ---")

	# 1. Every DifficultyCurve scalar is monotonic in progress.
	var growing: Array = [
		["footprint_scale", DIFF.footprint_scale],
		["height_scale", DIFF.height_scale],
		["debris_speed_scale", DIFF.debris_speed_scale],
		["debris_quantity_scale", DIFF.debris_quantity_scale],
	]
	for entry in growing:
		var name: String = entry[0]
		var fn: Callable = entry[1]
		_check(_monotonic_non_decreasing(fn, 0.0, 1.0, 41),
			name + " is monotonic non-decreasing in progress")
	_check(_monotonic_non_increasing(DIFF.structure_spacing, 0.0, 1.0, 41),
		"structure_spacing is monotonic non-increasing (density grows)")
	_check(DIFF.danger(1.0) > DIFF.danger(0.0), "combined danger grows with progress")

	# 2. The generator is seedable / deterministic.
	var a := LEVELGEN.new(RUN_SEED, RUN_LENGTH)
	var b := LEVELGEN.new(RUN_SEED, RUN_LENGTH)
	var ra: Array = a.generate()
	var rb: Array = b.generate()
	_check(_records_equal(ra, rb), "same seed -> identical record stream (%d records)" % ra.size())
	_check(ra.size() >= 8, "level has a meaningful number of structures (%d)" % ra.size())
	var c := LEVELGEN.new(RUN_SEED + 1, RUN_LENGTH)
	_check(not _records_equal(ra, c.generate()), "different seed -> different record stream")

	# 3. Difficulty parameters are monotonic along the record stream.
	_check(_records_monotonic(ra), "per-record difficulty params increase monotonically along the level")

	# 4. Clear forward lane: no structure intrudes into the guaranteed corridor.
	_check(_records_clear_lane(ra), "every structure leaves the forward lane clear (no unwinnable block)")

	# 5. Generated structures actually grow: mean block count + height rise.
	var early_count: Array = []
	var late_count: Array = []
	var early_height: Array = []
	var late_height: Array = []
	var quarter := maxi(1, int(ra.size() / 4))
	for i in range(ra.size()):
		var stats := _structure_stats(ra[i])
		if i < quarter:
			early_count.append(stats.count)
			early_height.append(stats.max_y)
		elif i >= ra.size() - quarter:
			late_count.append(stats.count)
			late_height.append(stats.max_y)
	var ec := _mean(early_count)
	var lc := _mean(late_count)
	var eh := _mean(early_height)
	var lh := _mean(late_height)
	_check(lc > ec, "generated block count grows with progress (mean %.1f -> %.1f)" % [ec, lc])
	_check(lh > eh, "generated structure height grows with progress (mean %.2f -> %.2f m)" % [eh, lh])

	# 6. The debris-speed knob flows through build_structure -> shatter: with the
	# same seed, a higher debris_speed_scale must yield faster debris at launch.
	var low_speed := _max_launch_speed(5555, 1.0)
	var high_speed := _max_launch_speed(5555, 2.0)
	_check(high_speed > low_speed,
		"higher debris_speed_scale -> faster debris at launch (%.1f -> %.1f m/s)" % [low_speed, high_speed])


# ---------------------------------------------------------------------------
# Part B -- seeded full run: winnable from start to finish, no unwinnable state.
# ---------------------------------------------------------------------------

func _part_b_full_run() -> void:
	print("--- part B: seeded full run (winnable from start to finish) ---")
	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		_check(false, "main scene loads")
		return
	var main = packed.instantiate()
	add_child(main)
	await _settle(4)

	var player = main.get_node_or_null("Player")
	var level = main.get_node_or_null("LevelManager")
	_check(player != null, "player exists in the game scene")
	_check(level != null, "level manager exists in the game scene")
	if player == null or level == null:
		return

	_check(level.records.size() >= 8, "level generator produced records (%d)" % level.records.size())
	_check(level.structures.size() >= 2, "structures streamed ahead at spawn (%d)" % level.structures.size())

	var length: float = float(level.length)
	var min_z: float = player.position.z
	var max_abs_x: float = absf(player.position.x)
	var reached_end := false
	var saw_ahead := false

	Input.action_press("move_forward")
	for i in range(MAX_RUN_FRAMES):
		await get_tree().physics_frame
		var pz: float = player.position.z
		min_z = minf(min_z, pz)
		max_abs_x = maxf(max_abs_x, absf(player.position.x))

		if not saw_ahead and pz < -length * 0.5:
			for s in level.structures:
				if s.position.z < pz - 1.0:
					saw_ahead = true
					break

		if pz <= -length:
			reached_end = true
			break
		if player.is_dead:
			break
	Input.action_release("move_forward")

	_check(reached_end, "player reached the end of the level (z=%.1f <= -%.0f)" % [player.position.z, length])
	_check(not player.is_dead and player.health > 0.0,
		"player survived the full run (health %.0f)" % player.health)
	_check(min_z <= -length, "forward progress carried the player to the end (min_z=%.1f)" % min_z)
	_check(max_abs_x < LEVELGEN.CLEAR_LANE_HALF + 0.5,
		"player stayed inside the clear lane (max|x|=%.2f m)" % max_abs_x)
	_check(saw_ahead, "structures streamed ahead of the advancing player")

	# Structures the player passed more than DESPAWN_BEHIND metres ago must have
	# been freed (despawn behind), and the live set must stay bounded.
	var stale := 0
	var live_count := 0
	for s in level.structures:
		live_count += 1
		if s.position.z > player.position.z + LEVELMANAGER.DESPAWN_BEHIND:
			stale += 1
	_check(stale == 0, "no stale structures left behind the player (despawn works)")
	_check(live_count < level.records.size(),
		"structures despawned over the run (%d live of %d total)" % [live_count, level.records.size()])


# ---------------------------------------------------------------------------
# Helpers.
# ---------------------------------------------------------------------------

func _settle(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _monotonic_non_decreasing(fn: Callable, lo: float, hi: float, steps: int) -> bool:
	var prev := -INF
	for i in range(steps + 1):
		var t := lerpf(lo, hi, float(i) / float(steps))
		var v: float = fn.call(t)
		if v < prev - 0.0001:
			return false
		prev = v
	return true


func _monotonic_non_increasing(fn: Callable, lo: float, hi: float, steps: int) -> bool:
	var prev := INF
	for i in range(steps + 1):
		var t := lerpf(lo, hi, float(i) / float(steps))
		var v: float = fn.call(t)
		if v > prev + 0.0001:
			return false
		prev = v
	return true


func _records_equal(a: Array, b: Array) -> bool:
	if a.size() != b.size():
		return false
	for i in range(a.size()):
		if not _record_equal(a[i], b[i]):
			return false
	return true


func _record_equal(x: Dictionary, y: Dictionary) -> bool:
	return x.z == y.z and x.x == y.x and x.seed == y.seed and x.t == y.t


func _records_monotonic(records: Array) -> bool:
	var prev_t := -1.0
	var prev_fp := -1.0
	var prev_h := -1.0
	var prev_spd := -1.0
	var prev_qty := -1.0
	for r in records:
		var t: float = r.t
		var p: Dictionary = r.params
		if t < prev_t - 0.0001:
			return false
		if float(p.footprint_scale) < prev_fp - 0.0001:
			return false
		if float(p.height_scale) < prev_h - 0.0001:
			return false
		if float(p.debris_speed_scale) < prev_spd - 0.0001:
			return false
		if float(p.block_count_scale) < prev_qty - 0.0001:
			return false
		prev_t = t
		prev_fp = p.footprint_scale
		prev_h = p.height_scale
		prev_spd = p.debris_speed_scale
		prev_qty = p.block_count_scale
	return true


func _records_clear_lane(records: Array) -> bool:
	for r in records:
		var inner := absf(float(r.x)) - float(r.half_x)
		if inner < LEVELGEN.CLEAR_LANE_HALF - 0.001:
			return false
	return true


func _structure_stats(record: Dictionary) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = record.seed
	var specs: Array = STRUCTGEN.generate(Vector3.ZERO, rng, record.params)
	var max_y := 0.0
	for s in specs:
		max_y = maxf(max_y, float(s.position.y) + float(s.size.y) * 0.5)
	return {"count": specs.size(), "max_y": max_y}


func _mean(values: Array) -> float:
	if values.is_empty():
		return 0.0
	var s := 0.0
	for v in values:
		s += float(v)
	return s / values.size()


func _max_launch_speed(p_seed: int, speed_scale: float) -> float:
	var d = DESTRUCTIBLE.new()
	add_child(d)
	d.build_structure(Vector3.ZERO, p_seed, {"debris_speed_scale": speed_scale})
	var debris: Array = d.shatter(Vector3.INF, 1.0)
	var mx := 0.0
	for b in debris:
		mx = maxf(mx, b.linear_velocity.length())
	d.queue_free()
	return mx


func _finish() -> void:
	print("=== results: %d checks, %d failures ===" % [_checks, _failures.size()])
	if _failures.size() == 0:
		print("LEVEL + DIFFICULTY-RAMP TEST PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("  FAILED: ", f)
		print("LEVEL + DIFFICULTY-RAMP TEST FAIL")
		get_tree().quit(1)
