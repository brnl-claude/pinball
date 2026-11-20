extends CanvasLayer
## Debug overlay: FPS, physics tick rate, physics engine, resolution and
## aspect ratio. Toggle with F3.

var _label: Label


func _ready() -> void:
	_label = Label.new()
	_label.position = Vector2(16, 16)
	_label.add_theme_font_size_override("font_size", 20)
	_label.add_theme_color_override("font_outline_color", Color.BLACK)
	_label.add_theme_constant_override("outline_size", 6)
	add_child(_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_debug"):
		visible = not visible


func _process(_delta: float) -> void:
	if not visible:
		return
	_label.text = build_text()


func build_text() -> String:
	var size := get_viewport().get_visible_rect().size
	var window_size := DisplayServer.window_get_size()
	var aspect := float(window_size.x) / maxf(1.0, float(window_size.y))
	return "\n".join([
		"FPS: %d" % Engine.get_frames_per_second(),
		"Physics: %s @ %d Hz" % [
			ProjectSettings.get_setting("physics/3d/physics_engine"),
			Engine.physics_ticks_per_second,
		],
		"Window: %d×%d (%.2f:1)  viewport %d×%d" % [
			window_size.x, window_size.y, aspect, size.x, size.y,
		],
		"Display: %s / %s" % [
			DisplayServer.get_name(),
			RenderingServer.get_current_rendering_driver_name(),
		],
	])
