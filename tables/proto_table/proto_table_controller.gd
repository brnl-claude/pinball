extends Node3D
## Prototype table: the physical side of the machine. It serves the ball into
## the shooter lane, reports drains and launches, and relays every part's
## `scored` signal with the part that scored. Game rules live separately in
## `GameRules`; without rules attached the table simply re-serves the ball
## after a drain (sandbox play). Backspace re-serves the ball by hand.
## The table owns a `Cabinet` for nudging and the tilt bob.

signal ball_drained
signal ball_launched
signal score_changed(score: int)
signal part_scored(points: int, part: Node)
signal tilt_warning(warnings_left: int)
signal tilted

## Seconds before re-serving after a drain; negative disables auto re-serve.
@export var respawn_delay := 1.0
## Balls with x above this are in the shooter lane.
@export var shooter_lane_x := 0.2

@onready var ball: Ball = $Ball
@onready var plunger: Plunger = $Plunger
@onready var drain: Drain = $Drain
@onready var left_flipper: Flipper = $LeftFlipper
@onready var right_flipper: Flipper = $RightFlipper

var cabinet: Cabinet
var drained_count := 0
## Raw points from all parts since the table loaded (rules keep the game score).
var score := 0

var _in_shooter_lane := true


func _ready() -> void:
	add_to_group("table")
	cabinet = Cabinet.new()
	cabinet.name = "Cabinet"
	add_child(cabinet)
	cabinet.tilt_warning.connect(tilt_warning.emit)
	cabinet.tilted.connect(_on_tilted)
	drain.ball_drained.connect(_on_ball_drained)
	for node in find_children("*", "", true, false):
		if node.has_signal("scored"):
			node.connect("scored", _on_scored.bind(node))
	serve_ball()


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("reset_ball"):
		serve_ball()
	var in_lane := ball.position.x > shooter_lane_x
	if _in_shooter_lane and not in_lane:
		ball_launched.emit()
	_in_shooter_lane = in_lane


func serve_ball() -> void:
	var radius := ball.tuning.scaled_ball_radius() if ball.tuning else 0.0135
	ball.reset_to(Transform3D(Basis.IDENTITY, plunger.ball_rest_position(radius)))
	drain.rearm(ball)
	_in_shooter_lane = true


func set_flippers_enabled(value: bool) -> void:
	left_flipper.enabled = value
	right_flipper.enabled = value


## Flippers, slingshots and pop bumpers: everything a tilt switches off.
func set_solenoids_enabled(value: bool) -> void:
	set_flippers_enabled(value)
	for type: Variant in [Slingshot, PopBumper]:
		for part in parts_of(type):
			part.set("enabled", value)


func reset_tilt() -> void:
	cabinet.reset_tilt()
	set_solenoids_enabled(true)


## All parts of a given class, e.g. `parts_of(Rollover)`.
func parts_of(type: Variant) -> Array[Node]:
	var result: Array[Node] = []
	for node in find_children("*", "", true, false):
		if is_instance_of(node, type):
			result.append(node)
	return result


func _on_scored(points: int, part: Node) -> void:
	score += points
	score_changed.emit(score)
	part_scored.emit(points, part)


func _on_tilted() -> void:
	set_solenoids_enabled(false)
	tilted.emit()


func _on_ball_drained(_drained: Ball) -> void:
	drained_count += 1
	ball_drained.emit()
	if respawn_delay >= 0.0:
		if cabinet.is_tilted:
			reset_tilt()
		get_tree().create_timer(respawn_delay, true, true).timeout.connect(serve_ball)
