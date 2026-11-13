class_name SimBody
extends RefCounted

var name := ""
## The body is simulated and responds to impulses.
var active := true

var q := Quaternion.IDENTITY
var basis := Basis.IDENTITY
var position := Vector3.ZERO
var linear_velocity := Vector3.ZERO
var angular_velocity := Vector3.ZERO
## Already divided by mass / passed through inverse inertia.
var force_acceleration := Vector3.ZERO
var torque_acceleration := Vector3.ZERO

var local_inverse_inertia := Vector3.ZERO
var inverse_mass := 0.0
var scalar_inertia := 0.0
var maximum_linear_velocity := SimMath.FLOAT_MAX
var maximum_angular_velocity := SimMath.FLOAT_MAX
## Drag: the share of velocity lost each tick, times the tick rate (so a drag
## of FREQUENCY stops the body dead).
var linear_drag := 0.0
var angular_drag := 0.0
var world_inverse_inertia := SimMath.ZERO_BASIS
var kinetic_energy := 0.0

# The four corrections the solver accumulates.
# Linear/angular displacements produce velocity; position/orientation only move.
var correction_linear := Vector3.ZERO
var correction_position := Vector3.ZERO
var correction_angular := Vector3.ZERO
var correction_orientation := Vector3.ZERO


func set_mass_properties(properties: Dictionary) -> void:
	local_inverse_inertia = properties.local_inverse_inertia
	inverse_mass = properties.inverse_mass
	scalar_inertia = properties.scalar_inertia
	maximum_linear_velocity = properties.max_linear
	maximum_angular_velocity = properties.max_angular
	linear_drag = properties.linear_drag
	angular_drag = properties.angular_drag


func set_pose(new_basis: Basis, new_position: Vector3) -> void:
	q = SimMath.quaternion_from_basis(new_basis)
	basis = SimMath.basis_from_quaternion(q)
	position = new_position
	world_inverse_inertia = SimMath.world_inverse_inertia(basis, local_inverse_inertia)


func transform() -> Transform3D:
	return Transform3D(basis, position)


## Inverse mass seen by constraint builders (zero when not simulated).
func solver_inverse_mass() -> float:
	return inverse_mass if active else 0.0


func solver_inverse_inertia() -> Basis:
	return world_inverse_inertia if active else SimMath.ZERO_BASIS


func clear_corrections() -> void:
	correction_linear = Vector3.ZERO
	correction_position = Vector3.ZERO
	correction_angular = Vector3.ZERO
	correction_orientation = Vector3.ZERO


## Velocity at a world-space arm from the body's centre of mass.
func point_velocity(arm: Vector3) -> Vector3:
	return linear_velocity + angular_velocity.cross(arm)


## Integrate with the solver's displacement corrections.
## Velocity is rebuilt from the total displacement, so solver corrections become motion.
func integrate(gravity: Vector3) -> void:
	var dt := SimMath.DT
	var linear := (force_acceleration * dt + linear_velocity) * dt + correction_linear
	var angular := (torque_acceleration * dt + angular_velocity) * dt + correction_angular
	position += correction_position + linear
	q = SimMath.integrate_orientation(q, angular + correction_orientation)
	basis = SimMath.basis_from_quaternion(q)
	world_inverse_inertia = SimMath.world_inverse_inertia(basis, local_inverse_inertia)
	angular_velocity = SimMath.clamp_length(angular * maxf(SimMath.FREQUENCY - angular_drag, 0.0), maximum_angular_velocity)
	linear_velocity = SimMath.clamp_length(linear * maxf(SimMath.FREQUENCY - linear_drag, 0.0), maximum_linear_velocity)
	kinetic_energy = linear_velocity.length_squared() + scalar_inertia * inverse_mass * angular_velocity.length_squared()
	clear_corrections()
	force_acceleration = gravity
	torque_acceleration = Vector3.ZERO


## World force at a body-local point.
func add_point_force(force_world: Vector3, point_body: Vector3) -> void:
	force_acceleration += force_world * inverse_mass
	var arm := basis * point_body
	torque_acceleration += world_inverse_inertia * arm.cross(force_world)
