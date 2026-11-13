class_name TrickDirector
extends RefCounted

signal trick_landed(name: String)
signal bailed(reason: String)

const Action := VirtualPad.Action
## Dip before a pop from a standing rider; also the window to combine buttons.
const WINDUP := 0.12
## Window to combine buttons when already crouched, on a rail or in the air.
const COMBO_WINDOW := 0.05
## A pop that can't fire yet (the wheels only just touched down) is dropped after this.
const PENDING_TIMEOUT := 0.4
## Holding a flip button this long after pressing it adds a flip, and one more
## each HOLD_STEP; holding a shove-it button this long makes it a 360.
const HOLD_START := 0.28
const HOLD_STEP := 0.12
const HOLD_WINDOW := 0.4

var skater: SkaterController
var tuning: SkateTuning

var airborne := false
var air_time := 0.0
var nollie := false
var fakie := false
## Took off riding the other stance from the rider's own.
var riding_switch := false
## Rider heading (yaw of the effective deck's +Z) while airborne, and its spin.
var heading := 0.0
var spin_rate := 0.0
var spin_total := 0.0
var time_to_land := INF
var landing_point := Vector3.ZERO
var bail_timer := -1.0
var last_message := ""
var last_message_time := -10.0
var clock := 0.0

# Flip trick in progress.
var trick_key := ""
var trick: Dictionary = {}
var trick_time := 0.0
var trick_finish := 0.4
var trick_progress := 0.0
var late := false
var flip_turns := 0.0
var flip_turns_target := 0.0
var shuv_turns := 0.0
var shuv_turns_target := 0.0
var _hold_extra := 0
## Buttons behind the trick in the air, for holds (-1 = none, or let go).
var _flip_button := -1
var _shuv_button := -1
## The trick came off a pop (not a roll-off): the pop's board pitch runs.
var _popped := false
var _pop_rotating := false
## The pop pitch as the board carries it, in degrees (momentum past the key angles).
var _pitch := MotionFilters.SecondOrder.new(7.0, 0.6, 0.0)
## Air time at which the feet caught the turning board (-1 = not yet).
var _caught_at := -1.0

# A pop asked for by the buttons, gathering buttons until it fires.
var _pending := false
var _pending_late := false
var _pending_time := 0.0
var _pending_wait := 0.0
var _pending_flip := 0
var _pending_shuv := 0
var _pending_nollie := false
## The Space press already went into a pop, so letting go does nothing.
var pop_consumed := false

# Grabs.
var grab := ""
var grab_front_hand := true
var grab_point := Vector3.ZERO
var grab_blend := 0.0
var grab_time := 0.0
var grabbed_names: Array[String] = []
## C went down in this air phase (a C held since the ground doesn't grab).
var _grab_requested := false

# Presentation hooks for the animator.
## Deck-space offset of the front foot as it drags up toward the nose.
var front_foot_slide := 0.0
## 0 = feet on the board, 1 = feet off it (flicked away while the board turns).
var feet_off := 0.0
## +1 when the kick goes off the toe edge, -1 off the heel edge, 0 for scoops.
var kick_side := 0.0

var _ray := PhysicsRayQueryParameters3D.new()
var _since_landing := 99.0
var _revert_armed := false
var _last_manual_time := 0.0
var _last_balance := 0.0


func _init(owner: SkaterController) -> void:
	skater = owner
	tuning = owner.tuning


func reset() -> void:
	airborne = false
	air_time = 0.0
	spin_rate = 0.0
	bail_timer = -1.0
	trick_key = ""
	grab = ""
	feet_off = 0.0
	_pending = false
	pop_consumed = false
	_disable_guide()


func mirrored() -> bool:
	return skater.animator.stance == RiderAnimator.Stance.GOOFY


func stance_sign() -> float:
	return -1.0 if mirrored() else 1.0


## Before the riding update: trick buttons, pops, air control.
func pre_physics(dt: float) -> void:
	clock += dt
	var rider := skater.rider
	if bail_timer >= 0.0:
		bail_timer += dt
		return
	_read_buttons(dt)
	_since_landing += dt
	# Revert: a powerslide (S with A or D) started just after landing swings the
	# board round. It has to start after touching down: a slide held through the
	# landing does not revert.
	var pad := skater.pad
	if not _slide_held(0.5):
		_revert_armed = true
	if rider.state == RidingModel.State.GROUND and _since_landing < tuning.revert_window and _revert_armed \
			and _slide_held(0.8) and rider.frame.absolute_speed > 1.0:
		rider.start_revert(-pad.steer)
		_since_landing = 99.0
		_message("Revert")
		trick_landed.emit("Revert")
	# A manual held long enough counts as a trick when it ends.
	if rider.manual_time == 0.0 and _last_manual_time > 0.5:
		var label := "Manual" if _last_balance > 0.0 else "Nose Manual"
		_message(label)
		trick_landed.emit(label)
	_last_manual_time = rider.manual_time
	if rider.manual_time > 0.0 and skater.rider_input.balance != 0.0:
		_last_balance = skater.rider_input.balance
	if airborne:
		_update_hold()
		_update_grab(dt)
		_air(dt)


func _slide_held(turn: float) -> bool:
	return skater.pad.down(Action.BRAKE) and absf(skater.pad.steer) > turn


## The rider dips while a pop winds up.
func winding_up() -> bool:
	return _pending and not _pending_late


## Space held (and not spent on a pop yet), or a pop winding up: crouch.
func wants_crouch() -> bool:
	return skater.pad.down(Action.POP) and not pop_consumed or winding_up()


## Trick buttons: a press asks for a pop (or a late flip in the air), and the
## request gathers buttons for a moment before it fires.
func _read_buttons(dt: float) -> void:
	var pad := skater.pad
	var state := skater.rider.state
	var rolling := state == RidingModel.State.GROUND
	var grinding := state == RidingModel.State.GRIND
	if pad.pressed(Action.POP):
		pop_consumed = false
	var trick_pressed := pad.pressed(Action.KICKFLIP) or pad.pressed(Action.HEELFLIP) \
		or pad.pressed(Action.SHUVIT) or pad.pressed(Action.FS_SHUVIT)
	if not _pending:
		if trick_pressed and (rolling or grinding):
			var crouched := pad.down(Action.POP) and not pop_consumed and pad.held_time(Action.POP) >= WINDUP
			_request(COMBO_WINDOW if crouched or grinding else WINDUP, false)
		elif trick_pressed and airborne and _late_allowed():
			_request(COMBO_WINDOW, true)
		elif pad.released(Action.POP) and not pop_consumed and (rolling or grinding):
			# A quick tap still gets the dip before the pop.
			_request(maxf(WINDUP - pad.held_time(Action.POP), 0.0), false)
	if not _pending:
		return
	_pending_time += dt
	if _pending_flip == 0:
		_pending_flip = 1 if pad.down(Action.KICKFLIP) else (-1 if pad.down(Action.HEELFLIP) else 0)
	if _pending_shuv == 0:
		_pending_shuv = 1 if pad.down(Action.SHUVIT) else (-1 if pad.down(Action.FS_SHUVIT) else 0)
	_pending_nollie = _pending_nollie or pad.down(Action.NOLLIE)
	if pad.down(Action.POP):
		pop_consumed = true
	if _pending_late and (pad.down(Action.BOARD) or not airborne):
		# A grab (or the landing) got there first.
		_pending = false
		return
	if _pending_time >= _pending_wait:
		_fire()


func _request(wait: float, is_late: bool) -> void:
	_pending = true
	_pending_late = is_late
	_pending_time = 0.0
	_pending_wait = wait
	_pending_flip = 0
	_pending_shuv = 0
	_pending_nollie = false


func _fire() -> void:
	var rider := skater.rider
	var key := TrickTable.trick_for_buttons(_pending_flip, _pending_shuv, _pending_nollie)
	_pending = false
	if _pending_late:
		_late_flip(key)
	elif rider.state == RidingModel.State.GRIND:
		skater.grind.pop_out(key, lerpf(0.5, 1.0, skater.animator.crouch.value))
	elif rider.state == RidingModel.State.GROUND:
		if rider.time_on_ground <= 0.12:
			# Only just landed: wait for the wheels to settle.
			_pending = _pending_time < PENDING_TIMEOUT
			return
		_pop(key)
	elif airborne and _late_allowed():
		# Rolled off an edge while winding up.
		_late_flip(key)
	if trick_key != "":
		_flip_button = -1 if _pending_flip == 0 else (Action.KICKFLIP if _pending_flip > 0 else Action.HEELFLIP)
		_shuv_button = -1 if _pending_shuv == 0 else (Action.SHUVIT if _pending_shuv > 0 else Action.FS_SHUVIT)


## A late flip needs a plain ollie (or no pop at all), free hands and time to land.
func _late_allowed() -> bool:
	var plain: bool = trick_key == "" or trick.flip == 0.0 and trick.shuv == 0.0
	return plain and grab == "" and time_to_land > 0.28


## After the board solve: landings.
func post_physics(_dt: float) -> void:
	var rider := skater.rider
	if airborne and rider.just_landed:
		_land()
	elif airborne and air_time > 0.3 and rider.state != RidingModel.State.AIR:
		_land()
	elif not airborne and rider.state == RidingModel.State.AIR and rider.state_timer > 0.12:
		# Rolled off an edge: the air phase starts without a pop.
		_start_air()


## The pop at full strength: how high it goes comes from how deep the rider
## crouched (PopLaunch launches from the current COM height).
func _pop(key: String) -> void:
	var rider := skater.rider
	var deck := skater.board.deck()
	var frame := rider.frame
	var com_height := BoardSpec.LEVEL_GROUND_DECK_HEIGHT + skater.animator.hip_height() * 0.95
	var launch := PopLaunch.launch_velocity(tuning, deck.linear_velocity, rider.ground_normal, frame.deck_forward,
		frame.surface_speed, 1.0, com_height, Vector2(skater.pad.steer, 0.0))
	for body in skater.board.bodies:
		body.linear_velocity = launch
	deck.angular_velocity = rider.ground_normal * deck.angular_velocity.dot(rider.ground_normal)
	fakie = frame.forward_speed < -0.3
	rider.force_air()
	skater.animator.pop(1.0)
	_start_air()
	_begin_trick(key, false)


func _late_flip(key: String) -> void:
	if key == "Ollie" or key == "Nollie":
		return
	if key.begins_with("N_"):
		key = key.substr(2)
	_begin_trick(key, true)


func _begin_trick(key: String, is_late: bool) -> void:
	trick_key = key
	trick = TrickTable.definition(key)
	nollie = trick.nollie if not is_late else nollie
	late = is_late
	trick_time = 0.0
	trick_progress = 0.0 if trick.time > 0.0 else 1.0
	flip_turns = absf(trick.flip)
	flip_turns_target = flip_turns
	shuv_turns = trick.shuv
	shuv_turns_target = shuv_turns
	_hold_extra = 0
	_caught_at = -1.0
	if not is_late:
		_popped = true
		_pop_rotating = absf(trick.flip) > 0.0 or absf(trick.shuv) > 0.0
	var room: float = time_to_land - 0.1 if time_to_land < INF else trick.time
	trick_finish = clampf(minf(trick.time, room), 0.16, 1.0)
	kick_side = signf(trick.flip)


func _start_air() -> void:
	airborne = true
	air_time = 0.0
	riding_switch = skater.animator.is_switch()
	spin_total = 0.0
	spin_rate = 0.0
	front_foot_slide = 0.0
	trick_key = ""
	trick = {}
	trick_progress = 1.0
	grab = ""
	grabbed_names.clear()
	_grab_requested = false
	late = false
	_popped = false
	_pitch.reset(0.0)
	_caught_at = -1.0
	_flip_button = -1
	_shuv_button = -1
	time_to_land = INF
	var forward := skater.deck_effective().basis.z
	heading = atan2(forward.x, forward.z)
	_predict_landing(true)
	skater.board.guide_dynamics = air_guide_dynamics()


## Guide drive dynamics while the deck follows an animated orientation:
## linear off, angular soft.
func air_guide_dynamics() -> Array:
	return [
		{"spring": 0.0, "damping": 0.0, "strength": 0.0, "type": ConstraintRow.DriveType.HARD},
		{"spring": tuning.air_pose_spring, "damping": 2.0 * sqrt(tuning.air_pose_spring), "strength": tuning.air_pose_strength, "type": ConstraintRow.DriveType.SOFT},
	]


## A grind took the board: the air phase ends without a landing check.
func enter_grind() -> void:
	airborne = false
	trick_key = ""
	grab = ""
	feet_off = 0.0
	_pending = false
	_flip_button = -1
	_shuv_button = -1


## Leaving a grind: straight into the air, with the trick the buttons asked for.
func leave_grind(key := "") -> void:
	_start_air()
	if key != "":
		skater.animator.pop(1.0)
		_begin_trick(key, false)


## Holding the button past the pop adds rotation: whole flips for a kick or heel
## flip, a full 360 for anything with a shove-it.
func _update_hold() -> void:
	if trick_key == "" or trick_time > HOLD_WINDOW or trick_progress >= 1.0:
		return
	var pad := skater.pad
	if _flip_button >= 0 and trick.shuv == 0.0:
		if not pad.down(_flip_button):
			_flip_button = -1
		elif pad.held_time(_flip_button) >= HOLD_START:
			var extra := mini(1 + int((pad.held_time(_flip_button) - HOLD_START) / HOLD_STEP), 2)
			if extra > _hold_extra:
				_hold_extra = extra
				flip_turns_target = absf(trick.flip) + extra
				# More flips take longer, but never past the landing.
				var finish := minf(trick.time * (1.0 + 0.45 * extra), time_to_land + trick_time - 0.1)
				trick_finish = maxf(finish, trick_time + 0.15)
	if _shuv_button >= 0:
		if not pad.down(_shuv_button):
			_shuv_button = -1
		elif pad.held_time(_shuv_button) >= HOLD_START:
			_shuv_button = -1
			_spin_up()


## Turn the shove-it into its 360 version. The flip keeps its place: the clock
## is rescaled so progress doesn't jump, and the extra shove eases in.
func _spin_up() -> void:
	var key := TrickTable.spun(trick_key)
	if key == "":
		return
	var u := clampf(trick_time / trick_finish, 0.0, 0.9)
	trick_key = key
	trick = TrickTable.definition(key)
	shuv_turns_target = trick.shuv
	var finish: float = trick.time
	if time_to_land < INF:
		finish = minf(finish, maxf(time_to_land - 0.1, 0.05) / (1.0 - u))
	trick_finish = maxf(finish, 0.16)
	trick_time = u * trick_finish


## C in the air grabs; W, S, Q or E held with it picks the grab.
func _update_grab(dt: float) -> void:
	var pad := skater.pad
	var holding := pad.down(Action.BOARD)
	if pad.pressed(Action.BOARD):
		_grab_requested = true
	elif not holding:
		_grab_requested = false
	if grab == "" and _grab_requested and trick_progress >= 1.0 and air_time > 0.12:
		grab = _grab_name()
		grab_time = 0.0
		grabbed_names.append(grab)
	elif grab != "" and not holding:
		grab = ""
	elif grab != "":
		grab_time += dt
		# A modifier pressed just after C still picks the grab.
		if grab_time < 0.1:
			var name := _grab_name()
			if name != grab:
				grab = name
				grabbed_names[-1] = name
	grab_blend = move_toward(grab_blend, 1.0 if grab != "" else 0.0, dt * 9.0)


func _grab_name() -> String:
	var pad := skater.pad
	var toe := skater.animator.facing().x * 0.11
	grab_front_hand = true
	if pad.down(Action.PUSH):
		grab_point = Vector3(0.0, 0.0, 0.4)
		return "Nosegrab"
	if pad.down(Action.KICKFLIP):
		grab_point = Vector3(toe, 0.0, 0.08)
		return "Mute"
	if pad.down(Action.HEELFLIP):
		grab_point = Vector3(-toe, 0.0, 0.08)
		return "Melon"
	grab_front_hand = false
	if pad.down(Action.BRAKE):
		grab_point = Vector3(0.0, 0.0, -0.4)
		return "Tailgrab"
	grab_point = Vector3(toe, 0.0, -0.05)
	return "Indy"


func _air(dt: float) -> void:
	air_time += dt
	_predict_landing(false)
	# Body spin: A/D turn the rider; the board turns with them.
	var stick := -skater.pad.steer
	var max_rate := deg_to_rad(tuning.spin_top_speed_degrees)
	var accel := deg_to_rad(tuning.spin_acceleration_degrees) * dt
	var target_rate := stick * max_rate
	if absf(stick) < 0.2 and time_to_land < tuning.landing_align_time:
		target_rate = _assist_rate()
	spin_rate = move_toward(spin_rate, target_rate, accel)
	heading = wrapf(heading + spin_rate * dt, -PI, PI)
	spin_total += spin_rate * dt

	# Flip progress: fast off the flick, settling into the catch.
	if trick_key != "" and trick_progress < 1.0:
		trick_time += dt
		var u := clampf(trick_time / trick_finish, 0.0, 1.0)
		trick_progress = 1.0 - pow(1.0 - u, 1.8)
		flip_turns = move_toward(flip_turns, flip_turns_target, dt * 20.0)
		shuv_turns = move_toward(shuv_turns, shuv_turns_target, dt * 5.0)
	var rotating := trick_key != "" and (absf(trick.get("flip", 0.0)) > 0.0 or absf(trick.get("shuv", 0.0)) > 0.0)
	if rotating and trick_progress >= 1.0 and _caught_at < 0.0:
		_caught_at = air_time
	# Feet: off the board while it turns, back on for the catch.
	var off_target := 0.0
	if rotating and trick_progress < 1.0:
		var lift := 1.0 if absf(trick.flip) > 0.0 else 0.55
		off_target = lift * (1.0 - smoothstep(0.72, 1.0, trick_progress))
	feet_off = move_toward(feet_off, off_target, dt * (14.0 if off_target > feet_off else 7.0))

	var flat := Basis(Vector3.UP, heading)
	var target := flat * _pop_pitch(dt) * _trick_rotation() * _catch_settle() * _grab_tweak()
	if skater.rider.facing_sign < 0.0:
		target = target * Basis(Vector3.UP, PI)
	skater.board.set_guide_transform(Transform3D(target, skater.board.deck().position))
	skater.rider_frame_target = flat


## Board rotation for the current flip trick, in effective deck space.
func _trick_rotation() -> Basis:
	if trick_key == "" or trick_progress >= 1.0 and trick_time == 0.0:
		return Basis.IDENTITY
	var p := trick_progress
	var s := stance_sign()
	var flip_angle: float = signf(trick.flip) * flip_turns * TAU * p * s
	var shuv_angle := shuv_turns * TAU * p * -s
	var hard := sin(p * PI) * deg_to_rad(65.0) if trick.hard else 0.0
	return Basis(Vector3.UP, shuv_angle) * Basis(Vector3.RIGHT, -hard) * Basis(Vector3.BACK, flip_angle)


## How the trick has turned the board under the rider's feet, in the deck's own
## frame: nothing when no trick is on, a whole number of turns once it is caught.
func trick_basis() -> Basis:
	if not airborne or trick_key == "":
		return Basis.IDENTITY
	return _trick_rotation() * _catch_settle()


## The board is flipping or spinning under the feet and hasn't been caught yet.
func board_turning() -> bool:
	if not airborne or trick_key == "" or trick_progress >= 1.0:
		return false
	return absf(trick.get("flip", 0.0)) > 0.0 or absf(trick.get("shuv", 0.0)) > 0.0


## The pop's board motion: the tail snaps down (nose up), the front foot drags
## the nose level by the top of the jump, and the board settles before landing.
## The board carries momentum through those key angles (it swings a little past
## each), and rolls and turns a few degrees under the dragging foot. Both fade
## out ahead of the landing, so it comes down as the key angles alone say.
func _pop_pitch(dt: float) -> Basis:
	if not _popped:
		return Basis.IDENTITY
	var t := air_time
	var up_degrees := 0.0
	if t < 0.07:
		up_degrees = lerpf(0.0, 30.0, smoothstep(0.0, 0.07, t))
	elif t < 0.13:
		up_degrees = 30.0
	elif t < 0.34:
		up_degrees = lerpf(30.0, -4.0, smoothstep(0.13, 0.34, t))
	else:
		up_degrees = lerpf(-4.0, 0.0, clampf((t - 0.34) / 0.2, 0.0, 1.0))
	if _pop_rotating:
		up_degrees *= 0.6
	front_foot_slide = clampf((t - 0.04) / 0.18, 0.0, 1.0) * (1.0 - clampf((t - 0.36) / 0.2, 0.0, 1.0)) * 0.08
	var free := smoothstep(0.1, 0.25, time_to_land)
	_pitch.configure(tuning.pop_pitch_frequency, tuning.pop_pitch_damping, 0.0)
	up_degrees = lerpf(up_degrees, _pitch.update(up_degrees, dt), free)
	# Positive rotation about +X lowers the nose; nollies lift the tail instead.
	var pitch := Basis(Vector3.RIGHT, deg_to_rad(up_degrees) * (1.0 if nollie else -1.0))
	if _pop_rotating:
		return pitch
	# The dragging foot's edge tips the toe side down and turns the nose with it.
	var style := deg_to_rad(tuning.pop_style_degrees) * sin(PI * clampf((t - 0.03) / 0.26, 0.0, 1.0)) * free * stance_sign()
	return pitch * Basis(Vector3.BACK, style) * Basis(Vector3.UP, -style * 0.4)


## The catch: the feet stop the turning board, which rocks on past and back.
func _catch_settle() -> Basis:
	if _caught_at < 0.0 or trick_key == "":
		return Basis.IDENTITY
	var since := air_time - _caught_at
	var rock := deg_to_rad(tuning.catch_wobble_degrees) * exp(-since / 0.07) * sin(since * TAU * 8.0)
	rock *= smoothstep(0.06, 0.2, time_to_land)
	if absf(trick.get("flip", 0.0)) > 0.0:
		return Basis(Vector3.BACK, rock * signf(trick.flip) * stance_sign())
	return Basis(Vector3.UP, rock * signf(trick.get("shuv", 0.0)) * -stance_sign())


## Holding a grab tweaks it: the board tips further toward the grabbed side.
func _grab_tweak() -> Basis:
	if grab_blend <= 0.0:
		return Basis.IDENTITY
	var tweak := smoothstep(0.1, 0.5, grab_time)
	var roll := deg_to_rad(18.0 + tweak * 16.0) * grab_blend * (1.0 if grab_point.x * skater.animator.facing().x > 0.0 else -1.0)
	var pitch := deg_to_rad((10.0 + tweak * 8.0) * signf(grab_point.z)) * grab_blend
	return Basis(Vector3.BACK, roll * 0.5) * Basis(Vector3.RIGHT, -pitch)


## Landing prediction: step the ballistic path
## and ray-test each segment against the level.
func _predict_landing(force: bool) -> void:
	if not force and int(air_time / SimMath.DT) % 4 != 0 and time_to_land < INF:
		time_to_land -= SimMath.DT
		return
	var space := skater.get_world_3d().direct_space_state
	var p := skater.board.deck().position - Vector3.UP * BoardSpec.LEVEL_GROUND_DECK_HEIGHT
	var v := skater.board.deck().linear_velocity
	var g := Vector3(0.0, -tuning.gravity, 0.0)
	var step := 1.0 / 30.0
	time_to_land = INF
	for i in 90:
		var t0 := i * step
		var t1 := t0 + step
		var a := p + v * t0 + g * (0.5 * t0 * t0)
		var b := p + v * t1 + g * (0.5 * t1 * t1)
		_ray.from = a
		_ray.to = b
		var hit := space.intersect_ray(_ray)
		if not hit.is_empty() and (i > 0 or v.y < 0.0):
			var fraction := a.distance_to(hit.position) / maxf(a.distance_to(b), 1e-5)
			time_to_land = t0 + step * fraction
			landing_point = hit.position
			return


## Auto-alignment: turn toward the nearer rolling direction so the
## wheels meet the ground along the line of travel.
func _assist_rate() -> float:
	var v := skater.board.deck().linear_velocity
	v.y = 0.0
	if v.length() < 0.5:
		return 0.0
	var travel := atan2(v.x, v.z)
	var board_heading := heading + _shuv_offset()
	var error := wrapf(travel - board_heading, -PI, PI)
	var reverse := wrapf(travel + PI - board_heading, -PI, PI)
	if absf(reverse) < absf(error):
		error = reverse
	return error / maxf(time_to_land, 0.032) * tuning.landing_align_strength


func _shuv_offset() -> float:
	if trick_key == "":
		return 0.0
	return shuv_turns * TAU * trick_progress * -stance_sign()


func _land() -> void:
	if skater.grind.try_enter():
		return
	airborne = false
	_disable_guide()
	var rider := skater.rider
	var deck := skater.board.deck()
	var normal := rider.ground_normal
	if trick_key != "" and trick_progress < 0.86:
		_bail("Didn't catch the board")
		return
	if grab != "":
		_bail("Still holding the grab")
		return
	if deck.basis.y.dot(normal) < 0.45:
		_bail("Landed on the deck")
		return
	var v := deck.linear_velocity - normal * deck.linear_velocity.dot(normal)
	var forward := deck.basis.z - normal * deck.basis.z.dot(normal)
	var angle := 0.0
	if v.length() > 0.5 and forward.length() > 0.1:
		angle = rad_to_deg(v.angle_to(forward))
		angle = minf(angle, 180.0 - angle)
	var limit := LinearCurve.evaluate(tuning.landable_angle, v.length())
	if angle > limit:
		_bail("Landed sideways (%.0f degrees)" % angle)
		return
	# A board that turned half a turn under the rider swaps which end is the nose.
	var rider_forward := skater.rider_frame.basis.z
	if skater.deck_effective().basis.z.dot(rider_forward) < 0.0:
		rider.facing_sign *= -1.0
	# Landed going backwards (a 180, 540...): ride away in the other stance.
	var rolling := v.length() > 0.3
	var backward := rolling and v.dot(skater.deck_effective().basis.z) < 0.0
	var name := _trick_name(backward if rolling else null)
	if backward:
		skater.switch_stance()
	trick_key = ""
	feet_off = 0.0
	_since_landing = 0.0
	_revert_armed = not _slide_held(0.5)
	if name != "":
		_message(name)
		trick_landed.emit(name)


## `backward`: whether the rider rolled away backwards, which settles an odd or
## even count of half turns (null when the board barely moves).
func _trick_name(backward: Variant = null) -> String:
	var parts: Array[String] = []
	var halves_exact := absf(rad_to_deg(spin_total)) / 180.0
	var halves := roundi(halves_exact)
	if backward != null and (halves % 2 == 1) != backward:
		# The assist finished the turn the other way: take the nearer count that fits.
		halves = halves + 1 if halves_exact > halves or halves == 0 else halves - 1
	var turns := halves * 180
	if fakie:
		parts.append("Fakie")
	elif riding_switch:
		parts.append("Switch")
	if turns >= 180:
		parts.append(("FS" if spin_total * stance_sign() > 0.0 else "BS") + " %d" % turns)
	if trick_key != "":
		var base: String = trick.name
		if late:
			base = "Late " + base
		if flip_turns_target >= 3.0:
			base = base.replace("Kickflip", "Triple Kickflip").replace("Heelflip", "Triple Heelflip")
		elif flip_turns_target >= 2.0:
			base = base.replace("Kickflip", "Double Kickflip").replace("Heelflip", "Double Heelflip")
		if not (grabbed_names.size() > 0 and (base == "Ollie" or base == "Nollie")):
			parts.append(base)
	for g in grabbed_names:
		parts.append(g)
	return " ".join(parts)


func _bail(reason: String) -> void:
	bail_timer = 0.0
	trick_key = ""
	grab = ""
	airborne = false
	_disable_guide()
	skater.rider.bail()
	skater.animator.start_ragdoll(skater.velocity())
	_message("Bail! " + reason)
	bailed.emit(reason)


## Respawn once the body has settled (eligible after
## 1.6 s, or settled; forced at the maximum time).
func ready_to_respawn() -> bool:
	if bail_timer < 0.0:
		return false
	var settled := skater.animator.is_ragdoll() and skater.animator.ragdoll_speed() < 0.4
	return bail_timer > 3.0 or (bail_timer > 1.6 and settled)


func _disable_guide() -> void:
	skater.board.guide_dynamics = [
		{"spring": 0.0, "damping": 0.0, "strength": 0.0, "type": ConstraintRow.DriveType.HARD},
		{"spring": 0.0, "damping": 0.0, "strength": 0.0, "type": ConstraintRow.DriveType.HARD},
	]


func _message(text: String) -> void:
	last_message = text
	last_message_time = clock
