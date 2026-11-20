class_name Replay
extends Node
## Per-tick replay recording for debugging physics.
##
## Every physics tick the recorder stores the ball's state, both flippers,
## the plunger, the coil inputs and the cabinet's nudge offset in a ring
## buffer of the last `seconds`. F9 saves it to user://replays/, F10 plays
## the newest saved replay back by driving the ball and parts from the
## recording, so a bug can be watched again tick by tick (with F3 open).
##
## A frame is a PackedFloat32Array with the FIELD_* layout below; files are
## a small header plus raw float32 frames.

signal playback_finished

const MAGIC := "PBRP"
const VERSION := 1
const DIRECTORY := "user://replays"

const FIELD_TICK := 0
const FIELD_POSITION := 1      # 3 floats
const FIELD_ROTATION := 4      # quaternion, 4 floats
const FIELD_VELOCITY := 8      # 3 floats
const FIELD_SPIN := 11         # 3 floats
const FIELD_LEFT_STROKE := 14
const FIELD_RIGHT_STROKE := 15
const FIELD_PLUNGER_PULL := 16
const FIELD_INPUTS := 17       # bit 0 left coil, bit 1 right coil, bit 2 plunger held
const FIELD_CABINET := 18      # 3 floats
const FIELD_COUNT := 21

## How much history to keep (s).
@export var seconds := 30.0
@export var use_input := true

var table: Node
var recording := true
var is_playing := false

var _buffer: Array[PackedFloat32Array] = []
var _next := 0
var _tick := 0
var _playback: Array[PackedFloat32Array] = []
var _playback_index := 0


func _ready() -> void:
	if table == null:
		table = get_parent()


func _unhandled_input(event: InputEvent) -> void:
	if not use_input:
		return
	if event.is_action_pressed("save_replay"):
		var path := save_to_file()
		print("Replay saved: ", ProjectSettings.globalize_path(path))
	elif event.is_action_pressed("play_replay"):
		var newest := newest_file()
		if newest != "":
			play(load_file(newest))


func _physics_process(_delta: float) -> void:
	if is_playing:
		_play_tick()
	elif recording:
		record_tick()


func capacity() -> int:
	return maxi(1, int(seconds * Engine.physics_ticks_per_second))


## Stores the current state as one frame.
func record_tick() -> void:
	var frame := capture()
	if _buffer.size() < capacity():
		_buffer.append(frame)
	else:
		_buffer[_next] = frame
	_next = (_next + 1) % capacity()
	_tick += 1


func capture() -> PackedFloat32Array:
	var frame := PackedFloat32Array()
	frame.resize(FIELD_COUNT)
	frame[FIELD_TICK] = _tick
	var ball: RigidBody3D = table.get("ball")
	var left: Node = table.get("left_flipper")
	var right: Node = table.get("right_flipper")
	var plunger: Node = table.get("plunger")
	var cabinet: Node = table.get("cabinet")
	if ball:
		frame = _put(frame, FIELD_POSITION, ball.position)
		var q := ball.quaternion
		frame[FIELD_ROTATION] = q.x
		frame[FIELD_ROTATION + 1] = q.y
		frame[FIELD_ROTATION + 2] = q.z
		frame[FIELD_ROTATION + 3] = q.w
		frame = _put(frame, FIELD_VELOCITY, ball.linear_velocity)
		frame = _put(frame, FIELD_SPIN, ball.angular_velocity)
	var inputs := 0
	if left:
		frame[FIELD_LEFT_STROKE] = left.get("stroke_angle")
		inputs |= 1 if left.get("energized") else 0
	if right:
		frame[FIELD_RIGHT_STROKE] = right.get("stroke_angle")
		inputs |= 2 if right.get("energized") else 0
	if plunger:
		frame[FIELD_PLUNGER_PULL] = plunger.get("pull")
		inputs |= 4 if plunger.get("pulled") else 0
	frame[FIELD_INPUTS] = inputs
	if cabinet:
		frame = _put(frame, FIELD_CABINET, cabinet.get("offset"))
	return frame


## The recorded frames, oldest first.
func frames() -> Array[PackedFloat32Array]:
	if _buffer.size() < capacity():
		return _buffer.duplicate()
	var ordered: Array[PackedFloat32Array] = []
	ordered.append_array(_buffer.slice(_next))
	ordered.append_array(_buffer.slice(0, _next))
	return ordered


func clear() -> void:
	_buffer.clear()
	_next = 0


## Saves the recorded frames and returns the file path.
func save_to_file(path := "") -> String:
	if path == "":
		DirAccess.make_dir_recursive_absolute(DIRECTORY)
		path = "%s/replay_%s.pbr" % [DIRECTORY, Time.get_datetime_string_from_system().replace(":", "-")]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write replay to %s" % path)
		return ""
	var recorded := frames()
	file.store_buffer(MAGIC.to_ascii_buffer())
	file.store_32(VERSION)
	file.store_32(Engine.physics_ticks_per_second)
	file.store_32(FIELD_COUNT)
	file.store_32(recorded.size())
	for frame in recorded:
		file.store_buffer(frame.to_byte_array())
	return path


static func load_file(path: String) -> Array[PackedFloat32Array]:
	var result: Array[PackedFloat32Array] = []
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return result
	if file.get_buffer(4).get_string_from_ascii() != MAGIC or file.get_32() != VERSION:
		push_error("%s is not a replay file" % path)
		return result
	file.get_32()  # tick rate
	var field_count := file.get_32()
	var count := file.get_32()
	for i in count:
		result.append(file.get_buffer(field_count * 4).to_float32_array())
	return result


static func newest_file() -> String:
	var dir := DirAccess.open(DIRECTORY)
	if dir == null:
		return ""
	var files := Array(dir.get_files()).filter(func(f: String): return f.ends_with(".pbr"))
	if files.is_empty():
		return ""
	files.sort()
	return "%s/%s" % [DIRECTORY, files[-1]]


## Plays frames back: the ball follows the recording exactly (it is frozen
## and moved kinematically) and the flippers and plunger take the recorded
## positions. Recording pauses meanwhile. When the recording ends, the ball
## gets its recorded velocity back and physics carries on from there.
func play(recorded: Array[PackedFloat32Array]) -> void:
	if recorded.is_empty():
		return
	_playback = recorded
	_playback_index = 0
	is_playing = true
	var ball: RigidBody3D = table.get("ball")
	if ball:
		ball.freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
		ball.freeze = true
	for part_name: String in ["left_flipper", "right_flipper", "plunger"]:
		var part: Node = table.get(part_name)
		if part:
			part.set("use_input", false)
	var cabinet: Node = table.get("cabinet")
	if cabinet:
		cabinet.set("use_input", false)


func stop() -> void:
	if not is_playing:
		return
	is_playing = false
	var ball: RigidBody3D = table.get("ball")
	if ball:
		ball.freeze = false
		# Carry on from the last recorded state.
		if not _playback.is_empty():
			var last := _playback[mini(_playback_index, _playback.size()) - 1]
			ball.linear_velocity = _get3(last, FIELD_VELOCITY)
			ball.angular_velocity = _get3(last, FIELD_SPIN)
	for part_name: String in ["left_flipper", "right_flipper", "plunger", "cabinet"]:
		var part: Node = table.get(part_name)
		if part:
			part.set("use_input", true)
	playback_finished.emit()


func _play_tick() -> void:
	if _playback_index >= _playback.size():
		stop()
		return
	var frame := _playback[_playback_index]
	_playback_index += 1
	var ball: RigidBody3D = table.get("ball")
	if ball:
		ball.position = _get3(frame, FIELD_POSITION)
		ball.quaternion = Quaternion(frame[FIELD_ROTATION], frame[FIELD_ROTATION + 1],
				frame[FIELD_ROTATION + 2], frame[FIELD_ROTATION + 3]).normalized()
	var inputs := int(frame[FIELD_INPUTS])
	var left: Node = table.get("left_flipper")
	var right: Node = table.get("right_flipper")
	if left:
		left.set("energized", inputs & 1 != 0)
		left.call("set_stroke", frame[FIELD_LEFT_STROKE])
	if right:
		right.set("energized", inputs & 2 != 0)
		right.call("set_stroke", frame[FIELD_RIGHT_STROKE])
	var plunger: Node = table.get("plunger")
	if plunger:
		plunger.set("pulled", inputs & 4 != 0)
		plunger.call("set_pull", frame[FIELD_PLUNGER_PULL])


## Packed arrays are passed by value, so this returns the updated frame.
static func _put(frame: PackedFloat32Array, index: int, value: Vector3) -> PackedFloat32Array:
	frame[index] = value.x
	frame[index + 1] = value.y
	frame[index + 2] = value.z
	return frame


static func _get3(frame: PackedFloat32Array, index: int) -> Vector3:
	return Vector3(frame[index], frame[index + 1], frame[index + 2])
