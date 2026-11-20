@tool
class_name BallSwitch
extends Area3D
## An invisible switch that fires when a ball passes through its box, like
## the gate or optical switch at a ramp exit.

signal scored(points: int)
signal activated(ball_switch: BallSwitch)

@export var size := Vector3(0.03, 0.03, 0.01)
@export var points := 0
## Sound to play when it fires (see Sfx), or empty for none.
@export var sound := ""

var hits := 0


func _ready() -> void:
	collision_layer = 0
	collision_mask = Ball.BALL_LAYER
	monitorable = false
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	add_child(shape_node)
	if not Engine.is_editor_hint():
		body_entered.connect(_on_body_entered)


func _on_body_entered(body: Node3D) -> void:
	if body is Ball:
		hits += 1
		if points > 0:
			scored.emit(points)
		activated.emit(self)
		if sound != "":
			SoundFx.play(sound)
