class_name ConstraintRow
extends RefCounted

enum Kind { JOINT, DRIVE }
enum DriveType { NONE = 0, SOFT = 1, HARD = 2 }

var kind := Kind.JOINT
var a: SimBody
var b: SimBody
var arm_a := Vector3.ZERO
var arm_b := Vector3.ZERO
var inverse_mass_a := 0.0
var inverse_mass_b := 0.0
var inertia_a := SimMath.ZERO_BASIS
var inertia_b := SimMath.ZERO_BASIS

var lin_axis := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var ang_axis := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var lin_m := PackedFloat64Array([0.0, 0.0, 0.0])
var ang_m := PackedFloat64Array([0.0, 0.0, 0.0])
var lin_acc := PackedFloat64Array([0.0, 0.0, 0.0])
var ang_acc := PackedFloat64Array([0.0, 0.0, 0.0])
# Joint: preconditioned limit errors. Drive: target impulse and its +/- cap.
var lin_low := PackedFloat64Array([0.0, 0.0, 0.0])
var lin_high := PackedFloat64Array([0.0, 0.0, 0.0])
var ang_low := PackedFloat64Array([0.0, 0.0, 0.0])
var ang_high := PackedFloat64Array([0.0, 0.0, 0.0])
var lin_softness := 1.0
var ang_softness := 1.0


func _bind(body_a: SimBody, body_b: SimBody) -> void:
	a = body_a
	b = body_b
	inverse_mass_a = a.solver_inverse_mass()
	inverse_mass_b = b.solver_inverse_mass()
	inertia_a = a.solver_inverse_inertia()
	inertia_b = b.solver_inverse_inertia()


func _linear_inverse_effective_mass(axis: Vector3) -> float:
	var ja := arm_a.cross(axis)
	var jb := arm_b.cross(axis)
	return 1.0 / (ja.dot(inertia_a * ja) + jb.dot(inertia_b * jb) + inverse_mass_a + inverse_mass_b)


## Build a joint's rows. `joint` is a JointDefinition; body a is its body A.
static func build_joint(joint: JointDefinition, body_a: SimBody, body_b: SimBody) -> ConstraintRow:
	var row := ConstraintRow.new()
	row.kind = Kind.JOINT
	row._bind(body_a, body_b)
	var dt := SimMath.DT
	var world_a := SimMath.quaternion_product(body_a.q, joint.orientation_a)
	var world_b := SimMath.quaternion_product(body_b.q, joint.orientation_b)
	var world_linear := SimMath.quaternion_product(body_b.q, joint.linear_frame_b)
	var basis_a := SimMath.basis_from_quaternion(world_a)
	var basis_b := SimMath.basis_from_quaternion(world_b)
	var linear_basis := SimMath.basis_from_quaternion(world_linear)
	row.arm_a = body_a.basis * joint.anchor_a
	row.arm_b = body_b.basis * joint.anchor_b
	row.lin_axis = [linear_basis.x, linear_basis.y, linear_basis.z]
	var relative_rows := SimMath.relative_rotation_jacobian(world_a, world_b)
	var angular := _angular_limits(joint, basis_a, basis_b, relative_rows)
	row.ang_axis = angular[0]
	var raw_ang_low: Array = angular[1]
	var raw_ang_high: Array = angular[2]

	for i in 3:
		row.lin_m[i] = row._linear_inverse_effective_mass(row.lin_axis[i])
		var axis: Vector3 = row.ang_axis[i]
		# The extra 1/2 converts quaternion-component error to angle.
		row.ang_m[i] = 0.5 / (axis.dot(row.inertia_a * axis) + axis.dot(row.inertia_b * axis))

	var displacement_a := (body_a.force_acceleration + body_a.torque_acceleration.cross(row.arm_a)) * dt + body_a.point_velocity(row.arm_a)
	displacement_a *= dt
	var displacement_b := (body_b.force_acceleration + body_b.torque_acceleration.cross(row.arm_b)) * dt + body_b.point_velocity(row.arm_b)
	displacement_b *= dt
	var relative_displacement := displacement_b - displacement_a
	var predicted_separation := (body_b.position + row.arm_b + displacement_b) - (body_a.position + row.arm_a + displacement_a)
	var slack := joint.linear_slack
	var speed_limit := joint.linear_speed_limit
	for i in 3:
		var axis: Vector3 = row.lin_axis[i]
		var separation := predicted_separation.dot(axis)
		var rate := relative_displacement.dot(axis)
		var displacement_low := separation - slack[i]
		var displacement_high := separation + slack[i]
		var velocity_low := rate - speed_limit[i] * dt
		var velocity_high := rate + speed_limit[i] * dt
		row.lin_low[i] = maxf(displacement_low, minf(velocity_low, displacement_high)) * row.lin_m[i]
		row.lin_high[i] = minf(displacement_high, maxf(velocity_high, displacement_low)) * row.lin_m[i]

	var relative_angular_rate := (body_b.torque_acceleration * dt + (body_b.angular_velocity - body_a.angular_velocity)) - body_a.torque_acceleration * dt
	var angular_speed_limit := [joint.twist_speed_limit, joint.swing_speed_limit, joint.swing_speed_limit]
	for i in 3:
		var axis: Vector3 = row.ang_axis[i]
		var local := (relative_angular_rate * dt).dot(axis)
		var predicted_low: float = raw_ang_low[i] + local
		var predicted_high: float = raw_ang_high[i] + local
		var velocity_low: float = local - angular_speed_limit[i] * dt
		var velocity_high: float = angular_speed_limit[i] * dt + local
		row.ang_low[i] = maxf(predicted_low, minf(velocity_low, predicted_high)) * row.ang_m[i]
		row.ang_high[i] = minf(predicted_high, maxf(velocity_high, predicted_low)) * row.ang_m[i]
	return row


## Twist/swing axes and their raw limits.
static func _angular_limits(joint: JointDefinition, basis_a: Basis, basis_b: Basis, relative_rows: Array) -> Array:
	var axes := [basis_b.x, basis_b.y, basis_b.z]
	var low := [-SimMath.FLOAT_MAX, -SimMath.FLOAT_MAX, -SimMath.FLOAT_MAX]
	var high := [SimMath.FLOAT_MAX, SimMath.FLOAT_MAX, SimMath.FLOAT_MAX]
	var relative: Quaternion = relative_rows[3]
	var a_columns := [basis_a.x, basis_a.y, basis_a.z]
	var b_columns := [basis_b.x, basis_b.y, basis_b.z]
	# Relative basis: rel[row][column] = a.column(row) . b.column(column)
	var rel := []
	for r in 3:
		rel.append([a_columns[r].dot(b_columns[0]), a_columns[r].dot(b_columns[1]), a_columns[r].dot(b_columns[2])])

	match joint.swing_kind:
		JointDefinition.Swing.LOCKED:
			axes[1] = relative_rows[1]
			axes[2] = relative_rows[2]
			low[1] = 2.0 * relative.y
			high[1] = low[1]
			low[2] = 2.0 * relative.z
			high[2] = low[2]
		JointDefinition.Swing.CONE:
			if not (rel[0][0] >= 0.99999):
				var perpendicular_y: float = rel[0][1]
				var perpendicular_z: float = rel[0][2]
				var root := sqrt(perpendicular_y * perpendicular_y + perpendicular_z * perpendicular_z)
				var inverse_length := 1.0 / root
				axes[1] = basis_a.x.cross(basis_b.x) * inverse_length
				axes[2] = (axes[1] as Vector3).cross(basis_a.x)
				low[1] = (joint.swing_limit_cosine - rel[0][0]) * inverse_length
		JointDefinition.Swing.LIMITED_HINGE, JointDefinition.Swing.HINGE:
			axes[1] = basis_b.y
			if joint.twist_kind == JointDefinition.Twist.LOCKED:
				axes[2] = relative_rows[2]
				low[2] = 2.0 * relative.z
				high[2] = low[2]
			else:
				axes[2] = basis_a.x.cross(axes[1])
				low[2] = -rel[0][1]
				high[2] = low[2]
			if joint.swing_kind == JointDefinition.Swing.LIMITED_HINGE:
				var denominator: float = rel[0][2]
				if denominator != 0.0:
					var correction: float = (1.0 / denominator) * (joint.swing_limit_cosine - rel[0][0])
					if denominator < 0.0:
						high[1] = correction
					else:
						low[1] = correction
		_:
			axes[1] = basis_b.y
			axes[2] = basis_b.z

	match joint.twist_kind:
		JointDefinition.Twist.LOCKED:
			axes[0] = relative_rows[0]
			low[0] = 2.0 * relative.x
			high[0] = low[0]
		JointDefinition.Twist.LIMITED:
			axes[0] = basis_a.x
			var denominator: float = rel[2][1] - rel[1][2]
			if denominator != 0.0:
				var numerator: float = (1.0 + rel[0][0]) * joint.twist_limit_cosine - (rel[1][1] + rel[2][2])
				var correction := (1.0 / denominator) * numerator
				if denominator < 0.0:
					high[0] = correction
				else:
					low[0] = correction
		_:
			axes[0] = basis_b.x
	return [axes, low, high]


## Build a drive's rows. Frame A rides on body_a, frame B on body_b; the linear
## error is frame B minus frame A. `dynamics` is [linear, angular], each
## {"spring": spring or max velocity, "damping", "strength", "type"}.
static func build_drive(body_a: SimBody, body_b: SimBody,
		frame_a_q: Quaternion, frame_a_t: Vector3, frame_b_q: Quaternion, frame_b_t: Vector3,
		dynamics: Array) -> ConstraintRow:
	var row := ConstraintRow.new()
	row.kind = Kind.DRIVE
	row._bind(body_a, body_b)
	var dt := SimMath.DT
	row.arm_a = body_a.basis * frame_a_t
	row.arm_b = body_b.basis * frame_b_t
	var world_a_q := SimMath.quaternion_product(body_a.q, frame_a_q)
	var world_b_q := SimMath.quaternion_product(body_b.q, frame_b_q)
	var linear_basis := SimMath.basis_from_quaternion(world_b_q)
	row.lin_axis = [linear_basis.x, linear_basis.y, linear_basis.z]

	var raw := SimMath.relative_rotation_jacobian(world_a_q, world_b_q)
	var relative: Quaternion = raw[3]
	var components := [relative.x, relative.y, relative.z]
	var singular := false
	var inverse_lengths := [1.0, 1.0, 1.0]
	for i in 3:
		var squared := clampf(components[i] * components[i], 0.0, 1.0)
		if squared == 1.0:
			singular = true
		inverse_lengths[i] = squared
	for i in 3:
		inverse_lengths[i] = 1.0 if singular else 1.0 / sqrt(1.0 - inverse_lengths[i])
	var angular_position_error := [0.0, 0.0, 0.0]
	for i in 3:
		var axis: Vector3 = row.lin_axis[i] if singular else raw[i]
		row.ang_axis[i] = axis * inverse_lengths[i]
		angular_position_error[i] = components[i] * inverse_lengths[i] * 2.0

	var linear_position_error := (body_b.position + row.arm_b) - (body_a.position + row.arm_a)
	var linear_velocity_displacement := body_b.point_velocity(row.arm_b) * dt - body_a.point_velocity(row.arm_a) * dt
	var linear_acceleration_displacement := (body_b.force_acceleration + body_b.torque_acceleration.cross(row.arm_b)) * dt * dt \
		- (body_a.force_acceleration + body_a.torque_acceleration.cross(row.arm_a)) * dt * dt
	var angular_velocity_displacement := (body_b.angular_velocity - body_a.angular_velocity) * dt
	var angular_acceleration_displacement := (body_b.torque_acceleration - body_a.torque_acceleration) * dt * dt

	for i in 3:
		row.lin_m[i] = 1.0 / row._drive_linear_effective_mass(row.lin_axis[i])
		var axis: Vector3 = row.ang_axis[i]
		var denominator := 0.0
		if body_a.active:
			denominator += axis.dot(row.inertia_a * axis)
		if body_b.active:
			denominator += axis.dot(row.inertia_b * axis)
		row.ang_m[i] = 1.0 / denominator

	var linear := _drive_terms(dynamics[0],
		[linear_position_error.x, linear_position_error.y, linear_position_error.z],
		[linear_velocity_displacement.x, linear_velocity_displacement.y, linear_velocity_displacement.z],
		[linear_acceleration_displacement.x, linear_acceleration_displacement.y, linear_acceleration_displacement.z])
	var target: Array = linear.target
	var linear_target := Vector3(target[0], target[1], target[2])
	var ang_vel := []
	var ang_accel := []
	for i in 3:
		ang_vel.append(angular_velocity_displacement.dot(row.ang_axis[i]))
		ang_accel.append(angular_acceleration_displacement.dot(row.ang_axis[i]))
	var angular := _drive_terms(dynamics[1], angular_position_error, ang_vel, ang_accel)
	row.lin_softness = linear.softness
	row.ang_softness = angular.softness
	for i in 3:
		row.lin_low[i] = linear_target.dot(row.lin_axis[i]) * row.lin_m[i]
		row.lin_high[i] = row.lin_m[i] * linear.strength
		row.ang_low[i] = angular.target[i] * row.ang_m[i]
		row.ang_high[i] = row.ang_m[i] * angular.strength
	return row


func _drive_linear_effective_mass(axis: Vector3) -> float:
	var denominator := 0.0
	if a.active:
		var ja := arm_a.cross(axis)
		denominator += a.inverse_mass + ja.dot(inertia_a * ja)
	if b.active:
		var jb := arm_b.cross(axis)
		denominator += b.inverse_mass + jb.dot(inertia_b * jb)
	return denominator


## The row's solve coefficients.
static func _drive_terms(params: Dictionary, position_error: Array, velocity_displacement: Array, acceleration_displacement: Array) -> Dictionary:
	var dt := SimMath.DT
	var damping: float = dt * params.damping
	var position_weight: float
	var velocity_weight: float
	var acceleration_weight: float
	if params.type == DriveType.SOFT:
		var spring: float = (dt * params.spring) * dt
		var inverse := 1.0 / ((1.0 + spring) + damping)
		position_weight = inverse * spring
		velocity_weight = inverse * damping
		acceleration_weight = inverse * (spring + damping)
	else:
		position_weight = 1.0 / (1.0 + damping)
		velocity_weight = 1.0
		acceleration_weight = 1.0
	var error := position_error.duplicate()
	if params.type == DriveType.HARD:
		var squared: float = error[0] * error[0] + error[1] * error[1] + error[2] * error[2]
		var maximum: float = dt * params.spring
		if squared > maximum * maximum:
			var factor := maximum / sqrt(squared)
			for i in 3:
				error[i] *= factor
	var target := [0.0, 0.0, 0.0]
	for i in 3:
		target[i] = acceleration_displacement[i] * acceleration_weight + (error[i] * position_weight + velocity_displacement[i] * velocity_weight)
	return {"softness": acceleration_weight, "target": target, "strength": (dt * params.strength) * dt}


## One solver pass of this row.
func solve() -> void:
	var relative_point := (b.correction_linear + b.correction_angular.cross(arm_b)) - (a.correction_linear + a.correction_angular.cross(arm_a))
	var relative_angular := b.correction_angular - a.correction_angular
	var dl0: float
	var dl1: float
	var dl2: float
	var da0: float
	var da1: float
	var da2: float
	if kind == Kind.JOINT:
		dl0 = _joint_limit(lin_acc[0] + lin_m[0] * relative_point.dot(lin_axis[0]), lin_low[0], lin_high[0]) - lin_acc[0]
		dl1 = _joint_limit(lin_acc[1] + lin_m[1] * relative_point.dot(lin_axis[1]), lin_low[1], lin_high[1]) - lin_acc[1]
		dl2 = _joint_limit(lin_acc[2] + lin_m[2] * relative_point.dot(lin_axis[2]), lin_low[2], lin_high[2]) - lin_acc[2]
		da0 = _joint_limit(ang_acc[0] + ang_m[0] * relative_angular.dot(ang_axis[0]), ang_low[0], ang_high[0]) - ang_acc[0]
		da1 = _joint_limit(ang_acc[1] + ang_m[1] * relative_angular.dot(ang_axis[1]), ang_low[1], ang_high[1]) - ang_acc[1]
		da2 = _joint_limit(ang_acc[2] + ang_m[2] * relative_angular.dot(ang_axis[2]), ang_low[2], ang_high[2]) - ang_acc[2]
	else:
		dl0 = clampf((lin_acc[0] + lin_m[0] * relative_point.dot(lin_axis[0])) * lin_softness + lin_low[0], -lin_high[0], lin_high[0]) - lin_acc[0]
		dl1 = clampf((lin_acc[1] + lin_m[1] * relative_point.dot(lin_axis[1])) * lin_softness + lin_low[1], -lin_high[1], lin_high[1]) - lin_acc[1]
		dl2 = clampf((lin_acc[2] + lin_m[2] * relative_point.dot(lin_axis[2])) * lin_softness + lin_low[2], -lin_high[2], lin_high[2]) - lin_acc[2]
		da0 = clampf((ang_acc[0] + ang_m[0] * relative_angular.dot(ang_axis[0])) * ang_softness + ang_low[0], -ang_high[0], ang_high[0]) - ang_acc[0]
		da1 = clampf((ang_acc[1] + ang_m[1] * relative_angular.dot(ang_axis[1])) * ang_softness + ang_low[1], -ang_high[1], ang_high[1]) - ang_acc[1]
		da2 = clampf((ang_acc[2] + ang_m[2] * relative_angular.dot(ang_axis[2])) * ang_softness + ang_low[2], -ang_high[2], ang_high[2]) - ang_acc[2]
	lin_acc[0] += dl0
	lin_acc[1] += dl1
	lin_acc[2] += dl2
	ang_acc[0] += da0
	ang_acc[1] += da1
	ang_acc[2] += da2
	var linear_impulse: Vector3 = lin_axis[0] * dl0 + lin_axis[1] * dl1 + lin_axis[2] * dl2
	var angular_impulse: Vector3 = ang_axis[0] * da0 + ang_axis[1] * da1 + ang_axis[2] * da2
	a.correction_linear += linear_impulse * inverse_mass_a
	b.correction_linear -= linear_impulse * inverse_mass_b
	a.correction_angular += inertia_a * (arm_a.cross(linear_impulse) + angular_impulse)
	b.correction_angular -= inertia_b * (arm_b.cross(linear_impulse) + angular_impulse)


## Two-sided limit projection: zero inside the permitted interval.
static func _joint_limit(candidate: float, low: float, high: float) -> float:
	var high_error := high + candidate
	var low_error := low + candidate
	return (low_error if low_error > 0.0 else 0.0) + (high_error if high_error < 0.0 else 0.0)
