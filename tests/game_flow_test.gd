extends Node
## G16 node_3 game-flow integration test (headless, no vision).
## Run:  godot --headless --audio-driver Dummy --path . res://tests/GameFlowTest.tscn
## Exit 0 on pass.
##
## Loads the real game scene and asserts, code-level (no vision):
##   * the HUD is wired (health bar full, ammo 30, game-over hidden);
##   * the player carries the weapon and damage zone;
##   * lethal damage -> death -> game-over overlay -> auto-respawn restores
##     full health and rebuilds the destructible structures.

const MAIN_SCENE := "res://main.tscn"
const RESPAWN_TIMEOUT_FRAMES := 240   # generous window for the 2s auto-respawn

var _checks := 0
var _failures: Array[String] = []
var _main = null


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
	print("=== G16 node_3 game-flow test ===")

	var packed: PackedScene = load(MAIN_SCENE)
	if packed == null:
		print("FATAL: could not load ", MAIN_SCENE)
		get_tree().quit(1)
		return
	_main = packed.instantiate()
	add_child(_main)
	await _settle(4)

	var player = _main.get_node_or_null("Player")
	_check(player != null, "player exists in the game scene")
	if player == null:
		_finish()
		return
	_check(player.weapon != null, "player carries a weapon")
	_check(player.damage_zone != null, "player carries a damage zone")

	var hud = _main.get_node_or_null("HUD")
	_check(hud != null, "HUD exists in the game scene")
	if hud != null:
		_check(hud.health_bar != null and hud.health_bar.value == 100.0,
			"HUD health bar starts full (%.0f)" % hud.health_bar.value)
		_check(hud.ammo_label != null and hud.ammo_label.text == "AMMO 30",
			"HUD ammo starts at 30 (%s)" % hud.ammo_label.text)
		_check(not hud.game_over_label.visible, "game-over overlay hidden at start")

	# Lethal damage -> death -> game-over.
	player.take_damage(1000.0)
	await _settle(2)
	_check(player.is_dead, "player dies on lethal damage")
	if hud != null:
		_check(hud.game_over_label.visible, "game-over overlay shown on death")

	# Auto-respawn after the delay.
	var respawned := false
	for i in range(RESPAWN_TIMEOUT_FRAMES):
		await get_tree().physics_frame
		if not player.is_dead:
			respawned = true
			break
	_check(respawned, "player auto-respawned after death")
	_check(player.health == player.max_health, "health restored to full after respawn (%.0f)" % player.health)
	if hud != null:
		_check(not hud.game_over_label.visible, "game-over overlay hidden after respawn")

	_check(_main._destructibles.size() >= 2, "structures rebuilt after respawn (%d)" % _main._destructibles.size())

	_finish()


func _settle(n: int) -> void:
	for i in range(n):
		await get_tree().physics_frame


func _finish() -> void:
	print("=== results: %d checks, %d failures ===" % [_checks, _failures.size()])
	if _failures.size() == 0:
		print("GAME-FLOW TEST PASS")
		get_tree().quit(0)
	else:
		for f in _failures:
			print("  FAILED: ", f)
		print("GAME-FLOW TEST FAIL")
		get_tree().quit(1)
