extends CanvasLayer
## In-game HUD: score, ball number, bonus multiplier and messages from the
## rules. Built with anchors and containers, and sized relative to the
## viewport height, so it works from 9:16 portrait to 32:9.

@export var rules_path: NodePath
## Text sizes as a fraction of the viewport height.
@export var score_size := 0.055
@export var info_size := 0.026
@export var message_size := 0.05
@export var message_seconds := 2.0

var rules: GameRules

var _score_label: Label
var _info_label: Label
var _message_label: Label
var _high_score_label: Label
var _message_time_left := 0.0


func _ready() -> void:
	_build()
	get_viewport().size_changed.connect(_apply_sizes)
	_apply_sizes()
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
				if rules.ball_save_left > 0.0:
					info += "    BALL SAVE"
				_info_label.text = info
				_high_score_label.visible = false
			_:
				_info_label.text = "PRESS 1 TO START"
				_high_score_label.visible = true
	if _message_time_left > 0.0:
		_message_time_left -= delta
		if _message_time_left <= 0.0:
			_message_label.text = ""


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
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var top := VBoxContainer.new()
	top.set_anchors_preset(Control.PRESET_TOP_WIDE)
	top.offset_top = 12
	top.alignment = BoxContainer.ALIGNMENT_BEGIN
	top.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(top)

	_score_label = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	top.add_child(_score_label)
	_info_label = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	top.add_child(_info_label)

	_message_label = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_message_label.set_anchors_preset(Control.PRESET_CENTER)
	_message_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_message_label.grow_vertical = Control.GROW_DIRECTION_BOTH
	root.add_child(_message_label)

	_high_score_label = _make_label(HORIZONTAL_ALIGNMENT_CENTER)
	_high_score_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_high_score_label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_high_score_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_high_score_label.offset_bottom = -24
	root.add_child(_high_score_label)


func _make_label(align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_color_override("font_color", Color(1.0, 0.75, 0.25))
	label.add_theme_color_override("font_outline_color", Color.BLACK)
	return label


func _apply_sizes() -> void:
	var height := get_viewport().get_visible_rect().size.y
	_set_size(_score_label, height * score_size)
	_set_size(_info_label, height * info_size)
	_set_size(_message_label, height * message_size)
	_set_size(_high_score_label, height * info_size)


func _set_size(label: Label, pixels: float) -> void:
	var size := maxi(int(pixels), 10)
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_constant_override("outline_size", maxi(size / 6, 2))
