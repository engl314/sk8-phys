class_name CameraFollower
extends RefCounted

var target := 0.0
var position := 0.0
var velocity := 0.0
var acceleration := 0.0

var near_band := 0.0
var far_band := 1.0
var speed_limit := 1e9
var far_acceleration := 1e9
var near_acceleration := 1e9
var far_smoothing := 0.0
var near_smoothing := 0.0
var stop_on_overshoot := false
## Angles wrap to (-PI, PI].
var angular := false


func configure(near_range: float, far_range: float, max_speed: float, far_accel: float, near_accel: float, smoothing := 0.0) -> CameraFollower:
	near_band = near_range
	far_band = far_range
	speed_limit = max_speed
	far_acceleration = far_accel
	near_acceleration = near_accel
	far_smoothing = smoothing
	near_smoothing = smoothing
	return self


func reset(value: float) -> void:
	target = value
	position = value
	velocity = 0.0
	acceleration = 0.0


func update(dt: float, goal: float) -> float:
	var delta := goal - position
	if angular:
		delta = wrapf(delta, -PI, PI)
		goal = position + delta
	target = goal
	if stop_on_overshoot and velocity * delta < 0.0:
		velocity = 0.0
	acceleration = (delta / dt - velocity) / dt
	var absolute_delta := absf(delta)
	var fraction := 0.0
	if absolute_delta < near_band:
		fraction = 1.0
	elif absolute_delta < far_band:
		fraction = 1.0 - (absolute_delta - near_band) / (far_band - near_band)
	if acceleration * delta > 0.0:
		var limit := lerpf(far_acceleration, near_acceleration, fraction)
		if absf(acceleration) > limit:
			acceleration = signf(acceleration) * limit
	velocity += acceleration * dt
	if absf(velocity) > speed_limit:
		velocity = signf(velocity) * speed_limit
	var next := position + velocity * dt
	var smoothing := lerpf(far_smoothing, near_smoothing, fraction)
	position += (next - position) * (1.0 - smoothing)
	if angular:
		position = wrapf(position, -PI, PI)
	return position
