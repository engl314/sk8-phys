class_name SkaterController
extends Node3D

const Action := VirtualPad.Action
## Smoothed ground-normal turn rate (rad/s, the pump controller's) that counts
## as riding a transition, and below which the ground counts as straight again.
const PUMP_CURVING := 0.5
const PUMP_STRAIGHT := 0.25
## W pumps rather than pushes for this long after the last transition.
const PUMP_MEMORY := 0.8
## Rolling backwards faster than this (m/s) for this long (s) switches stance,
## so forward is always the way of travel (down a wall, out of a revert).
const BACKWARD_SPEED := 0.5
const BACKWARD_TIME := 0.2

@export var tuning: SkateTuning

var board := BoardPhysics.new()
var collider := BoardCollider.new()
var pad := VirtualPad.new()
var rider: RidingModel
var rider_input := RidingInput.new()
var board_visual := BoardVisual.new()
var animator := RiderAnimator.new()
var director: TrickDirector
var grind: GrindController
var score: ScoreKeeper
var autopilot := false
## Tests drive the pad through this: called after sampling with the tick number,
## it can `pad.hold()` actions and set `pad.steer`.
var scripted_input: Callable
## Frame the rider is posed in: the deck on the ground, upright in the air.
var rider_frame := Transform3D.IDENTITY
## World basis the rider frame turns toward while airborne.
var rider_frame_target := Basis()

var collisions: Array[BoardContact] = []
var truck_targets := Vector2.ZERO
var tick := 0
var _spawn := Transform3D.IDENTITY
## Where to come back after a bail: a recent spot the rider was riding well.
var _safe_spots: Array[Transform3D] = []
var _safe_timer := 0.0


func _init() -> void:
	tuning = load("res://tuning/default_tuning.tres") if ResourceLoader.exists("res://tuning/default_tuning.tres") else SkateTuning.new()
	rider = RidingModel.new(tuning)
	director = TrickDirector.new(self)
	grind = GrindController.new(self)
	score = ScoreKeeper.new(self)


func _ready() -> void:
	add_child(pad)
	board_visual.name = "BoardVisual"
	board_visual.top_level = true
	add_child(board_visual)
	animator.name = "Rider"
	add_child(animator)


func respawn(at: Transform3D, remember := true) -> void:
	if remember:
		_spawn = at
	var deck_transform := at
	deck_transform.origin += at.basis.y * BoardSpec.LEVEL_GROUND_DECK_HEIGHT
	_apply_tuning()
	board.spawn(deck_transform, true)
	animator.stop_ragdoll()
	animator.reset_stance()
	rider.reset()
	director.reset()
	grind.reset()
	rider_frame = deck_transform
	truck_targets = Vector2.ZERO
	if is_inside_tree():
		board_visual.sync(board)


func _apply_tuning() -> void:
	board.gravity = Vector3(0.0, -tuning.gravity, 0.0)
	board.iterations = tuning.solver_iterations
	collider.wheel_material = rider.wheel_material()


func _physics_process(delta: float) -> void:
	tick += 1
	pad.sample(delta)
	if scripted_input.is_valid():
		scripted_input.call(tick)
	if autopilot:
		pad.hold(Action.PUSH, tick < 400)
		pad.steer = sin(tick * 0.012) * 0.6
	pad.commit(delta)
	if pad.pressed(Action.RESPAWN):
		respawn(_spawn)
	elif director.ready_to_respawn():
		respawn(_safe_spot(), false)
	_apply_tuning()
	_check_rolling_backward(delta)
	_read_input()
	director.pre_physics(delta)
	grind.pre_physics(delta)
	truck_targets = rider.update(board, rider_input)
	collider.grinding = grind.active
	collisions = collider.gather(board, get_world_3d().direct_space_state)
	board.step(collisions, truck_targets)
	board.clear_forces()
	director.post_physics(delta)
	score.update(delta)
	_record_safe_spot(delta)
	_update_rider_frame(delta)
	board_visual.sync(board)
	global_transform = board.body_transform(BoardSpec.Body.DECK)
	_tell_rider()
	animator.step(delta)


## Everything the rider's animation is told about this tick. The rig reads
## nothing else of the game (see RiderInputs), so this is the one place where
## the two meet: another game puts its own values here.
func _tell_rider() -> void:
	var to := animator.inputs
	# Where the board is and how it is moving.
	to.deck = deck_effective()
	to.frame = rider_frame
	to.velocity = velocity()
	to.angular_velocity = board.deck().angular_velocity
	to.forward_speed = rider.frame.forward_speed
	to.ground_normal = rider.ground_normal
	to.gravity = tuning.gravity
	# What it is doing.
	match rider.state:
		RidingModel.State.GROUND: to.state = RiderInputs.State.GROUND
		RidingModel.State.SLIDE: to.state = RiderInputs.State.SLIDE
		RidingModel.State.AIR: to.state = RiderInputs.State.AIR
		RidingModel.State.GRIND: to.state = RiderInputs.State.GRIND
		RidingModel.State.BAIL: to.state = RiderInputs.State.BAIL
	to.just_landed = rider.just_landed
	to.manual_time = rider.manual_time
	to.grind_lean = grind.lean
	# What the player is asking for.
	to.steer = rider_input.turn
	to.balance = rider_input.balance
	to.crouch = 1.0 if director.wants_crouch() or pumping and _pump_crouch else 0.0
	to.crouch_held = director.wants_crouch()
	to.nollie_held = pad.down(VirtualPad.Action.NOLLIE)
	# Pushing.
	match rider.push_phase:
		RidingModel.PushPhase.NONE: to.push_phase = RiderInputs.Push.NONE
		RidingModel.PushPhase.REACH: to.push_phase = RiderInputs.Push.REACH
		RidingModel.PushPhase.DRIVE: to.push_phase = RiderInputs.Push.DRIVE
		RidingModel.PushPhase.SWING: to.push_phase = RiderInputs.Push.SWING
		RidingModel.PushPhase.HANG: to.push_phase = RiderInputs.Push.HANG
	to.push_progress = rider.push_progress()
	to.push_again = rider.push_again
	to.push_hang = rider.push_hang
	to.push_reach_time = tuning.push_reach_time
	to.push_drive_time = tuning.push_drive_time
	to.push_swing_time = tuning.push_swing_time
	# In the air, and the trick under way.
	to.airborne = director.airborne
	to.air_time = director.air_time
	to.time_to_land = director.time_to_land
	to.landing_point = director.landing_point
	to.spin_rate = director.spin_rate
	to.trick_active = director.trick_key != ""
	to.trick_late = director.late
	to.trick_turns_board = director.trick.get("flip", 0.0) != 0.0 or director.trick.get("shuv", 0.0) != 0.0
	to.trick_progress = director.trick_progress
	to.board_turning = director.board_turning()
	to.trick_basis = director.trick_basis()
	to.feet_off = director.feet_off
	to.front_foot_slide = director.front_foot_slide
	to.kick_side = director.kick_side
	to.nollie = director.nollie
	to.grabbing = director.grab != ""
	to.grab_blend = director.grab_blend
	to.grab_point = director.grab_point
	to.grab_front_hand = director.grab_front_hand
	# The board itself.
	to.deck_ride_height = BoardSpec.LEVEL_GROUND_DECK_HEIGHT
	to.deck_width = BoardSpec.DECK_WIDTH
	to.deck_flat_length = BoardSpec.DECK_FLAT_LENGTH
	to.nose_kick_degrees = BoardSpec.NOSE_KICK_DEGREES
	to.tail_kick_degrees = BoardSpec.TAIL_KICK_DEGREES


## Riding intentions from the keyboard: A/D steer (positive turn =
## left), W pushes (or pumps in a transition), S brakes, and S with a hard turn
## powerslides.
func _read_input() -> void:
	var steer := pad.steer
	var balance := _manual_balance()
	_update_pump()
	rider_input.turn = -steer
	rider_input.sharp_turn = 0.0
	var sliding := rider.state == RidingModel.State.SLIDE or rider.frame.absolute_speed > tuning.slide_start_speed
	rider_input.slide = pad.down(Action.BRAKE) and absf(steer) > 0.5 and sliding and balance == 0.0
	rider_input.slide_direction = -steer
	rider_input.brake = 1.0 if pad.down(Action.BRAKE) and not rider_input.slide and balance == 0.0 else 0.0
	# No pushing while pumping, crouched for a pop or balancing a manual.
	var can_push := not pumping and balance == 0.0 and not director.wants_crouch()
	rider_input.push_pressed = pad.pressed(Action.PUSH) and can_push
	rider_input.push_held = pad.down(Action.PUSH) and can_push
	rider_input.balance = balance
	rider_input.com_height = animator.hip_height() * 0.95
	rider_input.player_pumping = pumping
	rider_input.active = absf(steer) > 0.05 or pad.any_down()


## Ride the other way round: the board's tail becomes the nose and the stance
## flips (goofy rides regular and back), so the body keeps its place but forward
## is the way it's going. The rig frame turns with the deck so the body doesn't spin.
func switch_stance() -> void:
	rider.switch_direction()
	animator.swap_stance()
	rider_frame.basis = rider_frame.basis * Basis(Vector3.UP, PI)
	_backward_time = 0.0


var _backward_time := 0.0


func _check_rolling_backward(delta: float) -> void:
	var backward := rider.state == RidingModel.State.GROUND and not rider.reverting \
		and rider.frame.forward_speed < -BACKWARD_SPEED
	_backward_time = _backward_time + delta if backward else 0.0
	if _backward_time >= BACKWARD_TIME:
		switch_stance()


## Remember grounded, upright spots twice a second; respawn at one a second old.
func _record_safe_spot(delta: float) -> void:
	_safe_timer += delta
	if _safe_timer < 0.5 or rider.state != RidingModel.State.GROUND or board.deck().basis.y.y < 0.9:
		return
	_safe_timer = 0.0
	var deck := deck_effective()
	var flat := Vector3(deck.basis.z.x, 0.0, deck.basis.z.z).normalized()
	var spot := Transform3D(Basis.looking_at(-flat, Vector3.UP), deck.origin - Vector3.UP * BoardSpec.LEVEL_GROUND_DECK_HEIGHT)
	_safe_spots.append(spot)
	if _safe_spots.size() > 6:
		_safe_spots.pop_front()


func _safe_spot() -> Transform3D:
	if _safe_spots.size() >= 3:
		return _safe_spots[_safe_spots.size() - 3]
	return _spawn if _safe_spots.is_empty() else _safe_spots[0]


func _update_rider_frame(delta: float) -> void:
	var deck := deck_effective()
	var target := rider_frame_target if director.airborne else deck.basis
	var q := rider_frame.basis.get_rotation_quaternion().slerp(target.get_rotation_quaternion(), 1.0 - exp(-22.0 * delta))
	rider_frame = Transform3D(Basis(q), deck.origin)


## Manual intent: C held on the ground balances on
## the back wheels (balance > 0), or the front ones if Shift was down as it
## started. W eases the tilt off; S tips it onto the tail as a brake.
var _manual_sign := 1.0


func _manual_balance() -> float:
	if not pad.down(Action.BOARD) or not rider.is_grounded() or director.airborne:
		return 0.0
	if rider.manual_time == 0.0:
		_manual_sign = -1.0 if pad.down(Action.NOLLIE) else 1.0
	var amount := tuning.manual_balance
	if pad.down(Action.PUSH):
		amount *= 0.35
	elif pad.down(Action.BRAKE):
		amount = 1.0
	return amount * _manual_sign


## Pumping: W in a transition stops pushing and works the
## crouch instead: down where the ground runs straight, up through the curve.
## The pump controller turns that standing up against the curve into speed.
var pumping := false
var _pump_crouch := false
var _since_curve := 99.0


func _update_pump() -> void:
	var curving: float = rider.pump_state.angular
	_since_curve = 0.0 if curving > PUMP_CURVING else _since_curve + SimMath.DT
	pumping = pad.down(Action.PUSH) and rider.is_grounded() and _since_curve < PUMP_MEMORY
	if curving > PUMP_CURVING:
		_pump_crouch = false
	elif curving < PUMP_STRAIGHT:
		_pump_crouch = true


func debug_lines() -> Array[String]:
	var deck := board.deck()
	var out: Array[String] = []
	out.append("state %s  t %.2f   push %s #%d   slide %.2f   target %.2f" % [rider.state_name(), rider.state_timer,
		RidingModel.PushPhase.keys()[rider.push_phase], rider.push_count, rider.slide_value, rider.rolling_state.target_speed])
	out.append("fwd speed %+.2f   ground n %s   up %s" % [rider.frame.forward_speed, _v3(rider.ground_normal), _v3(deck.basis.y)])
	return out


static func _v3(v: Vector3) -> String:
	return "(%.2f, %.2f, %.2f)" % [v.x, v.y, v.z]


func deck_transform() -> Transform3D:
	return board.body_transform(BoardSpec.Body.DECK)


## The deck as the rider stands on it: turned half a turn when the rider faces
## its tail (after a shove-it), so +Z is always the rider's nose.
func deck_effective() -> Transform3D:
	var deck := deck_transform()
	if rider.facing_sign < 0.0:
		deck.basis = deck.basis * Basis(Vector3.UP, PI)
	return deck


func is_grounded() -> bool:
	return rider.is_grounded()


## Point the camera frames (the deck; the rig offsets above it), or the
## tumbling body during a bail.
func camera_subject() -> Vector3:
	if animator.is_ragdoll():
		return animator.ragdoll_hips() - Vector3.UP * 0.7
	return board.deck().position


## Camera heading: the direction of travel when moving, else the rider's forward.
func camera_heading() -> float:
	var v := board.deck().linear_velocity
	v.y = 0.0
	var forward := board.deck().basis.z * rider.facing_sign
	forward.y = 0.0
	if v.length() > 1.0:
		var blend := clampf((v.length() - 1.0) / 1.0, 0.0, 1.0)
		var dir := forward.normalized().slerp(v.normalized(), blend) if forward.length_squared() > 1e-4 else v.normalized()
		return atan2(dir.x, dir.z)
	if forward.length_squared() < 1e-4:
		return 0.0
	return atan2(forward.x, forward.z)


func velocity() -> Vector3:
	return board.deck().linear_velocity
