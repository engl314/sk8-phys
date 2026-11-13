class_name MotionFilters

## A rate- and acceleration-limited follower:
##   v += clamp(clamp(target - x, -Vmax, Vmax) - v, -Amax, Amax);  x += v
## Limits are per tick. This is where most of the "weight" in the motion comes from.
class Follower:
	var value := 0.0
	var velocity := 0.0
	var max_velocity := 0.05
	var max_acceleration := 0.006

	func _init(vmax := 0.05, amax := 0.006, initial := 0.0) -> void:
		max_velocity = vmax
		max_acceleration = amax
		value = initial

	func update(target: float) -> float:
		var wanted := clampf(target - value, -max_velocity, max_velocity)
		velocity += clampf(wanted - velocity, -max_acceleration, max_acceleration)
		value += velocity
		return value

	func reset(initial: float) -> void:
		value = initial
		velocity = 0.0


## Damped spring (semi-implicit).
class Spring:
	var value := 0.0
	var velocity := 0.0
	var stiffness := 60.0
	var damping := 6.0

	func _init(k := 60.0, c := 6.0) -> void:
		stiffness = k
		damping = c

	func update(target: float, dt: float) -> float:
		velocity += ((target - value) * stiffness - velocity * damping) * dt
		value += velocity * dt
		return value

	func kick(impulse: float) -> void:
		velocity += impulse

	## Keep the value in a range, stopping at the ends rather than bouncing.
	func limit(low: float, high: float) -> void:
		if value < low:
			value = low
			velocity = maxf(velocity, 0.0)
		elif value > high:
			value = high
			velocity = minf(velocity, 0.0)


class SpringVector:
	var value := Vector3.ZERO
	var velocity := Vector3.ZERO
	var stiffness := 120.0
	var damping := 14.0

	func _init(k := 120.0, c := 14.0) -> void:
		stiffness = k
		damping = c

	func update(target: Vector3, dt: float) -> Vector3:
		velocity += ((target - value) * stiffness - velocity * damping) * dt
		value += velocity * dt
		return value

	func reset(initial: Vector3) -> void:
		value = initial
		velocity = Vector3.ZERO


## Second-order follower set by how it should feel rather than by spring
## constants: `frequency` (Hz) is how fast it answers, `damping` below 1 lets it
## overshoot and settle, and `response` shapes the start: 0 eases in, above 0
## moves at once, below 0 goes the wrong way first (a body left behind before
## it catches up). Semi-implicit, with the stiffness term kept stable per tick.
class SecondOrder:
	var value := 0.0
	var velocity := 0.0
	var _k1 := 0.0
	var _k2 := 0.0
	var _k3 := 0.0
	var _previous := 0.0
	var _primed := false

	func _init(frequency := 2.0, damping := 1.0, response := 0.0, initial := 0.0) -> void:
		configure(frequency, damping, response)
		value = initial

	func configure(frequency: float, damping: float, response: float) -> void:
		var w := TAU * maxf(frequency, 0.01)
		_k1 = 2.0 * damping / w
		_k2 = 1.0 / (w * w)
		_k3 = response * damping / w

	func update(target: float, dt: float) -> float:
		if not _primed:
			_previous = target
			_primed = true
		var target_velocity := (target - _previous) / dt
		_previous = target
		var k2 := maxf(_k2, maxf(dt * dt * 0.5 + dt * _k1 * 0.5, dt * _k1))
		value += velocity * dt
		velocity += dt * (target + _k3 * target_velocity - value - _k1 * velocity) / k2
		return value

	func kick(impulse: float) -> void:
		velocity += impulse

	func reset(initial: float) -> void:
		value = initial
		velocity = 0.0
		_primed = false

	## Mirror the state (the frame it lives in turned half a turn).
	func flip() -> void:
		value = -value
		velocity = -velocity
		_previous = -_previous


## SecondOrder for a point in space: a foot or a hand swung to where it is going.
class SecondOrderVector:
	var value := Vector3.ZERO
	var velocity := Vector3.ZERO
	var _k1 := 0.0
	var _k2 := 0.0
	var _k3 := 0.0
	var _previous := Vector3.ZERO
	var _primed := false

	func _init(frequency := 2.0, damping := 1.0, response := 0.0) -> void:
		configure(frequency, damping, response)

	func configure(frequency: float, damping: float, response: float) -> void:
		var w := TAU * maxf(frequency, 0.01)
		_k1 = 2.0 * damping / w
		_k2 = 1.0 / (w * w)
		_k3 = response * damping / w

	func update(target: Vector3, dt: float) -> Vector3:
		if not _primed:
			_previous = target
			_primed = true
		var target_velocity := (target - _previous) / dt
		_previous = target
		var k2 := maxf(_k2, maxf(dt * dt * 0.5 + dt * _k1 * 0.5, dt * _k1))
		value += velocity * dt
		velocity += dt * (target + _k3 * target_velocity - value - _k1 * velocity) / k2
		return value

	## Put it somewhere, moving: what follows carries on from there.
	func place(at: Vector3, moving := Vector3.ZERO) -> void:
		value = at
		velocity = moving
		_previous = at
		_primed = true

	## The target is about to jump to somewhere new: head for it from here on,
	## without taking the jump itself for the target's speed.
	func retarget(target: Vector3) -> void:
		_previous = target
		_primed = true


## An orientation that follows its target like a mass on a spring: it lags when
## the target turns suddenly, swings through and settles. Damping acts on the
## difference from the target's own turn rate, so a steadily turning target is
## followed without trailing behind it. `torque` adds angular acceleration.
class SpringRotation:
	## Fastest target turn rate (rad/s) the damping follows; faster is a jump.
	const TARGET_RATE_LIMIT := 8.0

	var value := Quaternion.IDENTITY
	## Angular velocity (rad/s) in the space the orientations are in.
	var velocity := Vector3.ZERO
	var stiffness := 355.0
	var damping := 24.5
	var _previous := Quaternion.IDENTITY
	var _primed := false

	func _init(frequency := 3.0, ratio := 0.65) -> void:
		configure(frequency, ratio)

	func configure(frequency: float, ratio: float) -> void:
		var w := TAU * maxf(frequency, 0.01)
		stiffness = w * w
		damping = 2.0 * ratio * w

	func update(target: Quaternion, dt: float, torque := Vector3.ZERO) -> Quaternion:
		if not _primed:
			reset(target)
		var target_velocity := (rotation_vector(_previous, target) / dt).limit_length(TARGET_RATE_LIMIT)
		_previous = target
		var turn := velocity * dt
		var angle := turn.length()
		if angle > 1e-9:
			value = (Quaternion(turn / angle, angle) * value).normalized()
		var error := rotation_vector(value, target)
		velocity += (error * stiffness - (velocity - target_velocity) * damping + torque) * dt
		return value

	func kick(impulse: Vector3) -> void:
		velocity += impulse

	func reset(initial: Quaternion) -> void:
		value = initial
		velocity = Vector3.ZERO
		_previous = initial
		_primed = true

	## Forget the state: the next update starts at its target.
	func release() -> void:
		_primed = false

	func is_following() -> bool:
		return _primed

	## The turn (axis times angle) that takes `from` to `to` the short way.
	static func rotation_vector(from: Quaternion, to: Quaternion) -> Vector3:
		var delta := to * from.inverse()
		if delta.w < 0.0:
			delta = -delta
		var axis := Vector3(delta.x, delta.y, delta.z)
		var sine := axis.length()
		if sine < 1e-9:
			return Vector3.ZERO
		return axis / sine * (2.0 * atan2(sine, delta.w))
