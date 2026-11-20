extends Node
## Display settings, saved in user://settings.cfg. For now: screen rotation,
## for a landscape monitor turned upright in a cabinet without the OS
## knowing. The content is rotated clockwise by `screen_rotation` degrees:
## use 90 when the monitor's top edge points left, 270 when it points right.
## F8 cycles through 0, 90, 180 and 270.

signal changed

const PATH := "user://settings.cfg"

var screen_rotation := 0


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		screen_rotation = ScreenRotation.normalize(int(config.get_value("display", "screen_rotation", 0)))


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rotate_screen"):
		set_screen_rotation(screen_rotation + 90)


func set_screen_rotation(degrees: int) -> void:
	screen_rotation = ScreenRotation.normalize(degrees)
	changed.emit()
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("display", "screen_rotation", screen_rotation)
	config.save(PATH)
