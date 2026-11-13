@tool
class_name GrindRail
extends Node3D

@export var start := Vector3.ZERO
@export var end := Vector3.ZERO
@export var width := 0.1
@export var thickness := 0.1


func _ready() -> void:
	add_to_group("grind_rails")


func direction() -> Vector3:
	return (end - start).normalized()


func length() -> float:
	return start.distance_to(end)
