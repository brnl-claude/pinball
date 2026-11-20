class_name Cabinet
extends Node
## The cabinet the playfield sits in: nudging and the tilt bob.
##
## The playfield is the physics frame. A nudge shoves the cabinet: a short,
## hard push, after which the cabinet settles back on its legs (a damped
## spring). Balls feel the cabinet's acceleration `a` as an inertial force
## `-m·a`, so a free ball lags behind the shove and catches up again, while a
## ball resting on a flipper or post gets pushed along by it. That is how
## nudging works on a real machine.
##
## The tilt bob is a plumb bob pendulum hanging inside a ring. The sharp
## shove makes it swing (the soft settle back barely does); when it touches
## the ring, that is a tilt warning, and touching it again after the allowed
## warnings tilts the machine. Well-timed or wild nudging builds up the swing.
##
## Directions follow the player's body: "left" shoves the cabinet from the
## left side (it jolts right, so the ball moves left relative to the table),
## "up" shoves it forward, away from the player.

signal nudged(push: Vector3)
signal tilt_warning(warnings_left: int)
signal tilted

const NUDGE_ACTIONS := {
	"nudge_left": Vector3.RIGHT,
	"nudge_right": Vector3.LEFT,
	"nudge_up": Vector3.FORWARD,
}

@export var use_input := true

@export_group("Shove")
## Cabinet acceleration during a shove (m/s²).
@export var push_acceleration := 15.0
## How long the shove lasts (s).
@export var push_seconds := 0.02
## Minimum time between two shoves (s); nobody shoves faster than this.
@export var nudge_cooldown := 0.12
## The cabinet settles back like a damped spring on its legs.
@export var settle_frequency := 4.0
@export var settle_damping_ratio := 0.7

@export_group("Tilt bob")
@export var bob_length := 0.15
## Damping of the bob's swing (1/s).
@export var bob_damping := 1.0
## Distance from the bob to the ring at rest (m).
@export var ring_clearance := 0.045
## Warnings before the next touch tilts the machine.
@export var warnings_allowed := 2
## A single swing can touch the ring more than once; count it once.
@export var warning_cooldown := 0.5

## Cabinet displacement and velocity relative to its rest position.
var offset := Vector3.ZERO
var velocity := Vector3.ZERO
## Acceleration of the cabinet this tick (what the balls feel, reversed).
var acceleration := Vector3.ZERO
## Bob displacement and velocity relative to the cabinet (x/z).
var bob := Vector3.ZERO
var bob_velocity := Vector3.ZERO
var warnings := 0
var is_tilted := false

var _push := Vector3.ZERO
var _push_time_left := 0.0
var _cooldown_left := 0.0
var _warning_cooldown_left := 0.0


func _ready() -> void:
	add_to_group("cabinet")


func _physics_process(delta: float) -> void:
	if use_input:
		for action: String in NUDGE_ACTIONS:
			if Input.is_action_just_pressed(action):
				nudge(NUDGE_ACTIONS[action])
	step(delta)
	_apply_to_balls()


## Shoves the cabinet in a direction (x/z; unit length gives a normal shove).
## Returns false when the cabinet is still in the cooldown of the last shove.
func nudge(direction: Vector3) -> bool:
	if _cooldown_left > 0.0:
		return false
	_push = Vector3(direction.x, 0.0, direction.z) * push_acceleration
	_push_time_left = push_seconds
	_cooldown_left = nudge_cooldown
	nudged.emit(_push)
	SoundFx.play("nudge")
	return true


## Advances the cabinet and the tilt bob by one tick.
func step(delta: float) -> void:
	_cooldown_left = maxf(_cooldown_left - delta, 0.0)
	_warning_cooldown_left = maxf(_warning_cooldown_left - delta, 0.0)

	var push := Vector3.ZERO
	if _push_time_left > 0.0:
		push = _push
		_push_time_left -= delta

	var omega := TAU * settle_frequency
	var settle := -omega * omega * offset - 2.0 * settle_damping_ratio * omega * velocity
	acceleration = push + settle
	velocity += acceleration * delta
	offset += velocity * delta

	# Pendulum in the cabinet's frame, driven by the shove.
	var gravity := float(ProjectSettings.get_setting("physics/3d/default_gravity", 9.81))
	var bob_acceleration := -(gravity / bob_length) * bob - bob_damping * bob_velocity - push
	bob_velocity += bob_acceleration * delta
	bob += bob_velocity * delta

	if bob.length() >= ring_clearance and _warning_cooldown_left <= 0.0:
		_warning_cooldown_left = warning_cooldown
		_touch_ring()


func _touch_ring() -> void:
	if is_tilted:
		return
	if warnings < warnings_allowed:
		warnings += 1
		tilt_warning.emit(warnings_allowed - warnings)
		SoundFx.play("tilt_warning")
	else:
		is_tilted = true
		tilted.emit()
		SoundFx.play("tilt")


## Clears warnings and the tilt, e.g. at the start of a ball.
func reset_tilt() -> void:
	warnings = 0
	is_tilted = false
	bob = Vector3.ZERO
	bob_velocity = Vector3.ZERO
	_warning_cooldown_left = 0.0


func _apply_to_balls() -> void:
	for node in get_tree().get_nodes_in_group("balls"):
		if node is Ball:
			node.set_frame_acceleration(acceleration)
