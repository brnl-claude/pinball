extends Node3D
## Prototype table: serves the ball into the shooter lane, and serves a new
## one after the ball drains. Backspace re-serves the ball by hand.

signal ball_drained

@export var respawn_delay := 1.0

@onready var ball: Ball = $Ball
@onready var plunger: Plunger = $Plunger
@onready var drain: Drain = $Drain
@onready var left_flipper: Flipper = $LeftFlipper
@onready var right_flipper: Flipper = $RightFlipper

var drained_count := 0


func _ready() -> void:
	drain.ball_drained.connect(_on_ball_drained)
	serve_ball()


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("reset_ball"):
		serve_ball()


func serve_ball() -> void:
	var radius := ball.tuning.scaled_ball_radius() if ball.tuning else 0.0135
	ball.reset_to(Transform3D(Basis.IDENTITY, plunger.ball_rest_position(radius)))


func _on_ball_drained(_drained: Ball) -> void:
	drained_count += 1
	ball_drained.emit()
	if respawn_delay >= 0.0:
		get_tree().create_timer(respawn_delay, true, true).timeout.connect(serve_ball)
