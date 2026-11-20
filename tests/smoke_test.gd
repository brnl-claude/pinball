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


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
