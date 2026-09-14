extends Node
## Smoke test: loads the real game scene, verifies a ground-level
## first-person camera, drives it forward, and confirms a 3D scene renders
## by sampling viewport pixels in code (not human vision).
## Run with a real GL context:  ./smoke_test.sh
## Exit code 0 on pass.

const MAIN_SCENE := "res://main.tscn"
const HEAD_HEIGHT := 1.7

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
	print("=== G16 node_1 smoke test ===")
	print("renderer=", RenderingServer.get_current_rendering_method(), " driver=", RenderingServer.get_current_rendering_driver_name())

	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		print("FATAL: could not load ", MAIN_SCENE)
		get_tree().quit(1)
		return
	var main := packed.instantiate()
	await get_tree().process_frame
	get_tree().root.add_child(main)

	for i in range(6):
		await get_tree().process_frame

	var player = main.get_node_or_null("Player")
	_check(player != null and player is CharacterBody3D, "player exists and is a CharacterBody3D")
	if player == null:
		_finish()
		return

	var camera := player.get_node_or_null("Camera3D") as Camera3D
	_check(camera != null, "player has a Camera3D child")
	if camera != null:
		_check(camera.current, "camera is the active camera")
		_check(absf(camera.global_position.y - HEAD_HEIGHT) < 0.05,
			"camera at head height (%.2f m)" % camera.global_position.y)

	var start: Vector3 = player.global_position
	Input.action_press("move_forward")
	for i in range(30):
		await get_tree().physics_frame
	Input.action_release("move_forward")
	var moved: Vector3 = player.global_position - start
	var pt: Transform3D = player.global_transform
	var fwd: Vector3 = -pt.basis.z
	var forward_progress := moved.dot(fwd)
	_check(forward_progress > 0.5, "player moves forward (progress %.2f m)" % forward_progress)
	_check(absf(moved.y) < 0.35, "player stays on floor (dy %.3f m)" % moved.y)

	await get_tree().process_frame
	await get_tree().process_frame
	_check_rendering()

	_finish()


func _check_rendering() -> void:
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		_check(false, "viewport image available for sampling")
		return
	_check(true, "viewport image available for sampling")

	var w := img.get_width()
	var h := img.get_height()
	_check(w >= 320 and h >= 200, "viewport is a real size (%dx%d)" % [w, h])

	var cx := w / 2
	var cy := h / 2
	var center := img.get_pixel(cx, cy)
	var top := img.get_pixel(cx, h / 4)
	var bottom := img.get_pixel(cx, int(h * 0.85))
	var left := img.get_pixel(w / 4, cy)
	var right := img.get_pixel(int(w * 0.75), cy)

	var top_is_sky := top.b > top.r and top.b > 0.4
	var bottom_is_ground := bottom.g > bottom.b and bottom.g > 0.15
	_check(top_is_sky, "top of frame is sky (top=%s)" % top)
	_check(bottom_is_ground, "bottom of frame is ground (bottom=%s)" % bottom)

	var samples: Array[Color] = [center, top, bottom, left, right]
	var distinct := 0
	for i in range(samples.size()):
		for j in range(i + 1, samples.size()):
			var d := samples[i] - samples[j]
			var mag := absf(d.r) + absf(d.g) + absf(d.b)
			if mag > 0.05:
				distinct += 1
	_check(distinct >= 2, "frame has colour variation (distinct=%d)" % distinct)


func _finish() -> void:
	print("=== results: %d checks, %d failures ===" % [_checks, _failures.size()])
	if _failures.size() == 0:
		print("SMOKE TEST PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("  FAILED: ", f)
		print("SMOKE TEST FAIL")
		get_tree().quit(1)

