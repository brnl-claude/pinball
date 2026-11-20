extends CanvasLayer
## Debug overlay: FPS, frame time, physics engine and tick rate, ball speed,
## camera profile, resolution and aspect ratio. Toggle with F3.

var _label: Label
var _frame_ms := 0.0


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


func _process(delta: float) -> void:
	# Smoothed frame time, so the number is readable.
	_frame_ms = lerpf(_frame_ms, delta * 1000.0, 0.1)
	if visible:
		_label.text = build_text()
		transform = ScreenRotation.canvas_transform(
				get_viewport().get_visible_rect().size, ScreenRotation.current(get_tree()))


func build_text() -> String:
	var size := get_viewport().get_visible_rect().size
	var window_size := DisplayServer.window_get_size()
	var aspect := float(window_size.x) / maxf(1.0, float(window_size.y))
	var lines := PackedStringArray([
		"FPS: %d  (%.2f ms)" % [Engine.get_frames_per_second(), _frame_ms],
		"Physics: %s @ %d Hz" % [
			ProjectSettings.get_setting("physics/3d/physics_engine"),
			Engine.physics_ticks_per_second,
		],
	])
	var rules := get_tree().current_scene.get_node_or_null("GameRules") if get_tree().current_scene else null
	if rules:
		lines.append("Rules: %s" % rules.call("state_name"))
	var balls := get_tree().get_nodes_in_group("balls")
	if not balls.is_empty():
		lines.append("Ball speed: %.2f m/s" % (balls[0] as RigidBody3D).linear_velocity.length())
	var cabinet := get_tree().get_first_node_in_group("cabinet")
	if cabinet:
		var bob: Vector3 = cabinet.get("bob")
		lines.append("Tilt bob: %.1f / %.1f mm  warnings %d%s" % [
			bob.length() * 1000.0, float(cabinet.get("ring_clearance")) * 1000.0,
			cabinet.get("warnings"), "  TILT" if cabinet.get("is_tilted") else "",
		])
	var camera := get_viewport().get_camera_3d()
	if camera and camera.has_method("profile_name"):
		lines.append("Camera: %s  [C]" % camera.call("profile_name"))
	lines.append("Window: %d×%d (%.2f:1)  viewport %d×%d" % [
		window_size.x, window_size.y, aspect, size.x, size.y,
	])
	var settings := get_node_or_null("/root/DisplaySettings")
	if settings:
		lines.append("Render: %s  [V]" % settings.call("render_scale_name"))
	lines.append("Display: %s / %s" % [
		DisplayServer.get_name(),
		RenderingServer.get_current_rendering_driver_name(),
	])
	lines.append("Shift: flippers  Enter: plunger  Z / slash / Space: nudge  Backspace: re-serve  V: render scale  R: rotate screen")
	return "\n".join(lines)
