extends Node
## Display settings, saved in user://settings.cfg. For now: screen rotation,
## for a landscape monitor turned upright in a cabinet without the OS
## knowing. The content is rotated clockwise by `screen_rotation` degrees:
## use 90 when the monitor's top edge points left, 270 when it points right.
## R cycles through 0, 90, 180 and 270.
##
## Render scale: the 3D view can render at a lower resolution and be
## upscaled with AMD FSR 2, which keeps 120 fps reachable at 7680×2160.
## V cycles through the steps in RENDER_SCALES; 100% renders natively.

signal changed

const PATH := "user://settings.cfg"
## Native, then FSR 2 "ultra quality", "quality", "balanced", "performance".
const RENDER_SCALES := [1.0, 0.77, 0.67, 0.59, 0.5]

var screen_rotation := 0
var render_scale := 1.0


func _ready() -> void:
	var config := ConfigFile.new()
	if config.load(PATH) == OK:
		screen_rotation = ScreenRotation.normalize(int(config.get_value("display", "screen_rotation", 0)))
		render_scale = clampf(float(config.get_value("display", "render_scale", 1.0)), 0.25, 1.0)
	apply_render_scale()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("rotate_screen"):
		set_screen_rotation(screen_rotation + 90)
	elif event.is_action_pressed("render_scale_next"):
		var index := RENDER_SCALES.find(render_scale)
		set_render_scale(RENDER_SCALES[(index + 1) % RENDER_SCALES.size()])


func set_screen_rotation(degrees: int) -> void:
	screen_rotation = ScreenRotation.normalize(degrees)
	changed.emit()
	_save()


func set_render_scale(value: float) -> void:
	render_scale = clampf(value, 0.25, 1.0)
	apply_render_scale()
	changed.emit()
	_save()


## Native rendering at 100%, FSR 2 upscaling below it.
func apply_render_scale() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	if render_scale >= 1.0:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
		viewport.scaling_3d_scale = 1.0
	else:
		viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2
		viewport.scaling_3d_scale = render_scale


func render_scale_name() -> String:
	return "native" if render_scale >= 1.0 else "FSR 2 at %d%%" % roundi(render_scale * 100.0)


func _save() -> void:
	var config := ConfigFile.new()
	config.load(PATH)
	config.set_value("display", "screen_rotation", screen_rotation)
	config.set_value("display", "render_scale", render_scale)
	config.save(PATH)
