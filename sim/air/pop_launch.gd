class_name PopLaunch

## Returns the launch velocity.
## `strength`: 0..1 flick strength. `com_height`: current COM height above the ground.
## `controls`: the steer (x right, y forward) for the small directional nudge.
static func launch_velocity(t: SkateTuning, velocity: Vector3, normal: Vector3, forward: Vector3,
		surface_speed: float, strength: float, com_height: float, controls: Vector2) -> Vector3:
	var planar := velocity - normal * velocity.dot(normal)
	var speed_fraction := clampf(surface_speed / t.pop_speed_range, 0.0, 1.0)
	var low := LinearCurve.evaluate(t.pop_weak_vs_speed, speed_fraction) * (t.pop_weak_height - t.pop_base_height) + t.pop_base_height
	var high := LinearCurve.evaluate(t.pop_strong_vs_speed, speed_fraction) * (t.pop_strong_height - t.pop_base_height) + t.pop_base_height
	var height := low * (1.0 - strength) + high * strength
	var remaining := maxf(height - com_height, 0.0)
	var speed := sqrt(2.0 * t.gravity * remaining)
	var slope := clampf(acos(clampf(normal.y, -1.0, 1.0)) * (2.0 / PI), 0.0, 1.0)
	var response := maxf(LinearCurve.evaluate(t.pop_vs_slope, slope), t.pop_slope_minimum)
	var launch := planar + normal * (speed * response)
	# Steering nudge, proportional to the pop along the normal.
	var projected := launch.dot(normal)
	var side := Vector3.UP.cross(forward)
	if side.length_squared() > 1e-8:
		side = side.normalized()
		var x := -(controls.x * t.pop_steer_sideways) * projected
		var z := (controls.y * t.pop_steer_forward) * projected
		launch += side * x + side.cross(Vector3.UP) * z
	return launch
