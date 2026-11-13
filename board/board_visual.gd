class_name BoardVisual
extends Node3D

@export var deck_color := Color(0.85, 0.32, 0.18)
@export var grip_color := Color(0.08, 0.08, 0.09)
@export var truck_color := Color(0.72, 0.74, 0.78)
@export var wheel_color := Color(0.95, 0.93, 0.85)

var deck_root := Node3D.new()
var _trucks: Array[Node3D] = []
var _wheels: Array[Node3D] = []


func _ready() -> void:
	deck_root.name = "Deck"
	add_child(deck_root)
	_build_deck()
	for i in 2:
		var truck := Node3D.new()
		truck.name = "Truck%d" % i
		add_child(truck)
		# Axle runs along the truck body's local Z (the wheel joint anchors).
		_add_box(truck, Vector3(0.028, 0.022, BoardSpec.HALF_TRACK_WIDTH * 2.0 - 0.03), Vector3.ZERO, truck_color)
		_trucks.append(truck)
	for i in 4:
		var wheel := Node3D.new()
		wheel.name = "Wheel%d" % i
		add_child(wheel)
		var mesh := CylinderMesh.new()
		mesh.top_radius = BoardSpec.WHEEL_RADIUS
		mesh.bottom_radius = BoardSpec.WHEEL_RADIUS
		mesh.height = 0.032
		mesh.radial_segments = 16
		var instance := MeshInstance3D.new()
		instance.mesh = mesh
		instance.material_override = _material(wheel_color)
		# Cylinder axis is Y; the wheel's spin axis is its local Z.
		instance.rotation = Vector3(PI * 0.5, 0.0, 0.0)
		wheel.add_child(instance)
		# A dark stripe makes the spin visible.
		_add_box(wheel, Vector3(0.006, BoardSpec.WHEEL_RADIUS * 2.02, 0.034), Vector3.ZERO, Color(0.3, 0.3, 0.32))
		_wheels.append(wheel)


func _build_deck() -> void:
	var length := BoardSpec.DECK_FLAT_LENGTH
	var width := BoardSpec.DECK_WIDTH
	var thickness := BoardSpec.DECK_THICKNESS
	_add_box(deck_root, Vector3(width, thickness, length), Vector3.ZERO, deck_color)
	_add_box(deck_root, Vector3(width - 0.01, 0.002, length), Vector3(0.0, thickness * 0.5 + 0.001, 0.0), grip_color)
	# Kicked nose (+Z) and tail (-Z).
	for end in [[1.0, BoardSpec.NOSE_KICK_DEGREES], [-1.0, BoardSpec.TAIL_KICK_DEGREES]]:
		var sign: float = end[0]
		var angle := deg_to_rad(end[1])
		var pivot := Node3D.new()
		pivot.position = Vector3(0.0, 0.0, sign * length * 0.5)
		pivot.rotation = Vector3(-sign * angle, 0.0, 0.0)
		deck_root.add_child(pivot)
		var tail_length := BoardSpec.DECK_TAIL_LENGTH
		_add_box(pivot, Vector3(width, thickness, tail_length), Vector3(0.0, 0.0, sign * tail_length * 0.5), deck_color)
		_add_box(pivot, Vector3(width - 0.01, 0.002, tail_length), Vector3(0.0, thickness * 0.5 + 0.001, sign * tail_length * 0.5), grip_color)


func _material(color: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = 0.6
	return m


func _add_box(parent: Node3D, size: Vector3, offset: Vector3, color: Color) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = offset
	instance.material_override = _material(color)
	parent.add_child(instance)
	return instance


## Copies body poses from the simulation (call once per physics tick).
func sync(board: BoardPhysics) -> void:
	deck_root.transform = board.body_transform(BoardSpec.Body.DECK)
	_trucks[0].transform = board.body_transform(BoardSpec.Body.FRONT_TRUCK)
	_trucks[1].transform = board.body_transform(BoardSpec.Body.BACK_TRUCK)
	for i in 4:
		_wheels[i].transform = board.body_transform(i)
