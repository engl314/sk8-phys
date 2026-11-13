class_name RidingModel
extends RefCounted

enum State { GROUND, SLIDE, AIR, GRIND, BAIL }
## HANG: gliding with the leg behind between pushes at speed.
enum PushPhase { NONE, REACH, DRIVE, SWING, HANG }

## Pushing, braking or pumping harder than this restarts the rolling speed target.
const ROLLING_RESET_FORCE_SQUARED := 1.5e-5

var tuning: SkateTuning
var frame := RidingFrame.new()
var state := State.AIR
var state_timer := 0.0
## Seconds since the wheels last landed and the grip/line-up clock.
var time_on_ground := 0.0
var grip_time := 0.0
var time_without_input := 0.0
## -1 while the rider faces the deck's tail.
var facing_sign := 1.0
var filtered_normal := Vector3.UP
var ground_normal := Vector3.UP

var rolling_state := {"target_speed": 0.0, "reset": true}
var steer_state := {"push_steer_scale": 1.0, "damped_turn": 0.0}
var truck_state := {"deck_tilt": 0.0, "targets": Vector2.ZERO, "timers": Vector2.ZERO}
var turn_state := {"manual_turn_filtered": 0.0}
var manual_state := {"elapsed": 0.0, "measured": 0.0, "filtered": 0.0, "correction": 0.0}
## Seconds the current manual has been held (0 when not manualling).
var manual_time := 0.0
var _noise_time := 0.0
var truck_targets := Vector2.ZERO

var push_phase := PushPhase.NONE
var push_timer := 0.0
var push_target := 0.0
## How long this push's glide before the next lasts (s).
var push_hang := 0.0
var push_buffered_until := -1.0
## Another push is wanted after this one (W held or buffered), for the animation.
var push_again := false
var push_count := 0

var slide_value := 0.0
var slide_side := 1.0
var slide_elapsed := 0.0

var pump_state := {"valid": false, "height": 0.0, "smoothed": 0.0, "time": 0.0, "angular": 0.0, "normal": Vector3.UP}
## Speed change from the last pump (m/s per tick), for debugging.
var pump_acceleration := 0.0

var wheels_down := [false, false, false, false]
var colliding := false
var just_landed := false
var _clock := 0.0


func _init(skate_tuning: SkateTuning) -> void:
	tuning = skate_tuning


func reset() -> void:
	state = State.AIR
	state_timer = 0.0
	time_on_ground = 0.0
	grip_time = 0.0
	rolling_state = {"target_speed": 0.0, "reset": true}
	steer_state = {"push_steer_scale": 1.0, "damped_turn": 0.0}
	truck_state = {"deck_tilt": 0.0, "targets": Vector2.ZERO, "timers": Vector2.ZERO}
	turn_state = {"manual_turn_filtered": 0.0}
	truck_targets = Vector2.ZERO
	push_phase = PushPhase.NONE
	slide_value = 0.0
	filtered_normal = Vector3.UP
	ground_normal = Vector3.UP
	facing_sign = 1.0


## Ride the board the other way round: its tail becomes the nose. A push in
## progress is dropped (it was pushing the old way); a held W starts a new one.
func switch_direction() -> void:
	facing_sign *= -1.0
	push_phase = PushPhase.NONE
	push_timer = 0.0


func is_grounded() -> bool:
	return state == State.GROUND or state == State.SLIDE


func is_pushing() -> bool:
	return push_phase != PushPhase.NONE


## 0..1 progress through the current push phase, for the rider's foot.
func push_progress() -> float:
	match push_phase:
		PushPhase.REACH:
			return push_timer / tuning.push_reach_time
		PushPhase.DRIVE:
			return push_timer / tuning.push_drive_time
		PushPhase.SWING:
			return push_timer / tuning.push_swing_time
		PushPhase.HANG:
			return push_timer / maxf(push_hang, SimMath.DT)
	return 0.0


## Reads the previous solve's contacts: which wheels pushed and the ground normal.
func observe_contacts(board: BoardPhysics) -> void:
	wheels_down = [false, false, false, false]
	colliding = false
	var normal_sum := Vector3.ZERO
	for row in board.contacts:
		if row.acc0 <= 0.0:
			continue
		colliding = true
		var body := row.collision.body_a
		if body <= BoardSpec.Body.LEFT_BACK_WHEEL:
			wheels_down[body] = true
			normal_sum += row.normal
	if normal_sum.length_squared() > 1e-8:
		ground_normal = normal_sum.normalized()


## One tick of riding before the board solve. Returns the truck steering targets.
func update(board: BoardPhysics, input: RidingInput) -> Vector2:
	var dt := SimMath.DT
	_clock += dt
	state_timer += dt
	just_landed = false
	if input.active:
		time_without_input = 0.0
	else:
		time_without_input += dt
	observe_contacts(board)
	_select_state(board)
	filtered_normal = RidingFrame.filter_normal(filtered_normal, ground_normal)
	frame.observe(board, ground_normal, filtered_normal, facing_sign)
	frame.wheel_contacts = wheels_down.count(true)
	frame.front_wheels_down = wheels_down[0] or wheels_down[1]
	frame.back_wheels_down = wheels_down[2] or wheels_down[3]
	frame.time_on_ground = time_on_ground

	_update_push(input)
	var travel := 1.0 if frame.forward_speed * facing_sign >= 0.0 else -1.0
	var tilt := RidingForces.steer_angle(steer_state, tuning, input.turn, input.sharp_turn,
		frame.absolute_speed, travel, input.balance, is_pushing())
	var active := [frame.back_wheels_down, frame.front_wheels_down]
	if facing_sign < 0.0:
		active.reverse()
	RidingForces.ease_truck_angles(truck_state, tilt, tuning.truck_follow_blend, active)
	truck_targets = truck_state.targets

	var deck := board.deck()
	var drag := 0.0
	if state == State.GROUND or state == State.SLIDE:
		RidingForces.drift_correction(deck)
	match state:
		State.GROUND:
			drag = _ground_forces(board, deck, input)
		State.SLIDE:
			_slide_forces(board, deck, input)
	for body in board.bodies:
		body.linear_drag = drag * SimMath.FREQUENCY
	var wheel_drag := 0.0 if state == State.GROUND or state == State.SLIDE else tuning.wheel_angular_drag_air * SimMath.FREQUENCY
	for wheel in BoardSpec.WHEELS:
		board.bodies[wheel].angular_drag = wheel_drag
	if state == State.GROUND or state == State.SLIDE:
		time_on_ground += dt
		grip_time += dt
	if state == State.GRIND:
		truck_targets = Vector2.ZERO
	return truck_targets


## Ground/air state rules, plus powerslide entry and exit.
func _select_state(board: BoardPhysics) -> void:
	var on_ground := wheels_down.count(true) > 0
	match state:
		State.GROUND, State.SLIDE:
			if not colliding and not on_ground:
				_enter(State.AIR)
		State.AIR:
			if state_timer > tuning.min_air_time and colliding and on_ground:
				_land(board)
		State.GRIND, State.BAIL:
			pass


## Wipeout: the rider is off the board, which tumbles freely until respawn.
func bail() -> void:
	_enter(State.BAIL)
	push_phase = PushPhase.NONE


## A grind owns the board: no riding forces until it ends.
func enter_grind() -> void:
	_enter(State.GRIND)
	push_phase = PushPhase.NONE


## The pop: leave the ground now rather than when contacts break.
func force_air() -> void:
	_enter(State.AIR)


func _enter(next: State) -> void:
	state = next
	state_timer = 0.0
	if next == State.AIR:
		push_phase = PushPhase.NONE


## Ground entry: keep only yaw spin, seed the speed
## target from the tangential speed and restart the grip and foot-force clocks.
func _land(board: BoardPhysics) -> void:
	_enter(State.GROUND)
	just_landed = true
	time_on_ground = 0.0
	grip_time = 0.0
	var deck := board.deck()
	deck.angular_velocity = ground_normal * deck.angular_velocity.dot(ground_normal)
	var forward := deck.basis.z
	var tangent := deck.linear_velocity - ground_normal * deck.linear_velocity.dot(ground_normal)
	rolling_state.target_speed = minf(absf(deck.linear_velocity.dot(forward)), absf(tangent.dot(forward)))
	rolling_state.reset = false
	filtered_normal = ground_normal


func _update_push(input: RidingInput) -> void:
	var dt := SimMath.DT
	if input.push_pressed:
		push_buffered_until = _clock + tuning.push_buffer_time
	var wants_push := input.push_held or push_buffered_until >= _clock
	push_again = wants_push
	if state != State.GROUND:
		push_phase = PushPhase.NONE
		return
	push_timer += dt
	match push_phase:
		PushPhase.NONE:
			if wants_push:
				_start_push()
		PushPhase.REACH:
			if push_timer >= tuning.push_reach_time:
				push_phase = PushPhase.DRIVE
				push_timer = 0.0
				# The plant fixes this push's target speed.
				var speed := maxf(frame.forward_speed, 0.0)
				push_target = speed + LinearCurve.evaluate(tuning.push_gain_vs_speed, speed)
				push_count += 1
		PushPhase.DRIVE:
			if push_timer >= tuning.push_drive_time:
				push_timer = 0.0
				# With another push to come at speed, glide first; the faster, the longer.
				push_hang = _push_hang_time() if wants_push else 0.0
				if push_hang > 0.0:
					push_phase = PushPhase.HANG
					if not input.push_held:
						# A tapped push waits out the glide (and a tick or two to spare:
						# the phases end on whole ticks).
						push_buffered_until = _clock + push_hang + tuning.push_swing_time + 0.1
				else:
					push_phase = PushPhase.SWING
		PushPhase.HANG:
			# Letting go of W ends the glide: the foot comes back to the board.
			if push_timer >= push_hang or not wants_push:
				push_phase = PushPhase.SWING
				push_timer = 0.0
		PushPhase.SWING:
			if push_timer >= tuning.push_swing_time:
				if wants_push:
					_start_push()
				else:
					push_phase = PushPhase.NONE


## Seconds to glide before the next push at the speed now.
func _push_hang_time() -> float:
	var from := tuning.push_hang_from_speed
	var span := maxf(tuning.push_top_speed - from, 0.1)
	var time := tuning.push_hang_time * clampf((maxf(frame.forward_speed, 0.0) - from) / span, 0.0, 1.0)
	# A glide shorter than a tick is no glide.
	return time if time >= SimMath.DT else 0.0


func _start_push() -> void:
	push_phase = PushPhase.REACH
	push_timer = 0.0
	push_buffered_until = -1.0


## Forces while rolling on the ground. Returns the linear drag to apply.
func _ground_forces(board: BoardPhysics, deck: SimBody, input: RidingInput) -> float:
	var t := tuning
	var f := frame
	var braking := input.brake > 0.0
	var pushing_force := push_phase == PushPhase.DRIVE

	if input.slide and f.absolute_speed > t.slide_start_speed:
		_start_slide(input)
		return 0.0

	var brake_force := RidingForces.braking_force(t, f, input.brake, false) if braking else Vector3.ZERO
	var push := RidingForces.push_force(t, f, push_target) if pushing_force else Vector3.ZERO
	var shares := RidingForces.weight_split(input.balance)
	var front: Array = RidingForces.foot_weight(t, f, t.foot_spacing, 0.0, shares.x, input.balance)
	var back: Array = RidingForces.foot_weight(t, f, -t.foot_spacing, 0.0, shares.y, input.balance)
	board.queue_force(front[0], front[1])
	board.queue_force(back[0], back[1])
	board.queue_force(brake_force, Vector3.ZERO)
	board.queue_force(push, Vector3.ZERO)

	RidingForces.request_rotation(deck, RidingForces.line_up_torque(t, f, grip_time, input.turn))
	RidingForces.request_rotation(deck, RidingForces.turn_torque(t, f, turn_state, input.turn, input.balance, input.turn * 0.6))
	RidingForces.apply_rotation(deck, RidingForces.level_torque(t, f, input.balance, false))
	_noise_time += SimMath.DT
	var balancing_wheels := f.back_wheels_down if input.balance > 0.0 else f.front_wheels_down
	var other_wheels := f.front_wheels_down if input.balance > 0.0 else f.back_wheels_down
	RidingForces.apply_rotation(deck, RidingForces.manual_pitch(manual_state, t, f, input.balance, _noise_time,
		balancing_wheels and not other_wheels or manual_state.elapsed < 0.3, other_wheels))
	manual_time = manual_time + SimMath.DT if input.balance != 0.0 else 0.0

	var speed_enabled := not pushing_force and not braking
	var speed_force := RidingForces.rolling_force(rolling_state, t, f, speed_enabled, input.balance, time_without_input)
	board.queue_force(speed_force, Vector3.ZERO)
	board.queue_force(RidingForces.side_grip(t, f, grip_time), Vector3.ZERO)

	var pump := _pump(input)
	board.queue_force(pump, Vector3.ZERO)

	if (push + brake_force + pump).length_squared() > ROLLING_RESET_FORCE_SQUARED:
		rolling_state.reset = true
	return RidingForces.stop_drag(t, f, braking, input.balance)


## Pumping: the force from a rising centre of mass while the ground normal
## turns under the board.
func _pump(input: RidingInput) -> Vector3:
	var t := tuning
	var f := frame
	var p := pump_state
	pump_acceleration = 0.0
	var height := input.com_height
	if p.valid:
		var rising := maxf(height - p.height, 0.0)
		p.smoothed = rising * t.pump_rise_smoothing + (1.0 - t.pump_rise_smoothing) * p.smoothed
		var effect: float = 0.0 if p.smoothed < t.pump_min_rise else p.smoothed
		p.time = p.time + f.dt if effect > 0.0 else 0.0
		effect = minf(effect, t.pump_max_rise) * LinearCurve.evaluate(t.pump_fade, p.time)
		# Signed turn rate of the ground normal: positive in a concave transition,
		# where the normal tips back against the direction of travel.
		var previous: Vector3 = p.normal
		var travel := f.ground_velocity.normalized() if f.surface_speed > 0.2 else f.deck_forward
		var turn := (ground_normal - previous).dot(-travel) / f.dt
		p.angular = turn * t.pump_curve_smoothing + (1.0 - t.pump_curve_smoothing) * p.angular
		var pumping: float = p.angular * LinearCurve.evaluate(t.pump_speed_response, f.surface_speed)
		var factor := t.pump_speed_up_factor if pumping * effect > 0.0 else t.pump_slow_down_factor
		pump_acceleration = clampf(pumping * factor * effect, -t.pump_max_slow_down * f.dt, t.pump_max_speed_up * f.dt)
	p.valid = true
	p.height = height
	p.normal = ground_normal
	var scalar := pump_acceleration if input.player_pumping else pump_acceleration * t.auto_pump_share
	var direction := f.ground_velocity.normalized() if f.surface_speed > 0.2 else Vector3.ZERO
	return direction * (f.total_mass * scalar / f.dt)


func _start_slide(input: RidingInput) -> void:
	_enter(State.SLIDE)
	slide_elapsed = 0.0
	slide_value = 0.0
	slide_side = signf(input.slide_direction) if input.slide_direction != 0.0 else 1.0
	push_phase = PushPhase.NONE
	reverting = false


## Revert: just after landing, swing the board a half turn on its
## wheels, using the powerslide yaw with a full half-turn target.
var reverting := false


func start_revert(direction: float) -> void:
	_enter(State.SLIDE)
	slide_elapsed = 0.0
	slide_value = 0.0
	slide_side = signf(direction) if direction != 0.0 else 1.0
	push_phase = PushPhase.NONE
	reverting = true


func _slide_forces(board: BoardPhysics, deck: SimBody, input: RidingInput) -> void:
	var t := tuning
	var f := frame
	slide_elapsed += SimMath.DT
	var goal := slide_side * t.slide_full_angle if input.slide else 0.0
	if reverting:
		goal = slide_side * 1.0
		slide_value = move_toward(slide_value, goal, 6.0 * SimMath.DT)
		var velocity := f.velocity - f.ground_normal * f.velocity.dot(f.ground_normal)
		# Done once the board points back along the line of travel.
		if slide_elapsed > 0.2 and velocity.length() > 0.3 and absf(f.deck_forward.normalized().dot(velocity.normalized())) > 0.97:
			reverting = false
			_enter(State.GROUND)
			grip_time = 0.0
			rolling_state.reset = true
			return
		if slide_elapsed > 0.8:
			reverting = false
	else:
		slide_value = move_toward(slide_value, goal, t.slide_build_rate * SimMath.DT)
	if not reverting and ((not input.slide and absf(slide_value) < 0.05) or f.surface_speed < 0.4):
		_enter(State.GROUND)
		grip_time = 0.0
		rolling_state.reset = true
		return
	var front: Array = RidingForces.foot_weight(t, f, t.foot_spacing, 0.0, 1.0, 0.0)
	var back: Array = RidingForces.foot_weight(t, f, -t.foot_spacing, 0.0, 1.0, 0.0)
	board.queue_force(front[0], front[1])
	board.queue_force(back[0], back[1])
	var slide: Array = RidingForces.powerslide_drag(t, f)
	board.queue_force(slide[0], slide[1])
	RidingForces.apply_rotation(deck, RidingForces.powerslide_yaw(t, f, slide_value, slide_elapsed))
	RidingForces.apply_rotation(deck, RidingForces.level_torque(t, f, 0.0, false))
	rolling_state.reset = true


func state_name() -> String:
	return State.keys()[state]


## Wheel contact material: wheels skid on a slippery material while sliding.
func wheel_material() -> ContactMaterial:
	if state == State.SLIDE:
		return ContactMaterial.make(tuning.slide_wheel_static_friction, tuning.slide_wheel_dynamic_friction, tuning.wheel_restitution)
	return tuning.wheel_material()
