extends CanvasLayer
## Pause and settings menu, opened with the pause action (Esc / Back). It
## pauses the game and edits the GameSettings (slope, difficulty, balls per
## game) and DisplaySettings (screen rotation, render scale) autoloads,
## which save themselves. Works with mouse, keyboard and gamepad (focus
## starts on Resume), and turns along with the in-game screen rotation.

signal opened
signal closed

const GameSettingsScript := preload("res://core/game_settings.gd")
const DisplaySettingsScript := preload("res://core/display_settings.gd")

## Panel width and text size as fractions of the (logical) view height.
@export var panel_width := 0.75
@export var text_size := 0.03

var is_open := false

var _root: Control
var _panel: PanelContainer
var _resume: Button
var _slope: HSlider
var _slope_label: Label
var _difficulty: OptionButton
var _balls: OptionButton
var _rotation: OptionButton
var _render_scale: OptionButton


func _ready() -> void:
	layer = 3
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()
	visible = false
	get_viewport().size_changed.connect(_apply_layout)
	var display := _display()
	if display:
		display.connect("changed", _apply_layout)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause"):
		toggle()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


func open() -> void:
	is_open = true
	visible = true
	get_tree().paused = true
	_refresh()
	_apply_layout()
	_resume.grab_focus()
	opened.emit()


func close() -> void:
	is_open = false
	visible = false
	get_tree().paused = false
	closed.emit()


func _game() -> Node:
	return get_node_or_null("/root/GameSettings")


func _display() -> Node:
	return get_node_or_null("/root/DisplaySettings")


## Shows the current settings in the controls.
func _refresh() -> void:
	var game := _game()
	if game:
		_slope.set_value_no_signal(game.get("slope_degrees"))
		_difficulty.select(game.get("difficulty"))
		_balls.select(GameSettingsScript.BALL_COUNTS.find(game.get("balls_per_game")))
	var display := _display()
	if display:
		_rotation.select(int(display.get("screen_rotation") / 90.0))
		_render_scale.select(maxi(DisplaySettingsScript.RENDER_SCALES.find(display.get("render_scale")), 0))
	_update_slope_label()


func _update_slope_label() -> void:
	_slope_label.text = "%.1f°" % _slope.value


func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.55)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(shade)

	_panel = PanelContainer.new()
	_root.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "PAUSED"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)

	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 10)
	box.add_child(grid)

	var slope_row := HBoxContainer.new()
	_slope = HSlider.new()
	_slope.min_value = GameSettingsScript.SLOPE_MIN
	_slope.max_value = GameSettingsScript.SLOPE_MAX
	_slope.step = 0.1
	_slope.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_slope.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_slope.value_changed.connect(_on_slope_changed)
	slope_row.add_child(_slope)
	_slope_label = Label.new()
	_slope_label.custom_minimum_size.x = 80
	slope_row.add_child(_slope_label)
	slope_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_add_row(grid, "Table slope", slope_row)

	_difficulty = _option(["Easy", "Normal", "Hard"], _on_difficulty_selected)
	_add_row(grid, "Difficulty", _difficulty)
	_balls = _option(["3 balls", "5 balls"], _on_balls_selected)
	_add_row(grid, "Balls per game", _balls)
	_rotation = _option(["0°", "90°", "180°", "270°"], _on_rotation_selected)
	_add_row(grid, "Screen rotation", _rotation)
	var scales: Array[String] = []
	for scale: float in DisplaySettingsScript.RENDER_SCALES:
		scales.append("Native" if scale >= 1.0 else "FSR 2 at %d%%" % roundi(scale * 100.0))
	_render_scale = _option(scales, _on_render_scale_selected)
	_add_row(grid, "Render scale", _render_scale)

	var help := Label.new()
	help.text = "Flippers: Shift   Plunger: Enter   Nudge: Z / ? / Space\nMagna-save: left Ctrl   Start: 1   Camera: C"
	help.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	help.modulate = Color(1, 1, 1, 0.7)
	box.add_child(help)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 24)
	box.add_child(buttons)
	_resume = Button.new()
	_resume.text = "Resume"
	_resume.pressed.connect(close)
	buttons.add_child(_resume)
	var quit := Button.new()
	quit.text = "Quit"
	quit.pressed.connect(func(): get_tree().quit())
	buttons.add_child(quit)


func _add_row(grid: GridContainer, text: String, control: Control) -> void:
	var label := Label.new()
	label.text = text
	grid.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(control)


func _option(items: Array, callback: Callable) -> OptionButton:
	var option := OptionButton.new()
	for item: String in items:
		option.add_item(item)
	option.item_selected.connect(callback)
	return option


## Centres the panel and sizes the text for the view, along with the
## in-game screen rotation.
func _apply_layout() -> void:
	var real_size := get_viewport().get_visible_rect().size
	var degrees := ScreenRotation.current(get_tree())
	var size := ScreenRotation.logical_size(real_size, degrees)
	transform = ScreenRotation.canvas_transform(real_size, degrees)
	_root.position = Vector2.ZERO
	_root.size = size
	var font_size := maxi(int(minf(size.x, size.y) * text_size), 12)
	var theme := Theme.new()
	theme.default_font_size = font_size
	_root.theme = theme
	var width := minf(size.x * 0.92, size.y * panel_width)
	_panel.custom_minimum_size = Vector2(width, 0)
	_panel.reset_size()
	_panel.position = (size - _panel.get_combined_minimum_size()) * 0.5


func _on_slope_changed(value: float) -> void:
	_update_slope_label()
	var game := _game()
	if game:
		game.call("set_slope", value)


func _on_difficulty_selected(index: int) -> void:
	var game := _game()
	if game:
		game.call("set_difficulty", index)


func _on_balls_selected(index: int) -> void:
	var game := _game()
	if game:
		game.call("set_balls_per_game", GameSettingsScript.BALL_COUNTS[index])


func _on_rotation_selected(index: int) -> void:
	var display := _display()
	if display:
		display.call("set_screen_rotation", index * 90)


func _on_render_scale_selected(index: int) -> void:
	var display := _display()
	if display:
		display.call("set_render_scale", DisplaySettingsScript.RENDER_SCALES[index])
