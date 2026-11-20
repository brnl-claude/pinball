extends Node3D
## Prototype table: serves the ball into the shooter lane, serves a new one
## after the ball drains, and keeps a simple score from every part that
## emits `scored`. Backspace re-serves the ball by hand. Full game rules
## (balls per game, bonus, high scores) arrive in Phase 4.

signal ball_drained
signal score_changed(score: int)

@export var respawn_delay := 1.0

@onready var ball: Ball = $Ball
@onready var plunger: Plunger = $Plunger
@onready var drain: Drain = $Drain
@onready var left_flipper: Flipper = $LeftFlipper
@onready var right_flipper: Flipper = $RightFlipper

var drained_count := 0
var score := 0


func _ready() -> void:
	add_to_group("table")
	drain.ball_drained.connect(_on_ball_drained)
	for node in find_children("*", "", true, false):
		if node.has_signal("scored"):
			node.connect("scored", _on_scored)
	serve_ball()


func _on_scored(points: int) -> void:
	score += points
	score_changed.emit(score)


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("reset_ball"):
		serve_ball()


func serve_ball() -> void:
	var radius := ball.tuning.scaled_ball_radius() if ball.tuning else 0.0135
	ball.reset_to(Transform3D(Basis.IDENTITY, plunger.ball_rest_position(radius)))
	drain.rearm(ball)


func _on_ball_drained(_drained: Ball) -> void:
	drained_count += 1
	ball_drained.emit()
	if respawn_delay >= 0.0:
		get_tree().create_timer(respawn_delay, true, true).timeout.connect(serve_ball)
