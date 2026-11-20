class_name Dmd
extends Control
## A dot-matrix display of 128 × 32 orange dots, as in the backbox of a
## 90s machine. It shows the score and ball, lock, multiball and mode
## status while playing, the rules' messages, and an attract loop with the
## high score. Dots are drawn by a shader from a 128 × 32 brightness image,
## with dim "off" dots like a real plasma display.
##
## Text uses a built-in 5 × 7 font, drawn at 1× (21 characters per line) or
## 2× (10 characters) size.

const COLUMNS := 128
const ROWS := 32
const GLYPH_WIDTH := 5
const GLYPH_HEIGHT := 7
## Each row is a 5-bit pattern, most significant bit on the left.
const GLYPHS := {
	"A": [14, 17, 17, 31, 17, 17, 17],
	"B": [30, 17, 17, 30, 17, 17, 30],
	"C": [14, 17, 16, 16, 16, 17, 14],
	"D": [30, 17, 17, 17, 17, 17, 30],
	"E": [31, 16, 16, 30, 16, 16, 31],
	"F": [31, 16, 16, 30, 16, 16, 16],
	"G": [14, 17, 16, 23, 17, 17, 15],
	"H": [17, 17, 17, 31, 17, 17, 17],
	"I": [14, 4, 4, 4, 4, 4, 14],
	"J": [7, 2, 2, 2, 2, 18, 12],
	"K": [17, 18, 20, 24, 20, 18, 17],
	"L": [16, 16, 16, 16, 16, 16, 31],
	"M": [17, 27, 21, 21, 17, 17, 17],
	"N": [17, 17, 25, 21, 19, 17, 17],
	"O": [14, 17, 17, 17, 17, 17, 14],
	"P": [30, 17, 17, 30, 16, 16, 16],
	"Q": [14, 17, 17, 17, 21, 18, 13],
	"R": [30, 17, 17, 30, 20, 18, 17],
	"S": [15, 16, 16, 14, 1, 1, 30],
	"T": [31, 4, 4, 4, 4, 4, 4],
	"U": [17, 17, 17, 17, 17, 17, 14],
	"V": [17, 17, 17, 17, 17, 10, 4],
	"W": [17, 17, 17, 21, 21, 21, 10],
	"X": [17, 17, 10, 4, 10, 17, 17],
	"Y": [17, 17, 10, 4, 4, 4, 4],
	"Z": [31, 1, 2, 4, 8, 16, 31],
	"0": [14, 17, 19, 21, 25, 17, 14],
	"1": [4, 12, 4, 4, 4, 4, 14],
	"2": [14, 17, 1, 2, 4, 8, 31],
	"3": [30, 1, 1, 14, 1, 1, 30],
	"4": [2, 6, 10, 18, 31, 2, 2],
	"5": [31, 16, 30, 1, 1, 17, 14],
	"6": [6, 8, 16, 30, 17, 17, 14],
	"7": [31, 1, 2, 4, 8, 8, 8],
	"8": [14, 17, 17, 14, 17, 17, 14],
	"9": [14, 17, 17, 15, 1, 2, 12],
	",": [0, 0, 0, 0, 0, 4, 8],
	".": [0, 0, 0, 0, 0, 0, 4],
	"!": [4, 4, 4, 4, 4, 0, 4],
	"-": [0, 0, 0, 14, 0, 0, 0],
	":": [0, 4, 0, 0, 0, 4, 0],
	"/": [1, 1, 2, 4, 8, 16, 16],
	"%": [25, 25, 2, 4, 8, 19, 19],
	"×": [0, 17, 10, 4, 10, 17, 0],
	"'": [4, 4, 0, 0, 0, 0, 0],
}

const SHADER := """
shader_type canvas_item;

uniform vec4 dot_color : source_color = vec4(1.0, 0.45, 0.1, 1.0);
uniform vec2 grid = vec2(128.0, 32.0);

void fragment() {
	vec2 cell = UV * grid;
	float lit = texture(TEXTURE, (floor(cell) + 0.5) / grid).r;
	float d = length(fract(cell) - 0.5);
	float dot_mask = 1.0 - smoothstep(0.3, 0.45, d);
	vec3 off_color = dot_color.rgb * 0.07;
	vec3 color = mix(off_color, dot_color.rgb * 1.6, lit);
	COLOR = vec4(color * dot_mask, 1.0);
}
"""

@export var dot_color := Color(1.0, 0.45, 0.1)
@export var message_seconds := 2.0
## Seconds per page of the attract loop.
@export var attract_page_seconds := 3.0

var rules: GameRules

var _image: Image
var _texture: ImageTexture
var _material: ShaderMaterial
var _message := ""
var _message_left := 0.0
var _time := 0.0
## What is on the display now, to skip redrawing an unchanged frame.
var _shown := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_image = Image.create(COLUMNS, ROWS, false, Image.FORMAT_L8)
	_texture = ImageTexture.create_from_image(_image)
	var shader := Shader.new()
	shader.code = SHADER
	_material = ShaderMaterial.new()
	_material.shader = shader
	_material.set_shader_parameter("dot_color", dot_color)
	material = _material


func show_message(text: String) -> void:
	_message = text
	_message_left = message_seconds


func _process(delta: float) -> void:
	_time += delta
	_message_left = maxf(_message_left - delta, 0.0)
	var ops := _compose()
	var key := str(ops)
	if key != _shown:
		_shown = key
		_render(ops)


func _draw() -> void:
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false)


## The frame to show, as text draw operations: [text, x, y, scale, level],
## where x = -1 centres the text.
func _compose() -> Array:
	if _message_left > 0.0 and _message != "":
		# Flash for the first half second.
		var level := 1.0 if _message_left < message_seconds - 0.5 \
				or fmod(_message_left, 0.2) > 0.1 else 0.45
		return _message_ops(_message, level)
	if rules == null:
		return [["PINBALL", -1, 9, 2, 1.0]]
	match rules.state:
		GameRules.State.PLAYING, GameRules.State.BALL_ENDING:
			return _playing_ops()
		GameRules.State.GAME_OVER:
			return [["GAME OVER", -1, 4, 2, 1.0], [format_score(rules.score), -1, 22, 1, 0.8]]
	return _attract_ops()


func _playing_ops() -> Array:
	var ops: Array = []
	var score_text := format_score(rules.score)
	var big := text_width(score_text, 2) <= COLUMNS
	ops.append([score_text, -1, 1 if big else 5, 2 if big else 1, 1.0])
	ops.append(["BALL %d" % rules.ball_number, 1, 17, 1, 0.6])
	var right := "%d×" % rules.multiplier
	ops.append([right, COLUMNS - text_width(right, 1) - 1, 17, 1, 0.6])
	var status := ""
	if rules.tilted:
		status = "TILT"
	elif rules.mode >= 0:
		status = "%s %d" % [GameRules.MODES[rules.mode]["name"], ceili(rules.mode_time_left)]
	elif rules.multiball:
		status = "JACKPOT " + format_score(rules.jackpot)
	elif rules.lock_lit:
		status = "LOCK IS LIT"
	elif rules.ball_save_left > 0.0:
		status = "BALL SAVE"
	if status != "":
		ops.append([status, -1, 25, 1, 0.85])
	return ops


func _attract_ops() -> Array:
	var page := int(_time / attract_page_seconds) % 2
	if page == 1 and not rules.high_scores.is_empty():
		return [["HIGH SCORE", -1, 4, 1, 0.8], [format_score(rules.high_scores[0]), -1, 15, 2, 1.0]]
	return [["PRESS START", -1, 9, 1 if text_width("PRESS START", 2) > COLUMNS else 2, 1.0]]


## A message, as large as fits: one line at 2×, else up to three lines at 1×.
func _message_ops(text: String, level: float) -> Array:
	if text_width(text, 2) <= COLUMNS:
		return [[text, -1, 9, 2, level]]
	var lines := _wrap(text, COLUMNS)
	var ops: Array = []
	var top := int((ROWS - lines.size() * 10 + 3) / 2.0)
	for i in lines.size():
		ops.append([lines[i], -1, top + i * 10, 1, level])
	return ops


static func _wrap(text: String, width: int) -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		var candidate := word if line == "" else line + " " + word
		if line != "" and text_width(candidate, 1) > width:
			lines.append(line)
			line = word
		else:
			line = candidate
	if line != "":
		lines.append(line)
	return lines.slice(0, 3)


func _render(ops: Array) -> void:
	_image.fill(Color.BLACK)
	for op: Array in ops:
		var text: String = op[0]
		var scale: int = op[3]
		var x: int = op[1]
		if x < 0:
			x = int((COLUMNS - text_width(text, scale)) / 2.0)
		paint_text(_image, text, x, op[2], scale, op[4])
	_texture.update(_image)
	queue_redraw()


## Width in dots of a text at a scale (one dot of spacing per character).
static func text_width(text: String, scale: int) -> int:
	return maxi(text.length() * (GLYPH_WIDTH + 1) - 1, 0) * scale


## Draws text into a brightness image with its top-left corner at (x, y).
static func paint_text(image: Image, text: String, x: int, y: int, scale: int, level: float) -> void:
	var color := Color(level, level, level)
	for i in text.length():
		var rows: Array = GLYPHS.get(text[i].to_upper(), [])
		var left := x + i * (GLYPH_WIDTH + 1) * scale
		for row in rows.size():
			for column in GLYPH_WIDTH:
				if int(rows[row]) & (1 << (GLYPH_WIDTH - 1 - column)):
					var rect := Rect2i(left + column * scale, y + row * scale, scale, scale)
					rect = rect.intersection(Rect2i(0, 0, COLUMNS, ROWS))
					if rect.has_area():
						image.fill_rect(rect, color)


## 1234567 → "1,234,567"
static func format_score(value: int) -> String:
	var digits := str(value)
	var out := ""
	for i in digits.length():
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out
