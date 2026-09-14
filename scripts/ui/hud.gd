extends CanvasLayer
## HUD (G16 node 3) -- health bar, ammo readout, and a game-over overlay.
## Built entirely in code (like the rest of the scene) so it is diffable and
## testable: tests assert on `health_bar.value`, `ammo_label.text`, and the
## game-over label's visibility instead of eyeballing pixels.

var health_bar: ProgressBar = null
var health_label: Label = null
var ammo_label: Label = null
var game_over_label: Label = null
var game_over_subtitle: Label = null


func _ready() -> void:
	layer = 10
	_build()


func _build() -> void:
	health_bar = ProgressBar.new()
	health_bar.name = "HealthBar"
	health_bar.min_value = 0.0
	health_bar.max_value = 100.0
	health_bar.value = 100.0
	health_bar.custom_minimum_size = Vector2(220, 22)
	health_bar.position = Vector2(16, 16)
	health_bar.show_percentage = false
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.85, 0.16, 0.16)
	health_bar.add_theme_stylebox_override("fill", fill)
	add_child(health_bar)

	health_label = Label.new()
	health_label.name = "HealthLabel"
	health_label.text = "HP 100 / 100"
	health_label.position = Vector2(16, 42)
	add_child(health_label)

	ammo_label = Label.new()
	ammo_label.name = "AmmoLabel"
	ammo_label.text = "AMMO 30"
	ammo_label.position = Vector2(16, 66)
	add_child(ammo_label)

	game_over_label = Label.new()
	game_over_label.name = "GameOverLabel"
	game_over_label.text = "YOU DIED"
	game_over_label.add_theme_font_size_override("font_size", 52)
	game_over_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.2))
	game_over_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_label.visible = false
	add_child(game_over_label)

	game_over_subtitle = Label.new()
	game_over_subtitle.name = "GameOverSubtitle"
	game_over_subtitle.text = "respawning..."
	game_over_subtitle.add_theme_font_size_override("font_size", 20)
	game_over_subtitle.set_anchors_preset(Control.PRESET_FULL_RECT)
	game_over_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	game_over_subtitle.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	game_over_subtitle.position = Vector2(0, 70)
	game_over_subtitle.visible = false
	add_child(game_over_subtitle)


func set_health(value: float, max_value: float) -> void:
	if health_bar == null:
		return
	health_bar.max_value = max_value
	health_bar.value = value
	health_label.text = "HP %d / %d" % [int(value), int(max_value)]


func set_ammo(value: int) -> void:
	if ammo_label == null:
		return
	ammo_label.text = "AMMO %d" % value


func show_game_over() -> void:
	if game_over_label != null:
		game_over_label.visible = true
	if game_over_subtitle != null:
		game_over_subtitle.visible = true


func hide_game_over() -> void:
	if game_over_label != null:
		game_over_label.visible = false
	if game_over_subtitle != null:
		game_over_subtitle.visible = false
