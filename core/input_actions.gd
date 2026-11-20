extends Node
## Registers the default controls in the InputMap.
##
## This is done in code rather than in project.godot so the defaults stay
## readable and easy to change. Actions that already exist (e.g. rebound by
## the player later) are not overwritten.

const ACTIONS := {
	"flipper_left": [
		{"key": KEY_SHIFT, "location": KEY_LOCATION_LEFT},
		{"joy_button": JOY_BUTTON_LEFT_SHOULDER},
	],
	"flipper_right": [
		{"key": KEY_SHIFT, "location": KEY_LOCATION_RIGHT},
		{"joy_button": JOY_BUTTON_RIGHT_SHOULDER},
	],
	"plunger": [
		{"key": KEY_ENTER},
		{"joy_button": JOY_BUTTON_A},
	],
	"nudge_left": [{"key": KEY_Z}],
	"nudge_right": [{"key": KEY_SLASH}],
	"nudge_up": [{"key": KEY_SPACE}],
	"start_game": [
		{"key": KEY_1},
		{"joy_button": JOY_BUTTON_START},
	],
	"pause": [
		{"key": KEY_ESCAPE},
		{"joy_button": JOY_BUTTON_BACK},
	],
	"reset_ball": [{"key": KEY_BACKSPACE}],
	"camera_next": [{"key": KEY_C}],
	"toggle_debug": [{"key": KEY_F3}],
	"rotate_screen": [{"key": KEY_F8}],
}


func _enter_tree() -> void:
	register_defaults()


static func register_defaults() -> void:
	for action: String in ACTIONS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.2)
		for spec: Dictionary in ACTIONS[action]:
			InputMap.action_add_event(action, _make_event(spec))


static func _make_event(spec: Dictionary) -> InputEvent:
	if spec.has("key"):
		var key_event := InputEventKey.new()
		key_event.physical_keycode = spec["key"]
		key_event.location = spec.get("location", KEY_LOCATION_UNSPECIFIED)
		return key_event
	var joy_event := InputEventJoypadButton.new()
	joy_event.button_index = spec["joy_button"]
	return joy_event
