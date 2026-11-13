class_name BoardSpec

enum Body { RIGHT_FRONT_WHEEL, LEFT_FRONT_WHEEL, RIGHT_BACK_WHEEL, LEFT_BACK_WHEEL, FRONT_TRUCK, BACK_TRUCK, DECK }
const BODY_COUNT := 7
const BODY_NAMES := ["wheel_rf", "wheel_lf", "wheel_rb", "wheel_lb", "truck_front", "truck_back", "deck"]
const WHEELS := [0, 1, 2, 3]

const WHEEL_RADIUS := 0.031
const HALF_TRACK_WIDTH := 0.095
const AXLE_HEIGHT := -0.0565
const TRUCK_FROM_FLAT_END := -0.052
const DECK_FLAT_LENGTH := 0.59
const TRUCK_PIVOT_ANGLE_DEGREES := 31.0
## Deck centre height that puts the wheel spheres on level ground.
const LEVEL_GROUND_DECK_HEIGHT := WHEEL_RADIUS - AXLE_HEIGHT

# Truck and wheel joint settings.
const TRUCK_MAX_TURN_RATE_DEGREES := 86.1
const TRUCK_MAX_TURN_DEGREES := 14.0
const WHEEL_MAX_SPIN_RATE_DEGREES := 1000000.0

# Deck shape, used for visuals and deck collision.
const DECK_WIDTH := 0.24
const DECK_THICKNESS := 0.015
const DECK_TAIL_LENGTH := 0.165
const NOSE_KICK_DEGREES := 13.0
const TAIL_KICK_DEGREES := 12.5

const MASS_PROPERTIES := {
	"wheel": {"local_inverse_inertia": Vector3(6268.571, 6268.571, 6268.571), "inverse_mass": 1.0 / 0.415,
		"scalar_inertia": 1.59526e-4, "max_linear": SimMath.FLOAT_MAX, "max_angular": SimMath.FLOAT_MAX,
		"linear_drag": 0.0, "angular_drag": 0.0},
	"truck": {"local_inverse_inertia": Vector3(285.8012, 285.8012, 18470.771), "inverse_mass": 1.0 / 1.95,
		"scalar_inertia": 3.4989356e-3, "max_linear": SimMath.FLOAT_MAX, "max_angular": SimMath.FLOAT_MAX,
		"linear_drag": 0.0, "angular_drag": 0.0},
	# The deck loses 45% of its spin each tick.
	"deck": {"local_inverse_inertia": Vector3(1.9265224, 1.841312, 37.752766), "inverse_mass": 1.0 / 6.0,
		"scalar_inertia": 0.543091, "max_linear": SimMath.FLOAT_MAX, "max_angular": SimMath.FLOAT_MAX,
		"linear_drag": 0.0, "angular_drag": 0.45 * SimMath.FREQUENCY},
}


static func mass_properties(body: int) -> Dictionary:
	if body <= Body.LEFT_BACK_WHEEL:
		return MASS_PROPERTIES.wheel
	if body <= Body.BACK_TRUCK:
		return MASS_PROPERTIES.truck
	return MASS_PROPERTIES.deck


static func front_truck_z() -> float:
	return DECK_FLAT_LENGTH * 0.5 + TRUCK_FROM_FLAT_END


## Default part poses in board space, body order 0..6.
static func default_part_poses() -> Array[Transform3D]:
	var front_z := front_truck_z()
	var back_z := -front_z
	var y := AXLE_HEIGHT
	var x := HALF_TRACK_WIDTH
	var out: Array[Transform3D] = [
		Transform3D(Basis.IDENTITY, Vector3(-x, y, front_z)),
		Transform3D(Basis.IDENTITY, Vector3(x, y, front_z)),
		Transform3D(Basis.IDENTITY, Vector3(-x, y, back_z)),
		Transform3D(Basis.IDENTITY, Vector3(x, y, back_z)),
		Transform3D(Basis.IDENTITY, Vector3(0.0, y, front_z)),
		Transform3D(SimMath.rotation_y(PI * 0.5), Vector3(0.0, y, back_z)),
		Transform3D.IDENTITY,
	]
	return out


## The trucks' base transforms: [back, front].
static func truck_pivot_frames() -> Array[Transform3D]:
	var alpha := deg_to_rad(TRUCK_PIVOT_ANGLE_DEGREES)
	var front_z := front_truck_z()
	var out: Array[Transform3D] = [
		Transform3D(SimMath.rotation_x(alpha) * SimMath.rotation_y(PI * 0.5), Vector3(0.0, AXLE_HEIGHT, -front_z)),
		Transform3D(SimMath.rotation_x(-alpha) * SimMath.rotation_y(-PI * 0.5), Vector3(0.0, AXLE_HEIGHT, front_z)),
	]
	return out


## The truck drives: no linear drive,
## a hard angular drive capped at 10 rad per tick and strength 11 * 3600.
static func truck_steering_drive() -> Array:
	return [
		{"spring": 0.0, "damping": 0.0, "strength": 0.0, "type": ConstraintRow.DriveType.NONE},
		{"spring": 10.0 * SimMath.FREQUENCY, "damping": 0.0, "strength": 11.0 * SimMath.FREQUENCY * SimMath.FREQUENCY, "type": ConstraintRow.DriveType.HARD},
	]


## The board's joints: two deck/truck joints then four truck/wheel joints.
static func joint_definitions() -> Array[JointDefinition]:
	var bases := truck_pivot_frames()
	var frequency := SimMath.FREQUENCY
	var truck_turn_rate := deg_to_rad(TRUCK_MAX_TURN_RATE_DEGREES) * frequency
	var truck_turn_cosine := cos(deg_to_rad(TRUCK_MAX_TURN_DEGREES))
	var wheel_spin_rate := deg_to_rad(WHEEL_MAX_SPIN_RATE_DEGREES) * frequency
	var wheel_orientation := SimMath.quaternion_from_basis(SimMath.rotation_x(PI * 0.5))
	var out: Array[JointDefinition] = []
	# Deck/truck: the front joint uses the front base (index 1).
	for pair in [[Body.FRONT_TRUCK, bases[1]], [Body.BACK_TRUCK, bases[0]]]:
		var r := JointDefinition.new()
		r.body_a = pair[0]
		r.body_b = Body.DECK
		r.twist_speed_limit = truck_turn_rate
		r.swing_limit_cosine = 1.0
		r.twist_limit_cosine = truck_turn_cosine
		r.swing_kind = JointDefinition.Swing.LOCKED
		r.twist_kind = JointDefinition.Twist.LIMITED
		var base: Transform3D = pair[1]
		r.orientation_b = SimMath.quaternion_from_basis(base.basis)
		r.anchor_b = base.origin
		r.linear_frame_b = r.orientation_b
		out.append(r)
	for wheel in [[Body.RIGHT_FRONT_WHEEL, Body.FRONT_TRUCK, 1.0], [Body.LEFT_FRONT_WHEEL, Body.FRONT_TRUCK, -1.0],
			[Body.RIGHT_BACK_WHEEL, Body.BACK_TRUCK, 1.0], [Body.LEFT_BACK_WHEEL, Body.BACK_TRUCK, -1.0]]:
		var r := JointDefinition.new()
		r.body_a = wheel[0]
		r.body_b = wheel[1]
		r.swing_speed_limit = wheel_spin_rate
		r.swing_limit_cosine = 1.0
		r.twist_limit_cosine = 1.0
		r.swing_kind = JointDefinition.Swing.HINGE
		r.twist_kind = JointDefinition.Twist.LOCKED
		r.orientation_a = wheel_orientation
		r.orientation_b = wheel_orientation
		r.anchor_b = Vector3(0.0, 0.0, HALF_TRACK_WIDTH * wheel[2])
		r.linear_frame_b = wheel_orientation
		out.append(r)
	return out
