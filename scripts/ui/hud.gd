extends CanvasLayer
## HUD (G16) -- health bar, ammo readout, game-over overlay, and (node 6) the
## start/title screen and victory screen. Built entirely in code so it is
## diffable and testable: tests assert on node values/visibility, not pixels.

var health_bar: ProgressBar = null
var health_label: Label = null
var ammo_label: Label = null
var game_over_label: Label = null
var game_over_subtitle: Label = null

# node 6: start (title) screen + victory screen.
var start_panel: ColorRect = null
var title_label: Label = null
var start_subtitle: Label = null
var controls_label: Label = null
var start_prompt: Label = null
var win_panel: ColorRect = null
var win_label: Label = null
var win_subtitle: Label = null
var win_prompt: Label = null


func _ready() -> void:
	layer = 10
	_build()


func _build() -> void:
	# --- gameplay HUD (health / ammo / game-over) ---
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

	# --- start (title) screen ---
	start_panel = _full_rect(Color(0.04, 0.06, 0.09, 0.62))
	start_panel.name = "StartPanel"
	start_panel.visible = false
	add_child(start_panel)

	title_label = _centered_label("TUMBLE", 68, Color(0.95, 0.90, 0.60), -150)
	title_label.name = "TitleLabel"
	title_label.visible = false
	add_child(title_label)

	start_subtitle = _centered_label(
		"Demolish the towers.  Dodge the debris.  Reach the far end.",
		22, Color(0.85, 0.85, 0.85), -70)
	start_subtitle.name = "StartSubtitle"
	start_subtitle.visible = false
	add_child(start_subtitle)

	controls_label = _centered_label(
		"WASD / arrows - move     Mouse - look     F or click - fire\nSpace - jump     Esc - release mouse     Enter - start / restart",
		15, Color(0.70, 0.75, 0.80), 10)
	controls_label.name = "ControlsLabel"
	controls_label.visible = false
	add_child(controls_label)

	start_prompt = _centered_label("Press ENTER or click to start", 24, Color(0.95, 0.70, 0.30), 150)
	start_prompt.name = "StartPrompt"
	start_prompt.visible = false
	add_child(start_prompt)

	# --- victory screen ---
	win_panel = _full_rect(Color(0.05, 0.20, 0.08, 0.60))
	win_panel.name = "WinPanel"
	win_panel.visible = false
	add_child(win_panel)

	win_label = _centered_label("LEVEL CLEARED", 60, Color(0.70, 1.00, 0.70), -80)
	win_label.name = "WinLabel"
	win_label.visible = false
	add_child(win_label)

	win_subtitle = _centered_label("You survived the gauntlet.", 22, Color(0.85, 0.95, 0.85), 10)
	win_subtitle.name = "WinSubtitle"
	win_subtitle.visible = false
	add_child(win_subtitle)

	win_prompt = _centered_label("Press ENTER to play again", 24, Color(0.95, 0.70, 0.30), 90)
	win_prompt.name = "WinPrompt"
	win_prompt.visible = false
	add_child(win_prompt)


func _full_rect(color: Color) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.set_anchors_preset(Control.PRESET_FULL_RECT)
	# Let clicks pass through to the game (the start/win screens respond to the
	# input handler, not to GUI focus).
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return r


func _centered_label(text: String, font_size: int, color: Color, v_offset: float) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	l.set_anchors_preset(Control.PRESET_FULL_RECT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.offset_top = v_offset
	l.offset_bottom = v_offset
	return l


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


func show_start_screen() -> void:
	_set_start_visible(true)


func hide_start_screen() -> void:
	_set_start_visible(false)


func show_win_screen() -> void:
	_set_win_visible(true)


func hide_win_screen() -> void:
	_set_win_visible(false)


func _set_start_visible(vis: bool) -> void:
	if start_panel != null:
		start_panel.visible = vis
	if title_label != null:
		title_label.visible = vis
	if start_subtitle != null:
		start_subtitle.visible = vis
	if controls_label != null:
		controls_label.visible = vis
	if start_prompt != null:
		start_prompt.visible = vis


func _set_win_visible(vis: bool) -> void:
	if win_panel != null:
		win_panel.visible = vis
	if win_label != null:
		win_label.visible = vis
	if win_subtitle != null:
		win_subtitle.visible = vis
	if win_prompt != null:
		win_prompt.visible = vis
