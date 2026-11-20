extends Node3D
## Physics sandbox: launch the ball with the plunger key, reset it with
## Backspace. Used to judge rolling, bouncing and tunneling by eye.

@export var launch_speed := 6.0
@export var launch_speed_variation := 2.0
@export var launch_spread_degrees := 25.0

@onready var _ball: Ball = $Ball
@onready var _spawn: Marker3D = $BallSpawn

var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_ball.reset_to(_spawn.global_transform)


func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("plunger"):
		launch()
	if Input.is_action_just_pressed("reset_ball"):
		_ball.reset_to(_spawn.global_transform)


func launch() -> void:
	_ball.reset_to(_spawn.global_transform)
	var angle := deg_to_rad(_rng.randf_range(-launch_spread_degrees, launch_spread_degrees))
	var speed := launch_speed + _rng.randf_range(-launch_speed_variation, launch_speed_variation)
	_ball.linear_velocity = Vector3(sin(angle), 0.0, -cos(angle)) * speed
