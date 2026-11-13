class_name RidingFrame
extends RefCounted

var dt := SimMath.DT
## -1 while the rider faces the deck's tail: the
## effective side and forward axes flip so "forward" is the rider's forward.
var facing_sign := 1.0
var deck_position := Vector3.ZERO
var deck_side := Vector3.RIGHT ## effective X
var deck_up := Vector3.UP ## deck Y
var deck_forward := Vector3.BACK ## effective Z
var deck_x := Vector3.RIGHT ## physical deck X
var deck_z := Vector3.BACK ## physical deck Z
var flat_forward := Vector3.BACK
var deck_up_no_pitch := Vector3.UP
var velocity := Vector3.ZERO
var ground_velocity := Vector3.ZERO
var angular_velocity := Vector3.ZERO
var ground_normal := Vector3.UP
var riding_up := Vector3.UP
var speed := 0.0 ## |velocity|
var surface_speed := 0.0 ## |ground velocity|
var forward_speed := 0.0 ## velocity . effective forward
var absolute_speed := 0.0
var total_mass := 11.56
var wheel_contacts := 0
var front_wheels_down := false
var back_wheels_down := false
var time_on_ground := 0.0


## Fill from the board, the processed ground normal and the filtered riding up.
func observe(board: BoardPhysics, normal: Vector3, filtered_up: Vector3, sign: float) -> void:
	var deck := board.deck()
	facing_sign = sign
	deck_position = deck.position
	deck_x = deck.basis.x
	deck_z = deck.basis.z
	deck_side = deck_x * sign
	deck_up = deck.basis.y
	deck_forward = deck_z * sign
	flat_forward = Vector3(deck_forward.x, 0.0, deck_forward.z)
	if flat_forward.length_squared() > 1e-5:
		flat_forward = flat_forward.normalized()
	var rejected := deck_up - flat_forward * deck_up.dot(flat_forward)
	deck_up_no_pitch = rejected.normalized() if rejected.length_squared() > 1e-12 else Vector3.UP
	velocity = deck.linear_velocity
	angular_velocity = deck.angular_velocity
	ground_normal = normal
	riding_up = filtered_up
	ground_velocity = velocity - filtered_up * velocity.dot(filtered_up)
	speed = velocity.length()
	surface_speed = ground_velocity.length()
	forward_speed = velocity.dot(deck_forward)
	absolute_speed = absf(forward_speed)
	var mass := 0.0
	for body in board.bodies:
		mass += 1.0 / body.inverse_mass
	total_mass = mass


## Filtered ground normal: snap when close, otherwise ease 10% per tick.
static func filter_normal(previous: Vector3, normal: Vector3) -> Vector3:
	if not (previous.dot(normal) <= 0.935):
		return normal
	var blended := previous * 0.9 + normal * 0.1
	return blended.normalized() if blended.length_squared() > 1e-12 else Vector3.ZERO
