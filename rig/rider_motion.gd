class_name RiderMotion
extends RefCounted

## Accelerations beyond this (m/s^2) are impacts, handled as impulses instead.
const ACCELERATION_LIMIT := 25.0
const YAW_ACCELERATION_LIMIT := 70.0

## World velocity and low-passed acceleration of the board.
var velocity := Vector3.ZERO
var acceleration := Vector3.ZERO
## The same in the rig frame (+Z the nose, +Y up, +X the board's left).
var local_velocity := Vector3.ZERO
var local_acceleration := Vector3.ZERO
## The force per unit mass through the feet, rig frame: 1 g straight up when
## rolling on the flat, tipped in a turn, more in a compression, none in the air.
var felt := Vector3(0.0, 9.8, 0.0)
## 1 while something holds the rider up (wheels down, or on a rail), easing to 0 in the air.
var loaded := 1.0
## The board's own acceleration along the rig's up: what the legs must absorb.
var heave := 0.0
## The board's acceleration the body has to be carried through (rig frame):
## its acceleration less free fall, which moves board and rider together.
var jolt := Vector3.ZERO
## Speed along the ground plane of the rig and the direction of travel in it.
var speed := 0.0
var travel := Vector3.BACK
## Turn rate of the rider's frame about its up (rad/s, positive to the left) and its change.
var yaw_rate := 0.0
var yaw_acceleration := 0.0
## Speed into the ground on the tick before a landing, as the simulation reads it
## (the wheels have already met the ground by then, so it is small).
var impact_speed := 0.0
## How fast the rider was really coming down: the most over the last few ticks.
var landing_speed := 0.0
var supported := true
var gravity := 9.8

var _previous_velocity := Vector3.ZERO
var _recent: Array[Vector3] = []
var _previous_yaw_rate := 0.0
var _primed := false
var _skip := false


func reset() -> void:
	_primed = false
	_recent.clear()


## The board's velocity was just set by hand (a pop, a launch): don't read it as a jolt.
func skip() -> void:
	_skip = true


func update(game: RiderInputs, dt: float) -> void:
	var frame := game.frame
	var to_rig := frame.basis.transposed()
	gravity = game.gravity
	velocity = game.velocity
	supported = game.grounded() or game.state == RiderInputs.State.GRIND
	var turning: float = game.spin_rate if game.airborne \
		else game.angular_velocity.dot(frame.basis.y)
	if not _primed:
		_previous_velocity = velocity
		_previous_yaw_rate = turning
		acceleration = Vector3.ZERO if supported else Vector3.DOWN * gravity
		yaw_acceleration = 0.0
		loaded = 1.0 if supported else 0.0
		_primed = true
	impact_speed = maxf(-_previous_velocity.dot(game.ground_normal), 0.0)
	landing_speed = 0.0
	for recent in _recent:
		landing_speed = maxf(landing_speed, -recent.dot(game.ground_normal))
	_recent.append(velocity)
	if _recent.size() > 5:
		_recent.pop_front()
	if _skip:
		_previous_velocity = velocity
		_skip = false
	var raw := ((velocity - _previous_velocity) / dt).limit_length(ACCELERATION_LIMIT)
	acceleration = acceleration.lerp(raw, 0.35)
	_previous_velocity = velocity
	local_velocity = to_rig * velocity
	local_acceleration = to_rig * acceleration
	felt = local_acceleration + to_rig * Vector3.UP * gravity
	heave = local_acceleration.y
	loaded = move_toward(loaded, 1.0 if supported else 0.0, dt * 8.0)
	jolt = local_acceleration + to_rig * Vector3.UP * gravity * (1.0 - loaded)
	speed = Vector2(local_velocity.x, local_velocity.z).length()
	travel = Vector3(local_velocity.x, 0.0, local_velocity.z).normalized() if speed > 0.4 \
		else Vector3.BACK * signf(game.forward_speed + 1e-3)
	var raw_yaw := clampf((turning - _previous_yaw_rate) / dt, -YAW_ACCELERATION_LIMIT, YAW_ACCELERATION_LIMIT)
	yaw_acceleration = lerpf(yaw_acceleration, raw_yaw, 0.4)
	_previous_yaw_rate = turning
	yaw_rate = turning
