class_name BoardPhysics
extends RefCounted

const Body = BoardSpec.Body

var bodies: Array[SimBody] = []
## Separate kinematic target the deck can be driven toward (the guide drive).
var guide := SimBody.new()
## The static world's slot for solver corrections (never integrated).
var world := SimBody.new()
var gravity := Vector3(0.0, -9.8, 0.0)
var iterations := 50
## Height offset added to every queued force point.
var queued_force_height := 0.0
## Guide drive dynamics [linear, angular]; disabled (zero strength) by default.
var guide_dynamics := [
	{"spring": 0.0, "damping": 0.0, "strength": 0.0, "type": ConstraintRow.DriveType.HARD},
	{"spring": 0.0, "damping": 0.0, "strength": 0.0, "type": ConstraintRow.DriveType.HARD},
]
## Guide drive frames: deck-side frame relative to the deck (frame B).
var guide_frame_q := Quaternion.IDENTITY

var _joint_definitions: Array[JointDefinition]
var _truck_pivots: Array[Transform3D]
var _truck_drive: Array
var _default_poses: Array[Transform3D]
## Queued deck forces: [force_world, point_body]. Cleared by the owner.
var forces: Array = []

# Rows from the last step, kept for contact reports and debugging.
var contacts: Array[ContactRow] = []
var joints: Array[ConstraintRow] = []
var drives: Array[ConstraintRow] = []
var last_step_usec := 0


func _init() -> void:
	_joint_definitions = BoardSpec.joint_definitions()
	_truck_pivots = BoardSpec.truck_pivot_frames()
	_truck_drive = BoardSpec.truck_steering_drive()
	_default_poses = BoardSpec.default_part_poses()
	for i in BoardSpec.BODY_COUNT:
		var body := SimBody.new()
		body.name = BoardSpec.BODY_NAMES[i]
		body.set_mass_properties(BoardSpec.mass_properties(i))
		bodies.append(body)
	guide.name = "guide"
	guide.active = false
	world.name = "world"
	world.active = false


func deck() -> SimBody:
	return bodies[Body.DECK]


## Place the deck at `deck_transform`, move
## every other part by the same rigid delta and clear all rates.
##
## The default part poses do not satisfy the truck joints (the front
## truck starts 90 degrees off its frame), so the first solve snaps the trucks
## and kicks the board. With `settled` the parts start from the pose the joints
## settle to instead.
func spawn(deck_transform: Transform3D, settled := false) -> void:
	var placed := deck_transform.orthonormalized()
	var parts := settled_parts() if settled else _default_poses
	for i in BoardSpec.BODY_COUNT:
		var part := placed * parts[i]
		var body := bodies[i]
		body.set_pose(part.basis.orthonormalized(), part.origin)
		body.linear_velocity = Vector3.ZERO
		body.angular_velocity = Vector3.ZERO
		body.force_acceleration = gravity
		body.torque_acceleration = Vector3.ZERO
		body.clear_corrections()
	guide.set_pose(placed.basis, placed.origin)
	forces.clear()
	contacts.clear()


static var _settled_parts: Array[Transform3D] = []


## Part poses in deck space after the joints and truck drives settle with no
## gravity or contacts. Computed once from the default poses.
static func settled_parts() -> Array[Transform3D]:
	if not _settled_parts.is_empty():
		return _settled_parts
	var scratch := BoardPhysics.new()
	scratch.gravity = Vector3.ZERO
	scratch.spawn(Transform3D.IDENTITY)
	var none: Array[BoardContact] = []
	for _i in 120:
		scratch.step(none, Vector2.ZERO)
		for body in scratch.bodies:
			body.linear_velocity = Vector3.ZERO
			body.angular_velocity = Vector3.ZERO
	var inverse_deck := scratch.deck().transform().affine_inverse()
	for body in scratch.bodies:
		var local := inverse_deck * body.transform()
		_settled_parts.append(Transform3D(local.basis.orthonormalized(), local.origin))
	return _settled_parts


## Move the assembly, keeping its rates.
func set_transform(deck_transform: Transform3D) -> void:
	var delta := deck_transform.orthonormalized() * deck().transform().affine_inverse()
	for body in bodies:
		var moved := delta * body.transform()
		body.set_pose(moved.basis.orthonormalized(), moved.origin)


func set_velocity(linear: Vector3, angular := Vector3.ZERO) -> void:
	for body in bodies:
		body.linear_velocity = linear
		body.angular_velocity = angular


func queue_force(force_world: Vector3, point_body: Vector3) -> void:
	forces.append([force_world, point_body])


func clear_forces() -> void:
	forces.clear()


## Guide target pose in world space.
func set_guide_transform(target: Transform3D) -> void:
	guide.set_pose(target.basis.orthonormalized(), target.origin)


## Advance the board one 1/60 s tick. `truck_targets` are the two trucks'
## steering angles in radians.
func step(collisions: Array[BoardContact], truck_targets: Vector2) -> void:
	var start := Time.get_ticks_usec()
	var deck_body := deck()
	for entry in forces:
		deck_body.add_point_force(entry[0], entry[1] + Vector3(0.0, queued_force_height, 0.0))

	contacts.clear()
	for c in collisions:
		var body_b := world if c.body_b < 0 else bodies[c.body_b]
		contacts.append(ContactRow.build(c, bodies[c.body_a], body_b))

	joints.clear()
	for joint in _joint_definitions:
		joints.append(ConstraintRow.build_joint(joint, bodies[joint.body_a], bodies[joint.body_b]))

	# Truck drive frames: the front drive follows the front base rotated by
	# target[1]; the back drive follows the back base rotated by -target[0].
	drives.clear()
	var front := _truck_pivots[1]
	var back := _truck_pivots[0]
	var front_q := SimMath.normalize_q(SimMath.quaternion_from_basis(front.basis * SimMath.rotation_x(truck_targets.y)))
	var back_q := SimMath.normalize_q(SimMath.quaternion_from_basis(back.basis * SimMath.rotation_x(-truck_targets.x)))
	drives.append(ConstraintRow.build_drive(bodies[Body.FRONT_TRUCK], deck_body,
		Quaternion.IDENTITY, Vector3.ZERO, front_q, front.origin, _truck_drive))
	drives.append(ConstraintRow.build_drive(bodies[Body.BACK_TRUCK], deck_body,
		Quaternion.IDENTITY, Vector3.ZERO, back_q, back.origin, _truck_drive))
	if _guide_enabled():
		drives.append(ConstraintRow.build_drive(guide, deck_body,
			Quaternion.IDENTITY, Vector3.ZERO, guide_frame_q, Vector3.ZERO, guide_dynamics))

	for _i in iterations:
		for row in contacts:
			row.solve()
		for row in joints:
			row.solve()
		for row in drives:
			row.solve()

	for body in bodies:
		if body.active:
			body.integrate(gravity)
		else:
			body.clear_corrections()
	guide.clear_corrections()
	world.clear_corrections()
	last_step_usec = Time.get_ticks_usec() - start


## A drive with zero strength on both halves clamps every impulse to zero.
func _guide_enabled() -> bool:
	return guide_dynamics[0].strength > 0.0 or guide_dynamics[1].strength > 0.0


## Wheels whose contact rows pushed this tick.
func wheel_contact_count() -> int:
	var touching := {}
	for row in contacts:
		if row.collision.body_a <= Body.LEFT_BACK_WHEEL and row.acc0 > 0.0:
			touching[row.collision.body_a] = true
	return touching.size()


## Live part transforms for presentation and collision queries.
func body_transform(index: int) -> Transform3D:
	return bodies[index].transform()


func speed() -> float:
	return deck().linear_velocity.length()
