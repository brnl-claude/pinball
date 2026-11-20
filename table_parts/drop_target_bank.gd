class_name DropTargetBank
extends Node3D
## Groups DropTarget children. When all are down it awards a bonus and
## raises them again after a short delay.

signal scored(points: int)
signal completed

@export var completion_points := 1000
@export var reset_delay := 1.0

var targets: Array[DropTarget] = []


func _ready() -> void:
	for child in get_children():
		if child is DropTarget:
			targets.append(child)
			(child as DropTarget).dropped.connect(_on_target_dropped)


func all_down() -> bool:
	for target in targets:
		if not target.is_down:
			return false
	return true


func reset_targets() -> void:
	for target in targets:
		target.reset()
	SoundFx.play("bank_reset")


func _on_target_dropped(_target: DropTarget) -> void:
	if not all_down():
		return
	scored.emit(completion_points)
	completed.emit()
	get_tree().create_timer(reset_delay, true, true).timeout.connect(reset_targets)
