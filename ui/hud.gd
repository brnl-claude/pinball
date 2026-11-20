extends CanvasLayer
## In-game HUD: score, ball number, bonus multiplier and messages from the
## rules. Built with anchors and containers, and sized relative to the
## viewport height, so it works from 9:16 portrait to 32:9.
##
## The camera's layout profile decides where the score goes: a bar at the
## top (portrait), a column next to the table (landscape) or panels on both
## sides (ultrawide). With in-game screen rotation the whole HUD turns along.

@export var rules_path: NodePath
## Text sizes as a fraction of the viewport height.
@export var score_size := 0.055
@export var info_size := 0.026
@export var message_size := 0.05
@export var message_seconds := 2.0

## Width of a side panel as a fraction of the (logical) view width.
@export var side_panel_width := 0.26
## Space above the score as a fraction of the view height.
@export var top_margin := 0.03

var rules: GameRules
var layout := CameraPreset.HudLayout.TOP_BAR

var _root: Control
var _left_box: VBoxContainer
var _right_box: VBoxContainer

var _score_label: Label
var _info_label: Label
var _message_label: Label
var _high_score_label: Label
var _message_time_left := 0.0


func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(_apply_layout)
	var settings := get_node_or_null("/root/DisplaySettings")
	if settings:
		settings.connect("changed", _apply_layout)
	var camera := get_viewport().get_camera_3d()
	if camera and camera.has_signal("preset_changed"):
		camera.connect("preset_changed", _on_preset_changed)
		var preset: CameraPreset = camera.call("active_preset")
		if preset:
			layout = preset.hud_layout
	_apply_layout()
	rules = get_node_or_null(rules_path)
	if rules:
		rules.message.connect(show_message)
		rules.game_over.connect(func(_score: int, _rank: int): _refresh_high_scores())
	_refresh_high_scores()


func _process(delta: float) -> void:
	if rules:
		_score_label.text = _format_score(rules.score)
		match rules.state:
			GameRules.State.PLAYING, GameRules.State.BALL_ENDING:
				var info := "BALL %d / %d    BONUS %d×" % [
					rules.ball_number, rules.balls_per_game, rules.multiplier]
				if rules.tilted:
					info += "    TILT"
				elif rules.ball_save_left > 0.0:
					info += "    BALL SAVE"
				if rules.multiball:
					info += "\nMULTIBALL    JACKPOT %d" % rules.jackpot
				elif rules.lock_lit:
					info += "\nLOCK IS LIT    LOCKED %d" % rules.locked
				elif rules.locked > 0:
					info += "\nLOCKED %d" % rules.locked
				if rules.mode >= 0:
					info += "\n%s  %d" % [GameRules.MODES[rules.mode]["name"], ceili(rules.mode_time_left)]
				_info_label.text = info
				_high_score_label.visible = false
			_:
				_info_label.text = "PRESS 1 TO START"
				_high_score_label.visible = true
	if _message_time_left > 0.0:
		_message_time_left -= delta
		if _message_time_left <= 0.0:
			_message_label.text = ""


func _on_preset_changed(preset: CameraPreset) -> void:
	layout = preset.hud_layout
	_apply_layout()


func show_message(text: String) -> void:
	_message_label.text = text
	_message_time_left = message_seconds


func _refresh_high_scores() -> void:
	if rules == null:
		return
	var lines := PackedStringArray(["HIGH SCORES"])
	for i in rules.high_scores.size():
		lines.append("%d.  %s" % [i + 1, _format_score(rules.high_scores[i])])
	_high_score_label.text = "\n".join(lines)


func _format_score(value: int) -> String:
	# 1234567 → 1,234,567
	var digits := str(value)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out


func _build() -> void:
	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	_left_box = _make_box()
	_right_box = _make_box()
	_score_label = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_left_box.add_child(_score_label)
	_info_label = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_left_box.add_child(_info_label)

	_message_label = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_message_label.set_anchors_preset(Control.PRESET_CENTER)
	_message_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	_root.add_child(_message_label)

	_high_score_label = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_high_score_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_high_score_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_high_score_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_high_score_label.offset_bottom = -24
	_root.add_child(_high_score_label)


func _make_box() -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_BEGIN
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)
	return box


## Lays the HUD out for the current profile, screen rotation and size.
func _apply_layout() -> void:
	var real_size := get_viewport().get_visible_rect().size
	var rotation_degrees_screen := ScreenRotation.current(get_tree())
	var size := ScreenRotation.logical_size(real_size, rotation_degrees_screen)
	transform = ScreenRotation.canvas_transform(real_size, rotation_degrees_screen)
	_root.position = Vector2.ZERO
	_root.size = size

	var margin := size.y * top_margin
	match layout:
		CameraPreset.HudLayout.SIDE_PANEL:
			_place(_left_box, 1.0 - side_panel_width, 1.0, margin)
			_move_label(_info_label, _left_box)
			_right_box.visible = false
		CameraPreset.HudLayout.SIDE_PANELS:
			_place(_left_box, 0.0, side_panel_width, margin)
			_place(_right_box, 1.0 - side_panel_width, 1.0, margin)
			_move_label(_info_label, _right_box)
			_right_box.visible = true
		_:
			_place(_left_box, 0.0, 1.0, margin)
			_move_label(_info_label, _left_box)
			_right_box.visible = false
	_apply_sizes()


## Anchors a box to a horizontal slice of the view, at the top.
func _place(box: Control, left: float, right: float, margin: float) -> void:
	box.anchor_left = left
	box.anchor_right = right
	box.anchor_top = 0.0
	box.anchor_bottom = 0.0
	box.offset_left = 0.0
	box.offset_right = 0.0
	box.offset_top = margin
	box.offset_bottom = margin


func _move_label(label: Label, box: Control) -> void:
	if label.get_parent() != box:
		label.reparent(box, false)


## Where the score label sits, in logical coordinates (for tests).
func score_rect() -> Rect2:
	return _score_label.get_global_rect()


func _make_label(align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.25))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	return label


func _apply_sizes() -> void:
	var height := _root.size.y if _root else get_viewport().get_visible_rect().size.y
	_set_size(_score_label, height * score_size)
	_set_size(_info_label, height * info_size)
	_set_size(_message_label, height * message_size)
	_set_size(_high_score_label, height * info_size)


func _set_size(label: Label, pixels: float) -> void:
	var size := maxi(int(pixels), 10)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", maxi(size / 6, 2))
