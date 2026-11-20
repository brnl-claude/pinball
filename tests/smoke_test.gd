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

	var input_actions = load("res://core/input_actions.gd")
	input_actions.register_defaults()
	for action: String in ["flipper_left", "flipper_right", "plunger", "nudge_left"]:
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
	if _failures.is_empty():
		print("SMOKE TEST OK")
		quit(0)
	else:
		for failure in _failures:
			printerr("SMOKE TEST FAIL: ", failure)
		quit(1)
	return true


func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures.append(message)
