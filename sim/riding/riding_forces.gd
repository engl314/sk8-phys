class_name RidingForces

const NORMAL_MINIMUM := 1e-6
## Seconds a truck takes to ease to the deck's tilt once its wheels touch.
const TRUCK_EASE_TIME := 0.165


static func _normalize_safe(v: Vector3) -> Vector3:
	var length := v.length()
	return v / length if length > NORMAL_MINIMUM else Vector3.ZERO


## Rolling force. `state` holds
## "target_speed" and "reset". The board is driven toward a target speed that
## follows the measured speed within a bound, eased by friction and gravity.
static func rolling_force(state: Dictionary, t: SkateTuning, f: RidingFrame,
		enabled: bool, balance: float, time_without_input: float) -> Vector3:
	var speed := absf(f.forward_speed)
	var dt := f.dt
	var bound := t.rolling_target_slack
	var lower := maxf(speed - bound, 0.0)
	var target: float
	if state.reset:
		state.reset = false
		target = speed
	else:
		target = clampf(state.target_speed, lower, bound + speed)
	var projected := f.deck_forward * f.ground_velocity.dot(f.deck_forward)
	var tangent := _normalize_safe(projected - f.ground_normal * projected.dot(f.ground_normal))
	var gravity := clampf(-tangent.y * t.slope_gravity, -t.slope_max_acceleration, t.slope_max_acceleration) * dt
	var friction := -LinearCurve.evaluate(t.rolling_resistance, f.surface_speed) * dt
	var surface_delta: float
	if gravity > 0.0:
		surface_delta = friction + gravity
	else:
		surface_delta = minf(friction, gravity)
	target += surface_delta
	if time_without_input > t.idle_friction_delay:
		target -= LinearCurve.evaluate(t.idle_friction, f.surface_speed) * dt
	if balance != 0.0:
		target -= LinearCurve.evaluate(t.manual_friction, f.surface_speed) * dt
	state.target_speed = maxf(target, 0.0)
	var error := clampf(state.target_speed - speed, -bound, bound)
	var gain := 0.0
	if enabled and f.wheel_contacts >= 2:
		gain = t.rolling_gain_down if error < 0.0 else t.rolling_gain_up
	var scalar := f.total_mass * gain * error / dt
	var axis := f.deck_forward if f.deck_forward.dot(tangent) > 0.0 else -f.deck_forward
	return axis * scalar


## Steer angle: truck angle request from the turn input.
## `state` keeps "push_steer_scale" and "damped_turn" between ticks.
static func steer_angle(state: Dictionary, t: SkateTuning, turn: float, sharp_turn: float,
		absolute_speed: float, control_scalar: float, balance: float, pushing: bool) -> float:
	var sharp_scalar := absf(sharp_turn) * t.steer_sharp_turn_boost + 1.0
	if sharp_turn != 0.0:
		turn = 1.0 if turn >= 0.0 else -1.0
	turn = (1.0 - t.steer_input_blend) * state.damped_turn + t.steer_input_blend * turn
	state.damped_turn = turn
	var speed_scalar := LinearCurve.evaluate(t.steer_vs_speed, clampf(absolute_speed / t.steer_speed_range, 0.0, 1.0))
	var input_scalar := LinearCurve.evaluate(t.steer_response, absf(turn))
	var next: float = state.push_steer_scale - t.steer_push_loss if pushing else state.push_steer_scale + t.steer_push_recovery
	state.push_steer_scale = clampf(next, t.steer_push_minimum, 1.0)
	var manual := t.steer_in_manual if balance != 0.0 else 1.0
	return control_scalar * t.steer_truck_angle * manual * state.push_steer_scale * input_scalar * speed_scalar * sharp_scalar * turn


## Truck angles. Each truck eases to the deck tilt over
## TRUCK_EASE_TIME while its wheels touch; off the ground it holds a frame, then decays.
## `state`: "deck_tilt", "targets" (Vector2), "timers" (Vector2). `active` is
## [back truck, front truck].
static func ease_truck_angles(state: Dictionary, tilt: float, blend: float, active: Array) -> void:
	state.deck_tilt = (1.0 - blend) * state.deck_tilt + blend * tilt
	var targets: Vector2 = state.targets
	var timers: Vector2 = state.timers
	for i in 2:
		if active[i]:
			if timers[i] <= TRUCK_EASE_TIME:
				timers[i] += SimMath.DT
				var fraction := clampf(timers[i] / TRUCK_EASE_TIME, 0.0, 1.0)
				targets[i] = (1.0 - fraction) * targets[i] + fraction * state.deck_tilt
			else:
				targets[i] = state.deck_tilt
		else:
			if timers[i] == 0.0:
				targets[i] *= 0.983
			timers[i] = 0.0
	state.targets = targets
	state.timers = timers


## Side grip: the wheels' sideways grip.
static func side_grip(t: SkateTuning, f: RidingFrame, grip_time: float) -> Vector3:
	var y := clampf(f.ground_normal.y, -1.0, 1.0)
	var angle := clampf(acos(y) * (2.0 / PI), 0.0, 1.0)
	var angle_response := 1.0 - LinearCurve.evaluate(t.grip_loss_vs_slope, angle)
	var speed_response := 1.0 - LinearCurve.evaluate(t.grip_loss_vs_speed, f.surface_speed * 0.1)
	var time := LinearCurve.evaluate(t.grip_ramp, clampf(grip_time, 0.0, t.grip_ramp_time) / t.grip_ramp_time)
	var blend := (1.0 - t.grip_soft_wheels) * t.wheel_hardness + t.grip_soft_wheels
	var response := maxf(angle_response, speed_response)
	var scalar := -(time * blend * response * t.grip_strength)
	var tangent := f.velocity - f.ground_normal * f.velocity.dot(f.ground_normal)
	return f.deck_side * (tangent.dot(f.deck_side) * scalar)


## Line-up torque: yaw that lines the deck up with
## its velocity. Returned as a requested angular displacement.
static func line_up_torque(t: SkateTuning, f: RidingFrame, grip_time: float, turn: float) -> Vector3:
	var limit := ((1.0 - t.line_up_ramp_soft_wheels) * t.wheel_hardness + t.line_up_ramp_soft_wheels) * t.grip_ramp_time
	var strength := LinearCurve.evaluate(t.line_up_ramp, clampf(grip_time, 0.0, limit) / limit) * t.line_up_strength
	var forward := -f.deck_forward if f.deck_forward.dot(f.velocity) < 0.0 else f.deck_forward
	var error := forward.cross(f.velocity).dot(f.ground_normal)
	var output := f.ground_normal * (error * strength)
	if turn * error < 0.0:
		output *= 1.0 - clampf(absf(turn), 0.0, t.line_up_steer_cutoff) / t.line_up_steer_cutoff
	return output


## Turn torque: the direct turn request, or the
## fall-line assist on slopes, whichever wins. `state` holds the manual turn filter.
static func turn_torque(t: SkateTuning, f: RidingFrame, state: Dictionary, turn: float, balance: float, manual_turn: float) -> Vector3:
	if balance != 0.0 and manual_turn != 0.0:
		var wrong := (f.back_wheels_down and balance < 0.0) or (f.front_wheels_down and balance > 0.0)
		var spin := manual_turn * t.manual_turn_wrong_wheels if wrong else manual_turn
		var goal := deg_to_rad(LinearCurve.evaluate(t.manual_turn_rate, f.speed))
		state.manual_turn_filtered = (1.0 - t.manual_turn_blend) * state.manual_turn_filtered + goal * t.manual_turn_blend
		return f.ground_normal * (f.dt * state.manual_turn_filtered * spin)
	state.manual_turn_filtered = 0.0
	# Ground frame: up = riding up, forward = deck forward flattened onto it.
	var up := f.riding_up
	var forward := _normalize_safe(f.deck_forward - up * f.deck_forward.dot(up))
	if forward == Vector3.ZERO:
		forward = Vector3.BACK
	var frame := Basis(up.cross(forward), up, forward)
	var inverse := frame.transposed()
	var world_up_local := inverse * Vector3.UP
	var angle := acos(clampf(world_up_local.y, -1.0, 1.0)) * (2.0 / PI)
	if angle > 1.2:
		angle = 0.0
	var downhill := Vector3(-world_up_local.x, 0.0, -world_up_local.z)
	downhill = _normalize_safe(downhill) * LinearCurve.evaluate(t.fall_line_vs_slope, angle)
	var velocity := inverse * (f.deck_forward * f.forward_speed)
	velocity.y = 0.0
	var cross_y := velocity.z * downhill.x - velocity.x * downhill.z
	var speed := clampf(f.absolute_speed, 0.0, t.fall_line_speed_range)
	var heading_scalar := cross_y * t.fall_line_strength * LinearCurve.evaluate(t.fall_line_vs_speed, speed / t.fall_line_speed_range)
	var opposing := maxf(f.angular_velocity.dot(f.ground_normal) * -turn, 0.0)
	var turn_scalar := LinearCurve.evaluate(t.turn_against_spin, opposing) * LinearCurve.evaluate(t.turn_vs_speed, f.absolute_speed) * t.turn_strength * turn
	var scalar := heading_scalar if not (heading_scalar * turn_scalar < 0.0) and not (absf(turn_scalar) > absf(heading_scalar)) else turn_scalar
	return f.ground_normal * scalar


## Levelling torque: restoring pitch/roll toward the riding plane,
## returned as a plain angular displacement.
static func level_torque(t: SkateTuning, f: RidingFrame, balance: float, braking_override: bool) -> Vector3:
	if braking_override:
		return Vector3.ZERO
	var up := f.riding_up
	var forward_axis := f.deck_z
	var side_axis := f.deck_x
	var a := _normalize_safe(forward_axis - up * up.dot(forward_axis))
	var b := _normalize_safe(side_axis - up * up.dot(side_axis))
	var sign_a := 1.0 if side_axis.dot(forward_axis.cross(a)) >= 0.0 else -1.0
	var sign_b := 1.0 if forward_axis.dot(side_axis.cross(b)) >= 0.0 else -1.0
	var b_strength := LinearCurve.evaluate(t.level_roll_vs_angle, _plane_angle(side_axis, b)) * sign_b
	var a_strength := LinearCurve.evaluate(t.level_pitch_vs_angle, _plane_angle(forward_axis, a)) * sign_a * (1.0 if balance == 0.0 else 0.0)
	return side_axis * a_strength + forward_axis * b_strength


static func _plane_angle(axis: Vector3, projected: Vector3) -> float:
	return acos(clampf(axis.dot(projected), 0.0, 1.0)) * (2.0 / PI)


## The rider's weight through one foot.
## Returns [force_world, point_body].
static func foot_weight(t: SkateTuning, f: RidingFrame, application_z: float, absorption: float, foot_share: float, balance: float) -> Array:
	var fraction := clampf(f.time_on_ground / t.landing_weight_time, 0.0, 1.0)
	var zero_scalar := 1.0 if f.time_on_ground != 0.0 or balance != 0.0 else 0.0
	var speed := f.surface_speed * 0.125 * t.riding_weight
	var remainder := (1.0 - fraction) * t.landing_weight * zero_scalar
	var magnitude := -(speed * fraction + remainder) * foot_share
	var force := f.riding_up * magnitude - f.deck_up_no_pitch * absorption
	var direction := _normalize_safe(f.velocity)
	force -= direction * direction.dot(force)
	return [force, Vector3(0.0, 0.0, application_z)]


## Which foot carries weight in a manual.
static func weight_split(balance: float) -> Vector2:
	var front := (1.0 if balance >= 0.0 else 2.0) if balance <= 0.0 else 0.0
	var back := (1.0 if balance <= 0.0 else 2.0) if balance >= 0.0 else 0.0
	return Vector2(front, back)


## Push acceleration.
static func push_force(t: SkateTuning, f: RidingFrame, target_speed: float) -> Vector3:
	var speed_change := maxf(target_speed - f.forward_speed, 0.0)
	var fraction := clampf(f.forward_speed / t.push_top_speed, 0.0, 1.0)
	var limit := (1.0 - fraction) * t.push_cap_standstill + fraction * t.push_cap_top_speed
	speed_change = clampf(speed_change, -limit, limit)
	if f.absolute_speed + speed_change > t.push_top_speed:
		speed_change = maxf(t.push_top_speed - f.absolute_speed, 0.0)
	return f.deck_forward * (f.total_mass * speed_change / f.dt)


## Braking. `input` is the foot brake amount (0..1).
static func braking_force(t: SkateTuning, f: RidingFrame, input: float, tail_brake: bool) -> Vector3:
	var amount := input * t.foot_brake_force
	if tail_brake:
		amount = t.tail_brake_force
	amount *= 1.0 if f.forward_speed < 0.0 else -1.0
	if f.absolute_speed < t.brake_cutoff_speed:
		amount = 0.0
	return f.flat_forward * amount


## Stopping drag: a held brake at a crawl stops the board dead.
static func stop_drag(t: SkateTuning, f: RidingFrame, braking_active: bool, balance: float) -> float:
	if f.absolute_speed < t.brake_hold_speed * 2.0 and braking_active and balance == 0.0:
		return 1.0
	return 0.0


## Manual pitch: pitch the deck to the manual
## target with an accumulating PID; returns the angular displacement to apply.
## `state`: elapsed, measured, filtered, correction. `contact_ok`: the wheels on
## the ground are the ones the manual balances on.
static func manual_pitch(state: Dictionary, t: SkateTuning, f: RidingFrame, balance: float, noise_time: float, contact_ok: bool, other_contact: bool) -> Vector3:
	if balance == 0.0:
		state.elapsed = 0.0
		state.measured = 0.0
		state.filtered = 0.0
		state.correction = 0.0
		return Vector3.ZERO
	var sign := 1.0 if balance > 0.0 else -1.0
	var signed_target := (absf(balance) * 0.75 + 0.25) * sign
	var noise := sin(noise_time * t.manual_wobble_rate * TAU) * deg_to_rad(t.manual_wobble_degrees)
	var target := deg_to_rad(t.manual_tilt_degrees) * signed_target + noise * LinearCurve.evaluate(t.manual_wobble_vs_speed, f.absolute_speed)
	if absf(balance) > t.manual_brake_threshold:
		target = deg_to_rad(t.manual_brake_degrees) * sign
	var started: bool = state.elapsed > 0.0
	if not started:
		state.correction = t.manual_start_kick * target
	# Nose-up pitch of the deck against the riding plane.
	var forward := f.deck_forward
	var up := f.riding_up
	var measured := asin(clampf(forward.dot(up), -1.0, 1.0))
	var change: float = measured - state.measured
	state.measured = measured
	var error := clampf(target - measured, -deg_to_rad(t.manual_error_limit_degrees), deg_to_rad(t.manual_error_limit_degrees))
	state.filtered = state.filtered * 0.95 + error * 0.05
	var derivative := clampf(change * t.manual_derivative if started else 0.0, -t.manual_derivative_limit, t.manual_derivative_limit)
	var scale := 1.0
	if not contact_ok:
		var wheel_scale := 0.5 if other_contact else 1.0
		state.correction = t.manual_off_wheels_bleed * state.correction * wheel_scale
		scale = t.manual_off_wheels_scale * wheel_scale
	else:
		state.correction = state.correction + derivative + state.filtered * t.manual_integral + error * t.manual_proportional
	state.elapsed += f.dt
	# Raising the nose is a negative turn about the deck's side axis.
	var side := up.cross(forward).normalized() if up.cross(forward).length_squared() > 1e-8 else f.deck_side
	return -side * (state.correction * scale)


## Drift correction:
## a constant -0.605 N m torque about the deck's local Y on every grounded tick.
## It offsets the board assembly's slight yaw drift.
static func drift_correction(deck: SimBody) -> void:
	deck.torque_acceleration += deck.world_inverse_inertia * (deck.basis * Vector3(0.0, -0.605, 0.0))


## Request an angular displacement, minus what the deck's current
## spin already supplies along that axis (never reversing it).
static func request_rotation(deck: SimBody, requested: Vector3) -> void:
	var direction := _normalize_safe(requested)
	var existing := direction * direction.dot(deck.angular_velocity * SimMath.DT)
	var remainder := requested - existing
	if remainder.dot(requested) < 0.0:
		remainder = Vector3.ZERO
	var selected := requested if existing.dot(requested) < 0.0 else remainder
	apply_rotation(deck, selected)


## Add the angular acceleration that yields `displacement` next tick.
static func apply_rotation(deck: SimBody, displacement: Vector3) -> void:
	deck.torque_acceleration += displacement / (SimMath.DT * SimMath.DT)


## Powerslide yaw: turn the deck to
## `slide` half-turns across the direction of travel.
static func powerslide_yaw(t: SkateTuning, f: RidingFrame, slide: float, elapsed: float) -> Vector3:
	var remap := LinearCurve.evaluate(t.slide_angle_response, absf(slide))
	var age := clampf(elapsed - 0.5, 0.0, 1.0)
	var weight := LinearCurve.evaluate(t.slide_response_vs_speed, f.surface_speed) * age
	var signed := remap if slide >= 0.0 else -remap
	var angle := (slide * PI) * (1.0 - weight) + (signed * PI) * weight
	var velocity := _normalize_safe(f.velocity)
	var side := _normalize_safe(f.ground_normal.cross(velocity))
	var desired := velocity * cos(angle) + side * sin(angle)
	var error := f.deck_forward.cross(desired)
	if f.deck_forward.dot(desired) < 0.0:
		error = -f.ground_normal if error.y < 0.0 else f.ground_normal
	var strength := ((1.0 - t.slide_yaw_soft_wheels) * t.wheel_hardness + t.slide_yaw_soft_wheels) * t.slide_yaw_spring
	var displacement := (error * strength + f.angular_velocity * t.slide_yaw_damping) * t.slide_yaw_scale
	return f.ground_normal * displacement.dot(f.ground_normal)


## Powerslide drag. Returns [force_world, point_body].
static func powerslide_drag(t: SkateTuning, f: RidingFrame) -> Array:
	var tangent := f.velocity - f.ground_normal * f.velocity.dot(f.ground_normal)
	var lateral := f.deck_side * tangent.dot(f.deck_side)
	var response := LinearCurve.evaluate(t.slide_drag, f.absolute_speed)
	var hardness := t.wheel_hardness if response > 0.0 else 1.0
	var strength := ((1.0 - t.slide_drag_soft_wheels) * hardness + t.slide_drag_soft_wheels) * response
	var side := _normalize_safe(f.ground_normal.cross(f.velocity))
	var scaled := lateral * strength
	var longitudinal := scaled - side * side.dot(scaled)
	var angle := 0.0
	var forward_flat := f.deck_forward - f.ground_normal * f.deck_forward.dot(f.ground_normal)
	if f.velocity.length_squared() * f.deck_forward.length_squared() > 1.5e-5 and forward_flat.length_squared() > 1e-10 and tangent.length_squared() > 1e-10:
		angle = tangent.signed_angle_to(forward_flat, f.ground_normal)
	var degrees := rad_to_deg(wrapf(angle, -PI, PI))
	var sign := 1.0 if degrees > 0.0 else -1.0
	var angular := side * LinearCurve.evaluate(t.slide_side_drag_vs_angle, absf(degrees)) * LinearCurve.evaluate(t.slide_side_drag_vs_speed, f.surface_speed)
	var force := angular * sign + longitudinal
	var y := -t.slide_drag_height if force.dot(f.velocity) < 0.0 else t.slide_drag_height
	return [force, Vector3(0.0, y, 0.0)]
