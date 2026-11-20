extends SceneTree
## CI smoke test: checks the core settings and loads the main scene.
## Usage: godot --headless --script res://tests/smoke_test.gd

const FRAMES_TO_RUN := 30

var _failures: PackedStringArray = []
var _frames := 0
var _main: Node


func _initialize() -> void:
	_expect(ProjectSettings.get_setting("physics/3d/physics_engine") == "Jolt Physics",
			"physics engine must be Jolt")
	_expect(Engine.physics_ticks_per_second == 1000, "physics must run at 1000 Hz")
	_expect(ProjectSettings.get_setting("physics/common/physics_interpolation") == true,
			"physics interpolation must be enabled")
	# Jolt caps angular velocity at 47 rad/s by default, which limits a rolling
	# 27 mm ball to ~0.64 m/s. A ball at 20 m/s spins at ~1500 rad/s.
	_expect(ProjectSettings.get_setting("physics/jolt_physics_3d/limits/max_angular_velocity") >= 2000.0,
			"Jolt max angular velocity is too low for a rolling pinball")

	var input_actions = load("res://core/input_actions.gd")
	input_actions.register_defaults()
	for action: String in ["flipper_left", "flipper_right", "plunger", "nudge_left", "reset_ball"]:
		_expect(InputMap.has_action(action), "missing input action: %s" % action)

	if not root.has_node("DisplaySettings"):
		var settings: Node = load("res://core/display_settings.gd").new()
		settings.name = "DisplaySettings"
		root.add_child(settings)

	var scene: PackedScene = load("res://main.tscn")
	_expect(scene != null, "main.tscn failed to load")
	if scene:
		_main = scene.instantiate()
		root.add_child(_main)


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames < FRAMES_TO_RUN:
		return false
	if _main:
		var overlay = _main.get_node_or_null("DebugOverlay")
		_expect(overlay != null and overlay.build_text().contains("Jolt"),
				"debug overlay does not show the physics engine")
		_expect(get_nodes_in_group("balls").size() == 1, "main scene must contain one ball")
		_check_camera_framing()
		_check_layout_profiles()
		_check_graphics()
	if _failures.is_empty():
		print("SMOKE TEST OK")
		quit(0)
	else:
		for failure in _failures:
			printerr("SMOKE TEST FAIL: ", failure)
		quit(1)
	return true


## The camera must fit the whole table on every supported aspect ratio.
func _check_camera_framing() -> void:
	var rig = load("res://cameras/camera_rig.gd")
	var size := Vector3(0.55, 0.07, 1.11)
	var center := Vector3(0.0, 0.03, 0.0)
	var corners: PackedVector3Array = rig.box_corners(center, size)
	for aspect: float in [9.0 / 16.0, 16.0 / 9.0, 21.0 / 9.0, 32.0 / 9.0]:
		for pitch: float in [38.0, 62.0, 90.0]:
			var xform: Transform3D = rig.compute_framing(pitch, 50.0, aspect, center, size, 1.04)
			var tan_v := tan(deg_to_rad(25.0))
			_expect(rig.corners_visible(xform, corners, tan_v * aspect, tan_v),
					"table does not fit at aspect %.2f, pitch %.0f" % [aspect, pitch])


## Profiles are picked by aspect ratio; screen rotation swaps the aspect,
## rolls the camera and turns the HUD.
func _check_layout_profiles() -> void:
	var presets := CameraPreset.defaults()
	var expected := {9.0 / 16.0: "portrait", 3.0 / 4.0: "portrait", 16.0 / 9.0: "landscape",
			21.0 / 9.0: "landscape", 32.0 / 9.0: "ultrawide"}
	for aspect: float in expected:
		var preset := CameraPreset.select(presets, aspect)
		_expect(preset.name == expected[aspect],
				"aspect %.2f picks %s, expected %s" % [aspect, preset.name, expected[aspect]])
		var rig = load("res://cameras/camera_rig.gd")
		var size := Vector3(0.55, 0.07, 1.11)
		var center := Vector3(0.0, 0.03, 0.0)
		var xform: Transform3D = rig.compute_framing(preset.pitch_degrees, preset.fov_degrees,
				aspect, center, size, preset.framing_margin)
		var tan_v := tan(deg_to_rad(preset.fov_degrees) * 0.5)
		_expect(rig.corners_visible(xform, rig.box_corners(center, size), tan_v * aspect, tan_v),
				"table does not fit with the %s preset at aspect %.2f" % [preset.name, aspect])

	# Rotation helpers: a quarter turn swaps the size and maps the logical
	# view exactly onto the real one.
	var real := Vector2(1920, 1080)
	for degrees: int in [0, 90, 180, 270]:
		var logical := ScreenRotation.logical_size(real, degrees)
		var xf := ScreenRotation.canvas_transform(real, degrees)
		var mapped := Rect2(xf * Vector2.ZERO, Vector2.ZERO).expand(xf * logical)
		_expect(mapped.position.distance_to(Vector2.ZERO) < 0.01 and mapped.size.distance_to(real) < 0.01,
				"screen rotation %d° does not map the view onto the screen (%s)" % [degrees, mapped])

	var settings := root.get_node_or_null("DisplaySettings")
	var camera = _main.get_node("Camera")
	var hud = _main.get_node("Hud")
	if settings == null:
		_failures.append("DisplaySettings is missing")
		return
	var saved: int = settings.get("screen_rotation")
	settings.call("set_screen_rotation", 0)
	var aspect_before: float = camera.viewport_aspect()
	_expect(hud.layout == camera.active_preset().hud_layout, "the HUD follows the camera's layout profile")
	settings.call("set_screen_rotation", 90)
	var aspect_after: float = camera.viewport_aspect()
	_expect(is_equal_approx(aspect_after, 1.0 / aspect_before),
			"a quarter turn swaps the aspect ratio (%.3f → %.3f)" % [aspect_before, aspect_after])
	_expect(camera.keep_aspect == Camera3D.KEEP_WIDTH, "a quarter turn keeps the logical vertical FOV")
	_expect(camera.global_transform.basis.x.dot(Vector3.RIGHT) < 0.1,
			"a quarter turn rolls the camera")
	_expect(hud.layout == camera.active_preset().hud_layout, "the HUD follows the rotated profile")
	_expect(is_equal_approx(hud.transform.get_rotation(), PI / 2.0), "a quarter turn rotates the HUD")
	print("Layout: %.2f:1 unrotated, rotated 90°: %s" % [aspect_before, camera.profile_name()])
	settings.call("set_screen_rotation", saved)


## Graphics pass: PBR finishes, chrome ball, reflection probe and FSR 2.
func _check_graphics() -> void:
	var playfield = _main.get_node("Table/Playfield")
	var playfield_material: StandardMaterial3D = playfield.get("surface_material")
	_expect(playfield_material != null and playfield_material.clearcoat_enabled,
			"the playfield has a clear-coated finish")
	var ball: Ball = get_nodes_in_group("balls")[0]
	var ball_mesh: SphereMesh = null
	for child in ball.get_children():
		if child is MeshInstance3D:
			ball_mesh = child.mesh as SphereMesh
	var chrome: StandardMaterial3D = (ball_mesh.material as StandardMaterial3D) if ball_mesh else null
	_expect(chrome != null and chrome.metallic == 1.0 and chrome.roughness < 0.1,
			"the ball is polished chrome")
	_expect(_main.get_node_or_null("ReflectionProbe") is ReflectionProbe,
			"the main scene has a reflection probe over the table")

	var settings := root.get_node_or_null("DisplaySettings")
	if settings == null:
		return
	var saved: float = settings.get("render_scale")
	settings.call("set_render_scale", 0.67)
	_expect(root.scaling_3d_mode == Viewport.SCALING_3D_MODE_FSR2 and is_equal_approx(root.scaling_3d_scale, 0.67),
			"a render scale below 100% upscales with FSR 2")
	settings.call("set_render_scale", 1.0)
	_expect(root.scaling_3d_mode != Viewport.SCALING_3D_MODE_FSR2 and root.scaling_3d_scale == 1.0,
			"100% renders natively")
	settings.call("set_render_scale", saved)


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
