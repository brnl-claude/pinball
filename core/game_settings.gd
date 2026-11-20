extends Node
## Game settings, saved in user://settings.cfg next to the display settings:
## playfield slope, difficulty and balls per game. Tables and rules read
## them through `apply_settings(settings)` when they load and whenever a
## setting changes (from the settings menu).

signal changed

const PATH := "user://settings.cfg"

enum Difficulty { EASY, NORMAL, HARD }

## Per difficulty: ball save time (s), tilt warnings before a tilt, and
## magna-save uses per ball.
const DIFFICULTY_PRESETS := {
	Difficulty.EASY: {"ball_save_seconds": 15.0, "tilt_warnings": 3, "magna_saves": 2},
	Difficulty.NORMAL: {"ball_save_seconds": 8.0, "tilt_warnings": 2, "magna_saves": 1},
	Difficulty.HARD: {"ball_save_seconds": 4.0, "tilt_warnings": 1, "magna_saves": 1},
}
const SLOPE_MIN := 5.5
const SLOPE_MAX := 8.0
const BALL_COUNTS := [3, 5]

var slope_degrees := 6.5
var difficulty := Difficulty.NORMAL
var balls_per_game := 3


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		slope_degrees = clampf(float(config.get_value("game", "slope_degrees", slope_degrees)), SLOPE_MIN, SLOPE_MAX)
		difficulty = clampi(int(config.get_value("game", "difficulty", difficulty)), 0, 2) as Difficulty
		var balls := int(config.get_value("game", "balls_per_game", balls_per_game))
		balls_per_game = balls if BALL_COUNTS.has(balls) else 3


func preset() -> Dictionary:
	return DIFFICULTY_PRESETS[difficulty]


func difficulty_name() -> String:
	return Difficulty.keys()[difficulty].capitalize()


func set_slope(degrees: float) -> void:
	slope_degrees = clampf(snappedf(degrees, 0.1), SLOPE_MIN, SLOPE_MAX)
	_changed()


func set_difficulty(value: int) -> void:
	difficulty = clampi(value, 0, 2) as Difficulty
	_changed()


func set_balls_per_game(value: int) -> void:
	balls_per_game = value if BALL_COUNTS.has(value) else 3
	_changed()


## Tells every table and rules node to pick up the settings.
func apply_all() -> void:
	for group in ["table", "rules"]:
		for node in get_tree().get_nodes_in_group(group):
			if node.has_method("apply_settings"):
				node.call("apply_settings", self)


func _changed() -> void:
	_save()
	apply_all()
	changed.emit()


func _save() -> void:
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("game", "slope_degrees", slope_degrees)
	config.set_value("game", "difficulty", difficulty)
	config.set_value("game", "balls_per_game", balls_per_game)
	config.save(PATH)
