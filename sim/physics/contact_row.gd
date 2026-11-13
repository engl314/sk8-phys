class_name ContactRow
extends RefCounted

## Below this the board is not sliding across the contact: any tangent will do.
const TANGENT_MINIMUM_SQUARED := 1.1754943508222875e-38

var a: SimBody
var b: SimBody
var arm_a := Vector3.ZERO
var arm_b := Vector3.ZERO
var normal := Vector3.UP
var tangent_0 := Vector3.ZERO
var tangent_1 := Vector3.ZERO
var inverse_mass_a := 0.0
var inverse_mass_b := 0.0
# Angular response I^-1 (arm x axis) per axis, for each body.
var response_a := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var response_b := [Vector3.ZERO, Vector3.ZERO, Vector3.ZERO]
var m0 := 0.0
var m1 := 0.0
var m2 := 0.0
var static_friction := 0.0
var dynamic_friction := 0.0
## Accumulated impulses: normal, tangent 0, tangent 1, position-only normal.
var acc0 := 0.0
var acc1 := 0.0
var acc2 := 0.0
var acc3 := 0.0
var target0 := 0.0
var target1 := 0.0
var target2 := 0.0
var target3 := 0.0
## Source collision, for contact reports (board body index, surface).
var collision: BoardContact


## Build the contact rows for one narrow-phase result.
static func build(c: BoardContact, body_a: SimBody, body_b: SimBody) -> ContactRow:
	var row := ContactRow.new()
	row.collision = c
	row.a = body_a
	row.b = body_b
	var dt := SimMath.DT
	row.arm_a = c.position_on_a - body_a.position
	row.arm_b = c.position_on_b - body_b.position
	var relative_velocity := body_b.point_velocity(row.arm_b) - body_a.point_velocity(row.arm_a)

	row.normal = c.normal
	var t := relative_velocity.cross(c.normal)
	var t_squared := t.length_squared()
	if t_squared < TANGENT_MINIMUM_SQUARED:
		var n := c.normal
		if 0.5 - n.x * n.x >= 0.0:
			t = Vector3(1.0 - n.x * n.x, -n.y * n.x, -n.z * n.x)
			t_squared = t.x
		else:
			t = -Vector3(-n.x * n.z, -n.y * n.z, 1.0 - n.z * n.z)
			t_squared = 1.0 - n.z * n.z
	var inverse_length := 1.0 / sqrt(t_squared)
	row.tangent_0 = t * inverse_length
	row.tangent_1 = c.normal.cross(t) * inverse_length
	row.static_friction = c.static_friction
	row.dynamic_friction = c.dynamic_friction

	row.inverse_mass_a = body_a.solver_inverse_mass()
	row.inverse_mass_b = body_b.solver_inverse_mass()
	var inertia_a := body_a.solver_inverse_inertia()
	var inertia_b := body_b.solver_inverse_inertia()
	var axes: Array[Vector3] = [row.normal, row.tangent_0, row.tangent_1]
	var m := PackedFloat64Array([0.0, 0.0, 0.0])
	for i in 3:
		var ja := row.arm_a.cross(axes[i])
		var jb := row.arm_b.cross(axes[i])
		var response_a := inertia_a * ja
		var response_b := inertia_b * jb
		row.response_a[i] = response_a
		row.response_b[i] = response_b
		m[i] = 1.0 / (ja.dot(response_a) + jb.dot(response_b) + row.inverse_mass_a + row.inverse_mass_b)
	row.m0 = m[0]
	row.m1 = m[1]
	row.m2 = m[2]

	var acceleration_a := Vector3.ZERO
	var acceleration_b := Vector3.ZERO
	if body_a.active:
		acceleration_a = body_a.force_acceleration + body_a.torque_acceleration.cross(row.arm_a)
	if body_b.active:
		acceleration_b = body_b.force_acceleration + body_b.torque_acceleration.cross(row.arm_b)
	var separation_vector := c.position_on_b - c.position_on_a
	var predicted := relative_velocity * dt + (separation_vector + (acceleration_b - acceleration_a) * (dt * dt))
	var separation := separation_vector.dot(row.normal) * m[0]
	var restitution := (relative_velocity * -(dt * c.restitution)).dot(row.normal) * m[0]
	var predicted_0 := predicted.dot(row.normal) * m[0]
	var normal_adjustment := 0.0 if restitution >= 0.0 else separation + restitution
	if separation >= 0.0:
		normal_adjustment = restitution
	if 0.0 >= predicted_0:
		normal_adjustment = 0.0
	row.target0 = predicted_0 - normal_adjustment
	row.target1 = predicted.dot(row.tangent_0) * m[1]
	row.target2 = predicted.dot(row.tangent_1) * m[2]
	row.target3 = separation
	return row


## One contact pass. Friction is bounded by the normal impulse from
## before this pass; crossing the static bound clamps to the dynamic bound.
func solve() -> void:
	var position_error := (b.correction_position + b.correction_orientation.cross(arm_b)) - (a.correction_position + a.correction_orientation.cross(arm_a))
	var total_error := (b.correction_linear + b.correction_angular.cross(arm_b)) - (a.correction_linear + a.correction_angular.cross(arm_a)) + position_error
	var normal_impulse := acc0
	var c0 := acc0 + target0 + m0 * total_error.dot(normal)
	var c1 := acc1 + target1 + m1 * total_error.dot(tangent_0)
	var c2 := acc2 + target2 + m2 * total_error.dot(tangent_1)
	var c3 := acc3 + target3 + m0 * position_error.dot(normal)
	var next0 := maxf(c0, 0.0)
	var next3 := maxf(c3, 0.0)
	var static_bound := static_friction * normal_impulse
	var dynamic_bound := dynamic_friction * normal_impulse
	var next1 := c1 if c1 >= -static_bound else -dynamic_bound
	if not (static_bound >= c1):
		next1 = dynamic_bound
	var next2 := c2 if c2 >= -static_bound else -dynamic_bound
	if not (static_bound >= c2):
		next2 = dynamic_bound
	var d0 := next0 - acc0
	var d1 := next1 - acc1
	var d2 := next2 - acc2
	var d3 := next3 - acc3
	acc0 = next0
	acc1 = next1
	acc2 = next2
	acc3 = next3
	var linear := normal * d0 + tangent_0 * d1 + tangent_1 * d2
	var positional := normal * d3
	var angular_a: Vector3 = response_a[0] * d0 + response_a[1] * d1 + response_a[2] * d2
	var angular_b: Vector3 = response_b[0] * d0 + response_b[1] * d1 + response_b[2] * d2
	a.correction_angular += angular_a
	a.correction_orientation += response_a[0] * d3
	a.correction_linear += linear * inverse_mass_a
	a.correction_position += positional * inverse_mass_a
	b.correction_angular -= angular_b
	b.correction_orientation -= response_b[0] * d3
	b.correction_linear -= linear * inverse_mass_b
	b.correction_position -= positional * inverse_mass_b


## Normal force this tick, as contact feedback reports it (impulse * 60 * 60).
func normal_force_magnitude() -> float:
	return acc0 * SimMath.FREQUENCY * SimMath.FREQUENCY
