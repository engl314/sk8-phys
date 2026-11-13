class_name RiderAnimator
extends Node3D

enum Stance { REGULAR, GOOFY }

## One arm, driven at the shoulder: lifted out to the side (raise), swung
## forward or back (swing) and bent at the elbow (bend), in radians. Each is
## held toward its target by a spring and pushed by `drive` (angular
## acceleration), so the arm moves as a limb with weight.
class Arm:
	var raise := MotionFilters.Spring.new(80.0, 14.0)
	var swing := MotionFilters.Spring.new(80.0, 14.0)
	var bend := MotionFilters.Spring.new(55.0, 8.5)

	## `target` and `drive`: raise, swing, bend.
	func update(target: Vector3, drive: Vector3, dt: float) -> void:
		raise.velocity += drive.x * dt
		swing.velocity += drive.y * dt
		bend.velocity += drive.z * dt
		raise.update(target.x, dt)
		swing.update(target.y, dt)
		bend.update(target.z, dt)
		raise.limit(0.0, 2.3)
		swing.limit(-1.1, 1.6)
		bend.limit(0.08, 2.2)

	func reset(target: Vector3) -> void:
		for i in 3:
			var spring: MotionFilters.Spring = [raise, swing, bend][i]
			spring.value = target[i]
			spring.velocity = 0.0


## One tick's working values, shared between the stages of step().
class Tick:
	## What the game says about this tick.
	var game: RiderInputs
	var dt := 1.0 / 60.0
	## The deck as the rider stands on it, the rider frame, and one in the other.
	var deck := Transform3D.IDENTITY
	var frame := Transform3D.IDENTITY
	var to_rig := Basis.IDENTITY
	var deck_in_rig := Transform3D.IDENTITY
	var face := Vector3.LEFT
	var front_left := true
	var grounded := true
	var grinding := false
	var airborne := false
	## Push: blend into the push pose, phase, 0..1 through the drive, heel lift
	## (negative: toes up, reaching for the plant).
	var push := 0.0
	var phase := RiderInputs.Push.NONE
	var stroke := 0.0
	var heel := 0.0
	## 0..1 round one whole push (lift, drive, recover), 0 when not pushing.
	var cycle := 0.0
	## How far behind the hips the push leg is: 0 at the plant, 1 where the foot
	## lets go of the ground, more as it trails behind, a little below 0 reaching ahead.
	var leg := 0.0
	## 0..1 standing still with the back foot down beside the board, and how
	## far the body is turned to the nose with that foot off the board (pushing
	## or standing).
	var stand := 0.0
	var open := 0.0
	## How much of the weight is over the foot on the ground: it goes there as
	## the foot comes down, the other way for a moment first, and past 1 before
	## it settles.
	var over := 0.0
	## 0..1..0 through a step off the board or back onto it.
	var step := 0.0
	## 0..1 how big the pushes are for the speed: short and upright setting off,
	## long and low at speed.
	var power := 0.0
	## 0..1 the push foot hanging from the leg behind, toes trailing.
	var trail := 0.0
	## The push foot is in the air: it gives to the leg's reach (planted, the hips do).
	var push_free := false
	## How far the pelvis has turned with the driving leg (radians about up).
	var drive := 0.0
	## The deck in the rig as the feet find it: after a shove-it the tail has
	## come round to the front, and either end will do to stand on.
	var board := Transform3D.IDENTITY
	## 0 = feet on the board, 1 = off it, held over where it will be caught.
	var free := 0.0
	## Ankles in deck space, and in the rig.
	var front_rest := Vector3.ZERO
	var back_rest := Vector3.ZERO
	var front_foot := Vector3.ZERO
	var back_foot := Vector3.ZERO
	var front_rig := Vector3.ZERO
	var back_rig := Vector3.ZERO
	var feet_mid := Vector3.ZERO
	## 0..1 as the popping foot snaps and as the sliding foot drags up the board.
	var snap := 0.0
	var drag := 0.0
	## Hip height the rider means to hold, and how far the load has pushed below it.
	var commanded := 0.8
	var compression := 0.0
	var hips_forward := Vector3.LEFT
	## The lean as the pelvis and the spine take it (the legs take all of it).
	var hips_tilt := Basis.IDENTITY
	var spine_tilt := Basis.IDENTITY
	var spine_up := Vector3.UP
	var breath := 0.0


const DECK_TOP := 0.0075
const ANKLE_HEIGHT := 0.075
## Hip height above the deck centre, standing and fully crouched.
const STAND_HEIGHT := 0.8
const CROUCH_HEIGHT := 0.53
const FRONT_FOOT_Z := 0.17
const BACK_FOOT_Z := -0.25
## Setting up a pop: the popping foot goes to the pocket of the tail (or nose),
## the other comes back toward the middle to slide from.
const SETUP_POP_FOOT := 0.085
const SETUP_SLIDE_FOOT := 0.08
## Pushing: the front foot over the front bolts; the push foot plants beside the
## board just behind it and drives back. PUSH_PLANT_Z to PUSH_END_Z and
## PUSH_MIN_STROKE are the stroke as the simulation's hip height counts it.
const PUSH_FRONT_Z := 0.2
const PUSH_SIDE := 0.19
const PUSH_PLANT_Z := 0.12
const PUSH_END_Z := -0.4
const PUSH_MIN_STROKE := 0.4
## The stroke the rider is seen to make grows with speed. Slow, it is short:
## planted at PUSH_PLANT_Z, let go at PUSH_RELEASE_Z, PUSH_LEAST_STROKE long
## even from a standstill. At full size the foot reaches PUSH_STRIDE_AHEAD
## further forward to plant and lets go PUSH_STRIDE_BEHIND further back.
const PUSH_RELEASE_Z := -0.25
const PUSH_LEAST_STROKE := 0.36
const PUSH_STRIDE_AHEAD := 0.08
const PUSH_STRIDE_BEHIND := 0.27
## Hips facing the nose while pushing (radians from side-on), and standing
## with the back foot down beside the board.
const PUSH_OPEN := 1.45
const STAND_OPEN := 1.25
## Stepping off the board and back on: the weight moves off the foot for this
## long before it lifts (s), and how high it is carried over the deck's edge.
const STEP_WAIT := 0.09
const STEP_DOWN_LIFT := 0.11
const STEP_UP_LIFT := 0.14
## Arm angles (raise out to the side, swing forward, elbow bend), radians,
## from hanging straight down (see _arm_frame).
## Standing still: hanging at the sides, nothing held.
const ARM_HANG := Vector3(0.12, 0.04, 0.22)
## Rolling along: still low, the elbows soft and the hands a little off the
## hips, the front arm slightly ahead.
const ARM_ROLL := Vector3(0.2, 0.12, 0.42)
const ARM_ROLL_FRONT := Vector3(0.23, 0.26, 0.5)
## Balancing for a while (a manual, a rail, a long time in the air): out from
## the body, the front arm toward the nose and higher, the back one toward the
## tail. Only ever taken in part (see _update_arms).
const ARM_BALANCE_FRONT := Vector3(1.05, 0.5, 0.8)
const ARM_BALANCE_BACK := Vector3(0.9, -0.25, 0.65)
## The least an arm is held out from the side of the body (radians).
const ARM_CLEAR := 0.05
## Where an arm's weight sits from the shoulder, and the trunk's from the hips (m).
const ARM_PENDULUM := 0.34
const TRUNK_PENDULUM := 0.45
## The legs never quite lock straight.
const LEG_REACH := 0.985

## The rider's own stance.
@export var natural_stance := Stance.REGULAR
## The stance they're riding in now: landing a 180 swaps it.
var stance := Stance.REGULAR
## How the body moves (weight, follow-through). Presentation only.
var feel: RiderFeel
## What the game says about this tick: fill it in, then call step(). It is
## everything the rig knows about the board and the game (see RiderInputs).
var inputs := RiderInputs.new()

var skeleton: Skeleton3D
var solver: RiderPoseSolver
var figure := BlockFigure.new()
var pose := RiderPose.new()
var motion := RiderMotion.new()

# --- What the simulation reads -------------------------------------------------
## Crouch fraction 0 (standing) .. 1 (deep): filtered input, then velocity and
## acceleration caps per tick.
var crouch := MotionFilters.Follower.new(0.065, 0.011)
## The landing compression, kept for the hip height the simulation reads.
var landing := MotionFilters.Spring.new(60.0, 6.0)
var landing_releasing := false
## A turn lean and torso bump: unseen now, but part of the hip
## height the pump and the pop were tuned against.
var _sim_lean := MotionFilters.Follower.new(0.03, 0.0035)
var _sim_torso := MotionFilters.SpringVector.new(110.0, 12.0)
var _sim_velocity := Vector3.ZERO
var _sim_acceleration := Vector3.ZERO
var _sim_height := 0.9

# --- The visible body ----------------------------------------------------------
## How far the pelvis sits from the height the rider means to hold (m): pushed
## down by load and landings, thrown up by the pop, on the spring of the legs.
var sag := MotionFilters.Spring.new(100.0, 11.0)
## 1 just after a landing, while the legs give softly to absorb it.
var absorb := 0.0
## Hip height the rider is holding: the crouch, as fast as legs can follow it.
var _commanded := STAND_HEIGHT
## Lean that keeps the rider balanced (radians): across the board, into a
## carve, and along it, into a push and back against the brakes.
var lean := MotionFilters.SecondOrder.new(1.7, 0.6, -0.35)
var pitch := MotionFilters.SecondOrder.new(1.7, 0.6, -0.35)
## How far the hips have been left behind (or carried past) as the board turns.
var hips_swing := MotionFilters.Spring.new(270.0, 20.0)
## Chest orientation in the world, following the hips.
var chest := MotionFilters.SpringRotation.new(2.8, 0.6)
var push_blend := MotionFilters.Follower.new(0.07, 0.012)
## Standing still with the back foot down beside the board. Seen only:
## nothing the simulation reads comes from any of it. The body turns to the
## nose (0..1, a little past and back), and the weight goes over to the foot
## on the ground: toward the other foot first, to free the one that steps.
var _stand := MotionFilters.SecondOrder.new(1.8, 0.75, 0.0)
var _stand_weight := MotionFilters.SecondOrder.new(1.5, 0.7, -0.6)
## Seconds the board has been at rest, whether the rider wants the foot down,
## and whether it has reached the ground.
var _still_time := 0.0
var _foot_down := false
var _foot_grounded := false
## The step under way (1 down to the ground, -1 back up onto the tail, 0
## none), how long it has been going and where the foot set off from.
var _stepping := 0
var _step_time := 0.0
var _step_from := Vector3.ZERO
## Weight over the front foot for a push: it gets there before the foot lifts.
var push_weight := MotionFilters.SecondOrder.new(3.2, 0.8, 0.6)
## 0..1 feet shifted to set up a pop.
var setup := MotionFilters.Follower.new(0.14, 0.035)
## The push foot swinging through the air (deck space): it leaves the ground
## still moving back, and carries that through before it comes forward.
var _swing := MotionFilters.SecondOrderVector.new(4.2, 0.8, 0.5)
## The push was cut short: the foot is still on its way back to the board.
var _returning := false
## Where the swinging foot sets off from (behind the hip, where the leg
## carried it after the drive), whether this swing ran straight on from the
## last push, and whether the driving foot has let go of the ground.
var _swing_from := Vector3.ZERO
var _swing_through := false
var _released := false
## How big the pushes are for the speed (see Tick.power), the size this stroke
## was planted with, and where it was planted (world).
var _push_power := 0.0
var _stride := 0.0
var _plant_anchor := Vector3.ZERO
## The pelvis going back over the board as the leg drives behind (m): it has
## weight, so it follows the leg rather than moving with it.
var _push_shift := MotionFilters.SecondOrder.new(3.0, 0.9, 0.0)
## Push foot pointed down from level (radians): heel up, toes trailing.
var _foot_point := 0.0
## Where in the push cycle the body is (see Tick.cycle), and where it was as
## the leg began to swing forward: a glide between pushes holds it there.
var _cycle := 0.0
var _recover_cycle := 0.0
## How fast the push leg is moving back (leg lengths per second), so the arms
## can swing with it rather than after it.
var _leg_rate := 0.0
## 0..1 feet off a board that is turning under them, and each foot's own
## flight over it (rig space).
var _free := 0.0
var _wanted_free := 0.0
var _free_front := MotionFilters.SecondOrderVector.new(5.5, 0.75, 0.8)
var _free_back := MotionFilters.SecondOrderVector.new(5.5, 0.75, 0.8)
## How fast the held hip height is changing, for the weight it throws on the legs.
var _commanded_speed := 0.0
var arm_l := Arm.new()
var arm_r := Arm.new()
## 0..1 how much of the balancing pose the arms are holding (a manual, a rail,
## a long air): it takes a moment to come up and to go.
var _arm_hold := 0.0
## What the trailing arm is asked for: the same things as the leading one, a
## moment later.
var _trail_target := ARM_HANG
## Seconds since the last pop, how big it was (0..1) and whether it popped a
## trick, for the arms' swing with it.
var _pop_age := 9.0
var _pop_size := 0.0
## Gestures made so far (pops, landings): each takes its small differences from this.
var _gestures := 0
## Which way each hand points (left, right), following its forearm loosely.
var _hand_dir := [Vector3.DOWN, Vector3.DOWN]
## The lean the rider is balancing toward (across, along), which the body
## follows a moment later and the arms answer first.
var _lean_target := 0.0
var _pitch_target := 0.0
## The small corrections of balancing just now (across, along), radians.
var _sway := Vector2.ZERO
var head_forward := Vector3.BACK

var _tick := Tick.new()
var _clock := 0.0
var _push_anchor := Vector3.ZERO
## Deck-space push foot.
var _push_foot := Vector3.ZERO
var _last_push_phase := RiderInputs.Push.NONE
## Deck-space slide along the nose that carries the feet from where they stood
## before a stance swap to the new stance's places.
var _stance_shift := 0.0
## World position, velocity and acceleration of each shoulder (left, right).
var _shoulder := [Vector3.ZERO, Vector3.ZERO]
var _shoulder_velocity := [Vector3.ZERO, Vector3.ZERO]
var _shoulder_acceleration := [Vector3.ZERO, Vector3.ZERO]
var _shoulders_primed := false
## The rig frame jumped (a stance swap): don't interpolate across it.
var _snap := false
var _initialised := false
## Active while bailing: the ragdoll drives the skeleton in world space.
var ragdoll: VerletRagdoll


func _init() -> void:
	feel = load(RiderFeel.SAVE_PATH) if ResourceLoader.exists(RiderFeel.SAVE_PATH) else RiderFeel.new()


func _ready() -> void:
	top_level = true
	skeleton = RiderSkeleton.build()
	add_child(skeleton)
	solver = RiderPoseSolver.new(skeleton)
	figure.name = "BlockFigure"
	add_child(figure)
	figure.setup(skeleton)


## Facing direction in deck space: regular riders face the deck's right (-X).
func facing() -> Vector3:
	return Vector3(-1.0 if stance == Stance.REGULAR else 1.0, 0.0, 0.0)


func is_switch() -> bool:
	return stance != natural_stance


func reset_stance() -> void:
	stance = natural_stance
	_stance_shift = 0.0


## Ride the other way round. The controller turns the rig frame half a turn at
## the same time, so the body stays where it is: the rig-space filters are
## turned with it (the chest lives in the world and needs nothing), and the feet
## slide the few centimetres between the two stances' places instead of jumping.
func swap_stance() -> void:
	stance = Stance.GOOFY if stance == Stance.REGULAR else Stance.REGULAR
	lean.flip()
	pitch.flip()
	_sim_lean.value = -_sim_lean.value
	_sim_lean.velocity = -_sim_lean.velocity
	_sim_torso.value *= Vector3(-1.0, 1.0, -1.0)
	_sim_torso.velocity *= Vector3(-1.0, 1.0, -1.0)
	_stance_shift = -(FRONT_FOOT_Z + BACK_FOOT_Z)
	_last_push_phase = RiderInputs.Push.NONE
	_snap = true


## Hand the body to the ragdoll, moving at `velocity` (world) and tumbling forward.
func start_ragdoll(velocity: Vector3) -> void:
	ragdoll = VerletRagdoll.new()
	ragdoll.gravity = inputs.gravity
	var forward := velocity.normalized() if velocity.length() > 0.5 else inputs.frame.basis * facing()
	var tumble := Vector3.UP.cross(forward) * clampf(velocity.length() * 1.2, 1.5, 7.0)
	ragdoll.start(skeleton, velocity * 0.85 + Vector3.UP * 0.6, tumble)


func is_ragdoll() -> bool:
	return ragdoll != null


func ragdoll_hips() -> Vector3:
	return ragdoll.position.Hips if ragdoll else global_position


## Mean speed of the ragdoll's joints (0 when not bailing).
func ragdoll_speed() -> float:
	return ragdoll.speed() if ragdoll else 0.0


func stop_ragdoll() -> void:
	ragdoll = null
	_initialised = false
	reset_physics_interpolation()


## Hip height above the deck centre the simulation works with (the pop's and
## the pump's centre-of-mass height): the crouch, the landing compression,
## turn lean and bump, without the visible body's own motion.
func hip_height() -> float:
	return _sim_height


## The pop: the legs snap straight and the arms start up; the air tuck then
## pulls the knees up.
func pop(_strength: float) -> void:
	# How big a pop it is, for the arms: out of a deep crouch they are thrown
	# up with it, off a quick tap they barely move.
	_pop_size = clampf(0.25 + crouch.value, 0.25, 1.0)
	_pop_age = 0.0
	_gestures += 1
	crouch.value *= 0.3
	crouch.velocity = 0.0
	landing.value = 0.0
	landing.velocity = 0.0
	# The board was launched by hand: that is the legs pushing, not a jolt to absorb.
	motion.skip()
	sag.velocity = maxf(sag.velocity, feel.pop_extension)
	absorb = 0.0
	arm_l.raise.kick(feel.pop_arm_throw * _pop_size * 0.5)
	arm_r.raise.kick(feel.pop_arm_throw * _pop_size * 0.5)


func step(dt: float) -> void:
	if ragdoll:
		ragdoll.step(get_world_3d().direct_space_state, dt)
		if global_transform != Transform3D.IDENTITY:
			global_transform = Transform3D.IDENTITY
			reset_physics_interpolation()
		solver.apply_positions(ragdoll.position)
		figure.sync()
		return
	# The rig works in the rider frame: the deck on the ground, an upright frame
	# on the rider's heading in the air (so the board can pitch and flip under the
	# feet). Feet are placed in deck space and carried into the rider frame.
	var t := _tick
	t.game = inputs
	t.dt = dt
	t.deck = inputs.deck
	t.frame = inputs.frame
	t.to_rig = t.frame.basis.transposed()
	t.deck_in_rig = t.frame.affine_inverse() * t.deck
	t.face = facing()
	t.front_left = stance == Stance.REGULAR
	t.grounded = inputs.grounded()
	t.grinding = inputs.state == RiderInputs.State.GRIND
	t.airborne = not t.grounded and not t.grinding
	global_transform = t.frame
	if _snap:
		reset_physics_interpolation()
		_snap = false
	_stance_shift *= exp(-12.0 * dt)
	_clock += dt
	_apply_feel()
	if not _initialised:
		_reset_body()
		_sim_velocity = inputs.velocity
	motion.update(inputs, dt)

	_update_sim_posture(t)
	_update_feet(t)
	_update_sim_height(t)
	_update_balance(t)
	_update_height(t)
	_update_hips(t)
	_update_chest(t)
	_update_head(t)
	_pose_feet(t)
	_update_arms(t)

	solver.apply(pose)
	figure.sync()


## Live tuning: the filters take their constants from the feel every tick.
func _apply_feel() -> void:
	lean.configure(feel.balance_frequency, feel.balance_damping, feel.balance_response)
	pitch.configure(feel.balance_frequency, feel.balance_damping, feel.balance_response)
	var hips := TAU * feel.hips_frequency
	hips_swing.stiffness = hips * hips
	hips_swing.damping = 2.0 * feel.hips_damping * hips
	chest.configure(feel.chest_frequency, feel.chest_damping)


## Start (or restart after a bail) standing still: nothing carries over.
func _reset_body() -> void:
	_initialised = true
	motion.reset()
	arm_l.reset(ARM_HANG)
	arm_r.reset(ARM_HANG)
	_arm_hold = 0.0
	_trail_target = ARM_HANG
	_pop_age = 9.0
	_pop_size = 0.0
	_gestures = 0
	_hand_dir = [Vector3.DOWN, Vector3.DOWN]
	_lean_target = 0.0
	_pitch_target = 0.0
	sag.value = 0.0
	sag.velocity = 0.0
	absorb = 0.0
	_commanded = lerpf(STAND_HEIGHT, CROUCH_HEIGHT, crouch.value)
	lean.reset(0.0)
	pitch.reset(0.0)
	hips_swing.value = 0.0
	hips_swing.velocity = 0.0
	chest.release()
	push_weight.reset(0.0)
	_stand.reset(0.0)
	_stand_weight.reset(0.0)
	_still_time = 0.0
	_foot_down = false
	_foot_grounded = false
	_stepping = 0
	_step_time = 0.0
	setup.reset(0.0)
	_shoulders_primed = false
	_free = 0.0
	_wanted_free = 0.0
	_returning = false
	_released = false
	_leg_rate = 0.0
	_push_power = 0.0
	_stride = 0.0
	_push_shift.reset(0.0)
	_foot_point = 0.0
	_commanded_speed = 0.0


# --- What the simulation reads ---------------------------------------------------

## The crouch controller and the landing compression, as the simulation was
## tuned with them; the visible body is built on top of them below.
func _update_sim_posture(t: Tick) -> void:
	var turn := absf(t.game.steer)
	var tuck := clampf((motion.speed - 5.0) / 4.0, 0.0, 1.0) * 0.22
	var target := maxf(t.game.crouch, maxf(turn * 0.18, tuck))
	# The support knee bends so the push foot can reach the ground.
	target = maxf(target, push_blend.value * 0.45)
	if t.grinding:
		target = maxf(target, 0.42)
	elif not t.grounded:
		# Tuck the knees up after the pop, then reach for the ground just before landing.
		target = 0.66 if t.game.air_time < 0.34 else 0.52
		target = maxf(target, t.game.feet_off * 0.9)
		target = maxf(target, t.game.grab_blend * 0.92)
		if t.game.time_to_land < 0.2 and not t.game.grabbing:
			target = minf(target, 0.25)
	crouch.update(clampf(target, 0.0, 1.0))

	# Landing compression.
	if t.game.just_landed:
		landing.velocity = -clampf(motion.impact_speed, 0.0, 8.0) * 0.55
		landing_releasing = false
	if not landing_releasing:
		landing.update(0.0, t.dt)
		if landing.velocity >= 0.0 and landing.value < 0.0:
			landing_releasing = true
	else:
		# Ground landings never spring upward: ease out over ~15 frames.
		landing.value *= pow(14.0 / 15.0, 2.0)
		landing.velocity = 0.0
	landing.value = clampf(landing.value, -0.32, 0.0)

	# Lean into the turn, and torso inertia.
	var lean_target := 0.0
	if t.grinding:
		lean_target = clampf(t.game.grind_lean * 1.4, -0.5, 0.5)
	elif t.grounded:
		var lateral := motion.speed * t.game.angular_velocity.dot(t.frame.basis.y)
		lean_target = clampf(atan2(lateral, 9.8) * 0.85 + t.game.steer * 0.1, -0.55, 0.55)
	_sim_lean.update(lean_target)
	var velocity := t.game.velocity
	_sim_acceleration = _sim_acceleration.lerp((velocity - _sim_velocity) / t.dt, 0.35)
	_sim_velocity = velocity
	var bump := t.to_rig * _sim_acceleration
	bump = Vector3(-bump.x * 0.008, -bump.y * 0.004 if t.grounded else 0.0, -bump.z * 0.010)
	_sim_torso.update(bump.limit_length(0.09), t.dt)


## The hip height those controllers give, as the rig they were tuned with placed it.
func _update_sim_height(t: Tick) -> void:
	var face := t.face
	var front := Vector3(face.x * 0.03, DECK_TOP + ANKLE_HEIGHT, FRONT_FOOT_Z + t.game.front_foot_slide + _stance_shift)
	front = front.lerp(Vector3(-face.x * 0.02, DECK_TOP + ANKLE_HEIGHT, PUSH_FRONT_Z), t.push)
	var back := Vector3(face.x * 0.02, DECK_TOP + ANKLE_HEIGHT, BACK_FOOT_Z + _stance_shift)
	var mid := t.deck_in_rig * ((front + back) * 0.5)
	var height := lerpf(STAND_HEIGHT, CROUCH_HEIGHT, crouch.value) + landing.value + _sim_torso.value.y
	height -= t.push * 0.06 * sin(t.stroke * PI)
	var across := lerpf(-face.x * 0.06, face.x * 0.03, t.push) + _sim_torso.value.x * 0.6 - mid.x
	_sim_height = DECK_TOP - across * sin(_sim_lean.value) + (height - DECK_TOP) * cos(_sim_lean.value)


# --- Feet --------------------------------------------------------------------------

## Where the feet go, in deck space: the riding stance, shifted to set up a pop,
## and the push cycle. Pushing turns the rider to face the nose: the front foot
## swivels to point down the board over the front bolts and the back foot
## reaches forward beside the board, plants and drives back while the support
## knee gives. With another push to come it swings straight to the next plant;
## after the last one it steps back onto the tail.
func _update_feet(t: Tick) -> void:
	var face := t.face
	var nose := Vector3.BACK
	push_blend.update(1.0 if t.game.pushing() else 0.0)
	push_weight.update(1.0 if t.game.pushing() else 0.0, t.dt)
	t.push = clampf(push_blend.value, 0.0, 1.0)
	t.phase = t.game.push_phase
	# Standing still, nobody balances on the board: after a moment at rest the
	# back foot goes down beside it. It comes back up to crouch for a pop, or
	# once the board is rolling; a push starts straight from it.
	# (Only once the board has all but stopped: a foot down on a board still
	# rolling would be dragged along the ground.)
	var at_rest: bool = t.grounded and t.game.state == RiderInputs.State.GROUND and t.game.manual_time <= 0.0 \
		and motion.speed < (0.5 if _foot_down else 0.15) and t.deck.basis.y.y > 0.97
	_still_time = _still_time + t.dt if at_rest else 0.0
	var down: bool = feel.stand_foot_down and _still_time > feel.stand_delay \
		and not t.game.pushing() and not t.game.crouch_held
	if down != _foot_down:
		_foot_down = down
		_foot_grounded = false
		_step_time = 0.0
		_step_from = _push_foot
		if down:
			_stepping = 1
		elif t.game.pushing():
			# Pushing off from the standing foot: the leg loads before it drives.
			_stepping = 0
			sag.kick(-feel.stand_give * 0.7)
		else:
			_stepping = -1
	# The body turns with the leg that steps, not before it: the weight moves
	# first (below), then the foot lifts and the hips go round with it.
	var turned := _foot_down
	if _stepping != 0 and _step_time < STEP_WAIT:
		turned = not _foot_down
	_stand.update(1.0 if turned else 0.0, t.dt)
	t.stand = clampf(_stand.value, 0.0, 1.0)
	t.open = maxf(t.push, t.stand)
	t.over = _stand_weight.update(1.0 if _foot_down else 0.0, t.dt)
	t.step = 0.0
	# Pushes are sized to the speed: short and upright setting off, long and low
	# once the ground is going by fast.
	var size := clampf((absf(t.game.forward_speed) - 0.5) / maxf(feel.push_full_speed - 0.5, 0.1), 0.0, 1.0)
	_push_power = lerpf(_push_power, size, 1.0 - exp(-5.0 * t.dt))
	t.power = _push_power

	# Setting up: the popping foot to the pocket, the other back to slide from.
	# By the top of the jump both are over the bolts again for the landing.
	var popped: bool = t.game.airborne and t.game.trick_active and not t.game.trick_late
	var setting_up: bool = t.grounded and t.game.crouch_held and not t.game.pushing()
	setup.update(1.0 if setting_up or popped and t.game.air_time < 0.16 else 0.0)
	var shifted := clampf(setup.value, 0.0, 1.0) * feel.setup_stance
	var nollie: bool = t.game.nollie if t.game.airborne else t.game.nollie_held
	var front_z := FRONT_FOOT_Z
	var back_z := BACK_FOOT_Z
	var slide: float = t.game.front_foot_slide * (1.0 + 1.1 * feel.setup_stance)
	if nollie:
		front_z += (SETUP_POP_FOOT + 0.05) * shifted
		back_z += SETUP_SLIDE_FOOT * shifted - slide
	else:
		front_z += -SETUP_SLIDE_FOOT * shifted + slide
		back_z -= SETUP_POP_FOOT * shifted
	t.snap = 0.0
	t.drag = 0.0
	if popped:
		t.snap = (1.0 - smoothstep(0.03, 0.15, t.game.air_time)) * feel.foot_articulation
		t.drag = clampf(t.game.front_foot_slide / 0.08, 0.0, 1.0) * feel.foot_articulation

	var shift := Vector3(0.0, 0.0, _stance_shift)
	t.front_rest = Vector3(face.x * 0.03, _deck_surface(front_z) + ANKLE_HEIGHT, front_z) + shift
	t.back_rest = Vector3(face.x * 0.02, _deck_surface(back_z) + ANKLE_HEIGHT, back_z) + shift
	t.front_foot = t.front_rest.lerp(Vector3(-face.x * 0.02, DECK_TOP + ANKLE_HEIGHT, PUSH_FRONT_Z), t.open)
	_update_push_foot(t)
	_place_feet(t)


## The push foot through one push, in deck space. It plants and drives back
## fixed in the world while the board rolls on, and lets go of the ground where
## the stroke (or the leg) runs out, still moving back: the leg carries it on
## behind the hip and up before the knee brings it forward. With another push
## to come, that swing runs straight through to the next plant: out a little
## past it, then back down onto it already moving with the ground. After the
## last push it steps up onto the tail. The stroke is sized to the speed (see
## Tick.power): short beside the front foot when slow; at speed the foot reaches
## ahead to plant, lets go further behind and trails higher. Only the planted
## part is exact; the rest is swung (see _swing), so the foot's speed never jumps.
func _update_push_foot(t: Tick) -> void:
	var ground_y := -t.game.deck_ride_height + ANKLE_HEIGHT
	var side := t.face.x * PUSH_SIDE
	# The next plant is sized to the speed now; a stroke under way keeps the
	# size it was planted with.
	var plant := Vector3(side, ground_y, PUSH_PLANT_Z + PUSH_STRIDE_AHEAD * t.power * feel.push_stride)
	var progress := clampf(t.game.push_progress, 0.0, 1.0)
	var reach_time: float = t.game.push_reach_time
	var drive_time: float = t.game.push_drive_time
	var swing_time: float = t.game.push_swing_time
	var whole := reach_time + drive_time + swing_time
	if t.phase != _last_push_phase:
		match t.phase:
			RiderInputs.Push.REACH:
				# Straight on from the recovery, or a fresh start off the tail.
				_swing_through = _last_push_phase == RiderInputs.Push.SWING
				if not _swing_through:
					_swing_from = _push_foot
			RiderInputs.Push.DRIVE:
				# Where the simulation counts its stroke from, and where the foot
				# is seen to come down.
				_push_anchor = t.deck * Vector3(side, ground_y, PUSH_PLANT_Z)
				_plant_anchor = t.deck * plant
				_stride = t.power * feel.push_stride
				_released = false
			RiderInputs.Push.HANG:
				if not _released:
					_let_go(t, side, ground_y)
			RiderInputs.Push.SWING:
				if not _released:
					_let_go(t, side, ground_y)
				_recover_cycle = _cycle if _last_push_phase == RiderInputs.Push.HANG else (reach_time + drive_time) / whole
			RiderInputs.Push.NONE:
				_returning = _stepping == 0 and _push_foot.distance_to(t.back_rest) > 0.02
				_swing.retarget(t.back_rest)
		if t.phase != RiderInputs.Push.NONE:
			# A push takes the foot from wherever a step had got it to.
			_stepping = 0
	_last_push_phase = t.phase
	t.stroke = 0.0
	t.heel = 0.0
	t.cycle = 0.0
	t.trail = 0.0
	t.push_free = t.phase != RiderInputs.Push.NONE or _returning
	var speed := absf(t.game.forward_speed)
	var from_z := PUSH_PLANT_Z + PUSH_STRIDE_AHEAD * _stride
	var end_z := PUSH_RELEASE_Z - PUSH_STRIDE_BEHIND * _stride
	var target := t.back_rest
	# How much of the target is taken as it is, rather than swung toward, and
	# how briskly it is swung: the swing forward is quick, the leg carrying on
	# behind after the drive is slower and heavier.
	var exact := 1.0
	var brisk := 1.0
	match t.phase:
		RiderInputs.Push.NONE:
			# Where the foot stands on the ground: where a push would start from.
			var spot := Vector3(side, ground_y, PUSH_PLANT_Z)
			if _stepping != 0:
				# A step, down beside the board or back up onto the tail. The
				# weight comes off the foot first; then it is carried over the
				# deck's edge and set down gently, the heel leaving last and the
				# toes hanging on the way.
				_step_time += t.dt
				var time := feel.stand_step_time if _stepping > 0 else feel.stand_step_up_time
				var u := clampf((_step_time - STEP_WAIT) / maxf(time, 0.05), 0.0, 1.0)
				target = _step_path(_step_from, spot if _stepping > 0 else t.back_rest, u,
					STEP_DOWN_LIFT if _stepping > 0 else STEP_UP_LIFT)
				t.step = sin(PI * u)
				t.heel = 0.6 * t.step
				_returning = false
				if u >= 1.0:
					if _stepping > 0:
						_foot_grounded = true
						# The weight comes down onto it: the knee gives, and
						# the body carries on forward a little before it settles.
						sag.kick(-feel.stand_give)
						pitch.kick(0.3)
					_stepping = 0
			elif _foot_down:
				target = spot
				t.push_free = false
			elif _returning:
				exact = 0.0
			if _stepping != 0:
				t.push_free = true
		RiderInputs.Push.REACH:
			t.cycle = progress * reach_time / whole
			var along := progress
			var time := reach_time
			if _swing_through:
				time += swing_time
				along = (swing_time + progress * reach_time) / time
			target = _swing_to_plant(_swing_from, plant, along, speed, time)
			t.heel = -0.35 * sin(PI * progress)
			# Onto the plant itself by the time it lands (a swing running through
			# from the last push is already most of the way there).
			exact = smoothstep(0.62, 0.9, along) if _swing_through else smoothstep(0.5, 0.85, along)
		RiderInputs.Push.DRIVE:
			t.cycle = (reach_time + progress * drive_time) / whole
			# The stroke as the simulation's hip height has always counted it.
			var counted := (t.deck.affine_inverse() * _push_anchor).z
			counted = maxf(minf(counted, PUSH_PLANT_Z - PUSH_MIN_STROKE * smoothstep(0.0, 1.0, progress)), PUSH_END_Z)
			t.stroke = (PUSH_PLANT_Z - counted) / (PUSH_PLANT_Z - PUSH_END_Z)
			if not _released:
				# Planted in the world while the board rolls on, but always a short
				# stroke at least. The foot keeps its speed to the end of the drive
				# rather than easing to a stop.
				var anchored := t.deck.affine_inverse() * _plant_anchor
				var least := PUSH_LEAST_STROKE + 0.14 * _stride
				var z := minf(anchored.z, from_z - least * pow(progress, 1.5))
				# Up onto the ball of the foot as the leg goes behind.
				t.heel = clampf((from_z - z) / (from_z - end_z) * 1.4 - 0.5, 0.0, 1.0)
				target = Vector3(side, ground_y + t.heel * 0.07, z)
				# It lets go where the stroke ends, or sooner if the leg runs out.
				var hip := _push_hip(t)
				var spent := z < hip.z - 0.2 and hip.distance_to(target) > solver.leg_length() * LEG_REACH
				if z < end_z or spent:
					_let_go(t, side, ground_y)
				else:
					t.push_free = false
			if _released:
				# Toes last off the ground; the leg carries on back and up, swinging
				# from the hip wherever that goes.
				_swing_from = _trail_point(t, side, ground_y)
				target = _swing_from
				t.heel = 1.0
				t.trail = 1.0
				exact = 0.0
				brisk = 0.0
		RiderInputs.Push.HANG:
			# Gliding between pushes at speed: the leg stays behind where the
			# drive left it, hanging from the hip and easing down a little, and
			# the body holds its lean, coming up only slightly, until the next
			# push is due.
			var settled := smoothstep(0.0, 1.0, progress) * clampf(t.game.push_hang / 0.3, 0.0, 1.0)
			t.cycle = (reach_time + drive_time) / whole + 0.06 * settled
			_swing_from = _trail_point(t, side, ground_y, 1.0 - 0.12 * settled)
			target = _swing_from
			t.heel = 1.0
			t.trail = 1.0
			exact = 0.0
			brisk = 0.0
		RiderInputs.Push.SWING:
			t.cycle = lerpf(_recover_cycle, 1.0, progress)
			if t.game.push_again:
				# The leg hangs behind a moment, then the knee swings it through
				# toward the next plant.
				var time := swing_time + reach_time
				var along := progress * swing_time / time
				target = _swing_to_plant(_swing_from, plant, along, speed, time)
				t.heel = 1.0 - smoothstep(0.0, 0.5, along)
				t.trail = 1.0 - smoothstep(0.25, 0.6, along)
				brisk = smoothstep(0.0, 0.35, along)
				exact = 0.0
			else:
				# Back up onto the tail.
				var e := smoothstep(0.0, 1.0, progress)
				target = _swing_from.lerp(t.back_rest, e) + Vector3.UP * sin(progress * PI) * 0.15
				t.heel = 1.0 - e
				t.trail = 1.0 - smoothstep(0.1, 0.6, progress)
				brisk = smoothstep(0.0, 0.4, progress)
				exact = smoothstep(0.6, 1.0, progress)
	_swing.configure(lerpf(3.4, 4.2, brisk), lerpf(0.9, 0.8, brisk), 0.5 * brisk)
	if exact >= 1.0:
		# Planted or at rest. Whatever swing comes next starts from here, with the
		# speed the ground gave the foot.
		var moving := (target - _push_foot) / t.dt if t.phase == RiderInputs.Push.DRIVE else Vector3.ZERO
		_swing.place(target, moving.limit_length(3.2 + 1.4 * _stride))
		t.back_foot = target
	else:
		var swung := _swing.update(target, t.dt)
		# Not through the ground beside the board, nor through the deck over it.
		var floor_y := ground_y if absf(swung.x) > t.game.deck_width * 0.5 + 0.03 else DECK_TOP + ANKLE_HEIGHT
		if swung.y < floor_y:
			swung.y = floor_y
			_swing.value.y = floor_y
			_swing.velocity.y = maxf(_swing.velocity.y, 0.0)
		t.back_foot = swung.lerp(target, exact)
		if t.phase == RiderInputs.Push.NONE and swung.distance_to(target) < 0.006 and _swing.velocity.length() < 0.15:
			_returning = false
	_push_foot = t.back_foot
	_cycle = t.cycle
	var pushing := t.phase != RiderInputs.Push.NONE or _returning
	var leg := clampf((from_z - t.back_foot.z) / (from_z - end_z), -0.3, 1.6) if pushing else 0.0
	_leg_rate = lerpf(_leg_rate, (leg - t.leg) / t.dt, 0.4)
	t.leg = leg


## The driving foot leaves the ground. From here the leg carries it on back and
## up behind the hip; the swing forward starts from there.
func _let_go(t: Tick, side: float, ground_y: float) -> void:
	_released = true
	_swing_from = _trail_point(t, side, ground_y)
	_swing_from.z = minf(_swing_from.z, _push_foot.z - 0.03)
	_swing.retarget(_swing_from)


## Where the leg, nearly straight, carries the foot behind the hip after the
## drive: further back and higher the bigger the push. `ease` below 1 lets it
## hang lower.
func _trail_point(t: Tick, side: float, ground_y: float, ease := 1.0) -> Vector3:
	var hip := _push_hip(t)
	var angle := (0.45 + (0.15 + 0.48 * _stride) * feel.push_follow_through) * ease
	var length := solver.leg_length() * 0.97
	return Vector3(side, maxf(hip.y - cos(angle) * length, ground_y + 0.04), hip.z - sin(angle) * length)


## The push leg's hip joint in deck space, as the body was last posed.
func _push_hip(t: Tick) -> Vector3:
	return t.deck_in_rig.affine_inverse() * solver.hip_joint(pose.hips, not t.front_left)


## Where a stepping foot is, `u` 0..1 of the way from one place to another:
## eased away and eased in, carried `lift` high in the middle, leaving and
## arriving with no speed, so it is picked up and set down rather than dropped.
static func _step_path(from: Vector3, to: Vector3, u: float, lift: float) -> Vector3:
	# (Eased so that it is slow for longer at both ends than a plain ease.)
	var at := from.lerp(to, u * u * u * (u * (u * 6.0 - 15.0) + 10.0))
	at.y += lift * pow(sin(PI * u), 2.0)
	return at


## Where a foot swinging to the plant is, `along` 0..1 of the way through a
## swing lasting `time`: down from where the leg trailed and through low over
## the ground, forward and out past the plant, then back onto it at the speed
## of the ground, so it lands already moving with it.
static func _swing_to_plant(from: Vector3, plant: Vector3, along: float, ground_speed: float, time: float) -> Vector3:
	const TURN := 0.72
	var reach := clampf(ground_speed * (1.0 - TURN) * 0.5 * time, 0.0, 0.12)
	var out := smoothstep(0.0, TURN, along)
	var at := from.lerp(plant + Vector3.BACK * reach, out)
	if along > TURN:
		var back := (along - TURN) / (1.0 - TURN)
		at.z = plant.z + reach * (1.0 - back * back)
	# A foot that starts low is lifted clear of the ground; one already high
	# behind only has to come down.
	var high := maxf(from.y - plant.y, 0.0)
	var apart := from.distance_to(plant)
	# (A foot already standing where the push starts stays down.)
	var clear := clampf(apart / 0.5, 0.35, 1.0) * 0.12 * (1.0 - clampf(high / 0.2, 0.0, 0.6)) * smoothstep(0.02, 0.12, apart)
	at.y = plant.y + high * (1.0 - smoothstep(0.0, 0.6, along)) + clear * sin(PI * along)
	return at


## Carry the feet into the rig. On the board they follow it. While a trick
## turns the board under them they don't: they lift clear and hold their place
## over where it will come back (the kicking foot flicks out off its edge
## first), and come down onto it as it comes round to something they can stand
## on. That is judged by the board, not by the clock, and either end will do:
## after a shove-it the tail has become the nose.
func _place_feet(t: Tick) -> void:
	var face := t.face
	var nose := Vector3.BACK
	t.board = t.deck_in_rig
	var want := 0.0
	if t.game.airborne:
		if t.board.basis.z.z < 0.0:
			t.board.basis = t.board.basis * Basis(Vector3.UP, PI)
		var turned: Basis = t.game.trick_basis
		if turned.z.z < 0.0:
			turned = turned * Basis(Vector3.UP, PI)
		# 1 when the board is back as the feet left it, less as it is rolled or turned away.
		var fit := minf(turned.y.y, turned.z.z)
		want = 1.0 - smoothstep(0.78, 0.97, fit)
		if t.game.board_turning and t.game.trick_progress < 0.75:
			want = 1.0
	if want < 0.5 and _wanted_free >= 0.5:
		# The catch: the feet stop the board and the knees give to it.
		sag.kick(-feel.catch_give)
	_wanted_free = want
	_free = move_toward(_free, want, t.dt * (20.0 if want > _free else 11.0))
	t.free = _free
	var mid := (t.front_foot + t.back_rest) * 0.5
	var on_front := t.board * t.front_foot
	var on_back := t.board * t.back_foot
	t.front_rig = on_front
	t.back_rig = on_back
	t.feet_mid = t.board * mid
	if _free <= 0.0:
		_free_front.place(on_front)
		_free_back.place(on_back)
		return
	# Clear of the board by as much as the trick needs (a flip more than a
	# shove-it), coming down as the catch nears.
	var lift: float = t.game.feet_off
	var flick := face * t.game.kick_side * 0.14 * (1.0 - smoothstep(0.2, 0.6, t.game.trick_progress))
	var kick_front: bool = not t.game.nollie
	var over_front := t.front_rest + Vector3.UP * 0.19 * lift + nose * 0.05 * lift + (flick if kick_front else Vector3.ZERO)
	var over_back := t.back_rest + Vector3.UP * 0.17 * lift - nose * 0.03 * lift + (Vector3.ZERO if kick_front else flick)
	t.front_rig = on_front.lerp(_free_front.update(over_front, t.dt), _free)
	t.back_rig = on_back.lerp(_free_back.update(over_back, t.dt), _free)
	t.feet_mid = t.feet_mid.lerp(mid, _free)


## Height of the deck's top surface at `z` along it: flat between the trucks,
## rising up the kicked nose and tail.
func _deck_surface(z: float) -> float:
	var half := inputs.deck_flat_length * 0.5
	var kick := inputs.nose_kick_degrees if z > 0.0 else inputs.tail_kick_degrees
	return DECK_TOP + maxf(absf(z) - half, 0.0) * tan(deg_to_rad(kick))


## Foot directions and knees for the pose, with the ankles working: the heel
## lifts as a foot snaps the tail or drives a push, and the sliding foot rolls
## onto its edge as it drags up the board.
func _pose_feet(t: Tick) -> void:
	var face := t.face
	var nose := Vector3.BACK
	var push := t.open
	var front_toe := (face * cos(0.55) + nose * sin(0.55)).normalized().slerp(nose, push * 0.95).normalized()
	var back_toe := (face * cos(0.12) + nose * sin(0.12)).normalized()
	var front_sole := Vector3.UP
	var back_sole := Vector3.UP
	# Pushing, the toes point forward and a little out. On the ground the heel
	# lifts as the stroke runs out; in the air behind, the foot hangs from the
	# shin with the toes trailing, and comes level as the leg swings through.
	var point := t.heel * 0.6
	if t.trail > 0.0:
		var leg := t.back_rig - solver.hip_joint(pose.hips, not t.front_left)
		var behind := atan2(-leg.dot(t.board.basis * nose), -leg.dot(t.board.basis.y))
		point = lerpf(point, clampf(behind * 0.9 + 0.35, 0.0, 1.6), t.trail)
	_foot_point = lerpf(_foot_point, point, 1.0 - exp(-22.0 * t.dt))
	if t.phase != RiderInputs.Push.NONE or absf(_foot_point) > 0.01 or t.stand > 0.0:
		var push_toe := (nose + face * 0.3).normalized()
		back_toe = back_toe.slerp(push_toe, push).normalized()
		var level := back_toe
		back_toe = (level * cos(_foot_point) - Vector3.UP * sin(_foot_point)).normalized()
		back_sole = (Vector3.UP * cos(_foot_point) + level * sin(_foot_point)).normalized()
	if t.snap > 0.0 or t.drag > 0.0:
		var nollie: bool = t.game.nollie
		# The popping foot goes up on its toes; the sliding one rolls to its outer edge.
		var away := -nose if nollie else nose
		var pop_toe := front_toe if nollie else back_toe
		var pop_sole := (Vector3.UP + pop_toe * t.snap * 0.6).normalized()
		pop_toe = (pop_toe - Vector3.UP * t.snap * 0.6).normalized()
		var drag_toe := back_toe if nollie else front_toe
		var drag_sole := (Vector3.UP + away * t.drag * 0.45).normalized()
		drag_toe = (drag_toe - Vector3.UP * t.drag * 0.25).normalized()
		if nollie:
			front_toe = pop_toe
			front_sole = pop_sole
			back_toe = drag_toe
			back_sole = drag_sole
		else:
			back_toe = pop_toe
			back_sole = pop_sole
			front_toe = drag_toe
			front_sole = drag_sole
	# Knees over the toes, coming together a little as the rider gets low.
	var pinch := crouch.value * 0.22 * (1.0 - push)
	var front_knee := (face + front_toe * 0.6 + Vector3.UP * 0.2 - nose * pinch).normalized()
	front_knee = front_knee.slerp((nose + face * 0.2 + Vector3.UP * 0.1).normalized(), push).normalized()
	var back_knee := (face + back_toe * 0.4 + Vector3.UP * 0.2 + nose * pinch).normalized().slerp(nose, push * 0.9).normalized()
	# On the board the feet and knees take its tilt. Off it they belong to the
	# body: the knees stay over the toes whatever the board is doing below, and
	# the ankles hang a little loose.
	var carry := t.board.basis
	var front_toe_rig := carry * front_toe
	var back_toe_rig := carry * back_toe
	var front_sole_rig := carry * front_sole
	var back_sole_rig := carry * back_sole
	var front_knee_rig := carry * front_knee
	var back_knee_rig := carry * back_knee
	var off := t.free
	if off > 0.0:
		var loose := Vector3.UP * 0.25
		front_toe_rig = front_toe_rig.slerp((front_toe - loose).normalized(), off).normalized()
		back_toe_rig = back_toe_rig.slerp((back_toe - loose).normalized(), off).normalized()
		front_sole_rig = front_sole_rig.slerp((Vector3.UP + front_toe * 0.25).normalized(), off).normalized()
		back_sole_rig = back_sole_rig.slerp((Vector3.UP + back_toe * 0.25).normalized(), off).normalized()
		front_knee_rig = front_knee_rig.slerp(front_knee, off).normalized()
		back_knee_rig = back_knee_rig.slerp(back_knee, off).normalized()
	_set_feet(t.front_left, t.front_rig, t.back_rig, front_toe_rig, back_toe_rig,
		front_knee_rig, back_knee_rig, front_sole_rig, back_sole_rig)


func _set_feet(front_left: bool, front: Vector3, back: Vector3, front_toe: Vector3, back_toe: Vector3,
		front_knee: Vector3, back_knee: Vector3, front_sole: Vector3, back_sole: Vector3) -> void:
	if front_left:
		pose.foot_l = front
		pose.toe_l = front_toe
		pose.knee_l = front_knee
		pose.sole_l = front_sole
		pose.foot_r = back
		pose.toe_r = back_toe
		pose.knee_r = back_knee
		pose.sole_r = back_sole
	else:
		pose.foot_r = front
		pose.toe_r = front_toe
		pose.knee_r = front_knee
		pose.sole_r = front_sole
		pose.foot_l = back
		pose.toe_l = back_toe
		pose.knee_l = back_knee
		pose.sole_l = back_sole


# --- Pelvis: weight and balance -----------------------------------------------------

## The lean that keeps the felt force running through the feet: into a carve
## across the board; into a push, back against the brakes and upright on a
## slope along it. A change first leaves the body behind, then it swings into
## the lean and settles (the filters' negative response and low damping).
func _update_balance(t: Tick) -> void:
	var support := maxf(motion.felt.y, 3.0)
	var across := atan2(motion.felt.x, support) * feel.lean_gain * motion.loaded
	var along := atan2(motion.felt.z, support) * feel.lean_along_gain * motion.loaded * (1.0 - 0.6 * t.push)
	if t.grinding:
		across = clampf(t.game.grind_lean * 1.4, -0.5, 0.5)
		along *= 0.5
	elif t.grounded:
		# The rider leans as they steer, a moment before the board comes round
		# (not on a board that is standing still: there is nothing to lean into).
		across += t.game.steer * 0.07 * smoothstep(0.2, 1.5, motion.speed)
		if t.game.manual_time > 0.0:
			# Hips over the wheels still on the ground.
			along -= signf(t.game.balance) * feel.manual_shift
	# Nobody stands perfectly still: small corrections, larger when it is hard.
	var hard := 1.0 - clampf(motion.speed / 2.5, 0.0, 1.0)
	if t.grinding or t.game.manual_time > 0.0:
		hard = 3.0
	var sway := 0.008 * feel.sway_amount * (0.5 + hard) * motion.loaded
	_sway = Vector2(sway * _wander(0.0), sway * _wander(7.3))
	across += _sway.x
	along += _sway.y
	_lean_target = clampf(across, -feel.lean_limit, feel.lean_limit)
	_pitch_target = clampf(along, -feel.lean_along_limit, feel.lean_along_limit)
	lean.update(_lean_target, t.dt)
	pitch.update(_pitch_target, t.dt)
	lean.value = clampf(lean.value, -feel.lean_limit * 1.25, feel.lean_limit * 1.25)
	pitch.value = clampf(pitch.value, -feel.lean_along_limit * 1.5, feel.lean_along_limit * 1.5)
	# The legs lean all the way; the pelvis and the spine take less of it, so
	# the body bends at the hips instead of tipping like a post. Onto the toes
	# the chest goes with the lean; onto the heels it stays up and folds
	# forward instead (see the chest), sitting back into the turn.
	var toe_side := smoothstep(-0.12, 0.12, lean.value * t.face.x)
	var spine := (1.0 - feel.angulation) * lerpf(0.3, 1.0, toe_side)
	t.hips_tilt = _lean_basis(lerpf(0.4, 0.65, toe_side), 0.6)
	t.spine_tilt = _lean_basis(spine, 0.35)
	t.spine_up = t.spine_tilt * Vector3.UP


## A share of the lean: about the nose axis, tipping up toward the board's left
## for a positive lean, and about the across axis, toward the nose for a
## positive pitch.
func _lean_basis(across: float, along: float) -> Basis:
	return Basis(Vector3.BACK, -lean.value * across) * Basis(Vector3.RIGHT, pitch.value * along)


## Slow, never-repeating drift in -1..1 for the small motions of balancing.
func _wander(offset: float) -> float:
	var c := _clock + offset
	return (sin(c * 2.7) + 0.6 * sin(c * 4.46 + 1.3) + 0.4 * sin(c * 7.1 + 4.1)) * 0.5


## The pelvis is a mass on the legs. They hold it at the height the rider means
## (the crouch) and give to everything else: the board pushing up into a
## transition or dropping away over a crest, a landing, the pop.
func _update_height(t: Tick) -> void:
	var wanted := lerpf(STAND_HEIGHT, CROUCH_HEIGHT, crouch.value)
	if t.push > 0.0:
		# Pushing slowly, the rider stands as tall as the driving leg allows: it
		# meets the ground nearly straight and leaves it nearly straight. At
		# speed they get lower over the board, for the longer stroke and to
		# stay steady on it.
		wanted = lerpf(wanted, feel.push_height - feel.push_speed_crouch * t.power, t.push)
	if t.phase != RiderInputs.Push.NONE:
		# The support knee gives through the drive and straightens as the leg
		# swings forward: lowest as the leg is furthest behind, tallest as it
		# reaches for the next plant. A big push starts down sooner, the foot
		# being on the ground so briefly.
		var low := lerpf(0.58, 0.52, t.power)
		wanted -= t.push * feel.push_bob * (1.0 + 0.6 * t.power) * 0.5 * (1.0 + cos(TAU * (t.cycle - low)))
	# Standing with a foot down: on a nearly straight leg.
	wanted = lerpf(wanted, feel.stand_height, clampf(t.over, 0.0, 1.0) * (1.0 - t.push))
	# Rolling along relaxed, the legs are a little straighter than the crouch's zero.
	wanted += feel.stand_tall * (1.0 - smoothstep(0.0, 0.4, crouch.value)) * (1.0 - t.open)
	if t.airborne:
		# Knees sucked up under the body through the top of the jump and kept
		# there; the legs only reach down for the ground as it arrives.
		var reaching := 1.0 - smoothstep(0.05, 0.24, t.game.time_to_land)
		wanted -= feel.air_tuck * smoothstep(0.04, 0.24, t.game.air_time) * (1.0 - reaching)
		var held := minf(wanted, lerpf(STAND_HEIGHT - 0.2, STAND_HEIGHT - 0.04, reaching))
		wanted = lerpf(wanted, held, smoothstep(0.1, 0.25, t.game.air_time))
	# Even the snap of a pop takes the legs a few frames.
	var before := _commanded
	_commanded = move_toward(_commanded, wanted, feel.leg_speed * t.dt)
	t.commanded = _commanded
	# The body has to be started and stopped: when the rider drops or rises, it
	# is a moment behind, and carries on a little past where they meant to stop.
	var speed := (_commanded - before) / t.dt
	var surge := clampf((speed - _commanded_speed) / t.dt, -14.0, 14.0)
	_commanded_speed = speed
	if t.game.just_landed:
		# The body is still coming down as the board stops: the legs give softly.
		var impact := clampf(motion.landing_speed, 0.0, 8.0)
		sag.velocity -= impact * feel.landing_give
		absorb = clampf(impact / 2.5, 0.0, 1.0)
	absorb *= exp(-t.dt / 0.3)
	var w := TAU * lerpf(feel.weight_frequency, feel.weight_frequency * feel.landing_softness, absorb)
	var ratio := feel.weight_rebound_damping if sag.velocity > 0.0 and sag.value < 0.0 else feel.weight_damping
	sag.stiffness = w * w
	sag.damping = 2.0 * ratio * w
	# In the air the board is not pushing on anything; a little of the unweighting stays.
	var heave := motion.heave + motion.gravity * (1.0 - motion.loaded) * 0.75 + surge * feel.weight_carry
	sag.velocity -= heave * feel.weight_load * t.dt
	sag.update(0.0, t.dt)
	sag.limit(CROUCH_HEIGHT - 0.12 - t.commanded, 0.07)
	t.compression = maxf(-sag.value, 0.0)


# --- Hips, chest, head: each follows the one below it ---------------------------------

func _update_hips(t: Tick) -> void:
	var face := t.face
	var nose := Vector3.BACK
	var push := t.push
	# Side-on to ride; facing the nose to push; most of the way round standing
	# with a foot down.
	var open := lerpf(lerpf(0.28, STAND_OPEN, _stand.value), PUSH_OPEN, push)
	var forward := (face * cos(open) + nose * sin(open)).normalized()
	# The hips have their own momentum about the spine: when the board turns
	# under them (a revert, a kickturn, a spin stopping on landing) they are
	# left behind, then come round and settle.
	hips_swing.velocity -= motion.yaw_acceleration * t.dt
	hips_swing.update(0.0, t.dt)
	hips_swing.limit(-0.7, 0.7)
	var weight := clampf(push_weight.value, 0.0, 1.15)
	var height := t.commanded + sag.value
	var origin := Vector3(-face.x * 0.06, height, t.feet_mid.z)
	# Pushing: hips over the front foot, toward the push side. As the leg drives
	# behind they go back and the trunk comes forward, keeping the weight over
	# the front foot: the more, the bigger the push.
	var back := _push_shift.update((0.05 + 0.08 * t.power) * clampf(t.leg, 0.0, 1.3), t.dt)
	# Standing with a foot down: between the two feet, most of the weight on
	# the one on the ground.
	origin = origin.lerp(Vector3(face.x * 0.11, height, 0.14), t.over)
	origin = origin.lerp(Vector3(face.x * 0.03, height, 0.11 - back), weight)
	# The pelvis turns with the driving leg: its hip reaches forward to plant
	# and goes back with the stroke.
	t.drive = face.x * clampf(t.leg * (0.26 + 0.1 * t.power) - 0.05, -0.12, 0.42) * push
	t.hips_forward = Basis(Vector3.UP, hips_swing.value + t.drive) * forward
	var pivot := Vector3(t.feet_mid.x, DECK_TOP, t.feet_mid.z)
	origin = pivot + _lean_basis(1.0, 1.0) * (origin - pivot)
	var pelvis := t.hips_tilt * _basis_from_forward(t.hips_forward, Vector3.UP)
	# It tips forward with the trunk as the rider leans into a push.
	pelvis = Basis(pelvis.x, (_push_bend(t) - 0.14) * 0.4 * push) * pelvis
	pose.hips = Transform3D(pelvis, origin)
	_keep_legs_in_reach(t)


## Bring the pelvis down toward a foot the leg cannot reach, rather than let the
## knee lock and the foot come off the board (or off the ground, pushing: the
## hips go down and back with the driving leg). The push foot in the air gives
## instead: it swings on the end of the leg.
func _keep_legs_in_reach(t: Tick) -> void:
	var limit := solver.leg_length() * LEG_REACH
	var pulled := false
	for _pass in 2:
		for front in [true, false]:
			var ankle := t.front_rig if front else t.back_rig
			var hip := solver.hip_joint(pose.hips, t.front_left == front)
			var reach := hip.distance_to(ankle)
			if reach <= limit:
				continue
			if not front and t.push_free:
				t.back_rig = hip + (ankle - hip) / reach * limit
			else:
				pose.hips.origin += (ankle - hip) / reach * (reach - limit)
				pulled = true
	if pulled:
		sag.velocity = minf(sag.velocity, 0.0)


func _update_chest(t: Tick) -> void:
	var push := t.push
	var nose := Vector3.BACK
	t.breath = sin(_clock * TAU * feel.breath_rate)
	var base := t.spine_tilt * _basis_from_forward(t.hips_forward, Vector3.UP)
	# Folded at the waist: more as the rider crouches and as load pushes the legs
	# down; leaning onto the heels the chest comes forward to stay over the board.
	# Pushing keeps the back fairly upright, dipping a little into each drive.
	var heel_side := maxf(-lean.value * t.face.x, 0.0)
	# Standing with a foot down the back is nearly straight.
	var bend := lerpf(lerpf(0.24 + crouch.value * 0.4 + heel_side * 0.35, 0.09, t.stand), _push_bend(t), push)
	bend += t.compression * feel.compression_fold + t.breath * 0.012 * feel.breath_amount
	var target := Basis(base.x, bend) * base
	# Side-on the shoulders turn further toward the nose than the hips; pushing,
	# both face it, the shoulders countering the leg a little.
	var twist := lerpf(0.32, 0.0, t.open)
	twist *= 1.0 if t.hips_forward.cross(nose).dot(t.spine_up) >= 0.0 else -1.0
	# The shoulders turn against the pelvis as the leg drives, as in a stride.
	twist -= t.drive * 1.7
	# Shoulders lead a turn, and a spin; crouched with the steer held they wind
	# up against the spin first, to be thrown into it by the pop.
	var lead := motion.yaw_rate * (feel.turn_lead if not t.airborne else feel.spin_lead)
	if t.grounded and t.game.crouch_held:
		lead -= t.game.steer * feel.spin_windup * (0.4 + 0.6 * crouch.value)
	twist += clampf(lead, -0.6, 0.6)
	target = Basis(t.spine_up, twist) * target
	# Followed in the world, so a turning or pitching board leaves the chest
	# behind for a moment, and the body's own acceleration throws it: back as
	# the board surges, further over as a landing stops the pelvis.
	var world := t.frame.basis
	var axis := chest.value * Vector3.UP if chest.is_following() else world * (target * Vector3.UP)
	var jolt := world * (motion.jolt + Vector3.UP * _sag_acceleration())
	var torque := jolt.cross(axis) / TRUNK_PENDULUM * feel.chest_inertia
	var goal := (world * target).get_rotation_quaternion()
	var followed := chest.update(goal, t.dt, torque)
	# Never further from where it should be than a spine can bend.
	var error := MotionFilters.SpringRotation.rotation_vector(goal, followed)
	if error.length() > 0.6:
		followed = (Quaternion(error.normalized(), 0.6) * goal).normalized()
		chest.value = followed
		chest.velocity *= 0.5
	pose.chest = (t.to_rig * Basis(followed)).orthonormalized()


## How far forward the trunk leans to push (radians): into each drive, furthest
## as the leg is furthest behind, and back up as it swings through. A slow push
## is nearly upright; at speed the rider stays low over the board and goes well
## forward, the trunk ahead of the front foot balancing the leg behind.
func _push_bend(t: Tick) -> float:
	var into := 0.1
	if t.phase != RiderInputs.Push.NONE:
		into = 0.5 * (1.0 + cos(TAU * (t.cycle - lerpf(0.6, 0.5, t.power))))
	return 0.14 + feel.push_lean * into + t.power * (0.28 + feel.push_speed_lean * into)


## Acceleration of the pelvis on the legs' spring, for what it does to the trunk.
func _sag_acceleration() -> float:
	return clampf(-sag.stiffness * sag.value - sag.damping * sag.velocity, -30.0, 30.0)


## The head stays level while the body leans and looks where the rider is
## going: down the line and into a turn; at the board while setting up and
## through a flip; at the landing once the board is caught.
func _update_head(t: Tick) -> void:
	var frame := t.frame
	var travel := frame.basis * motion.travel
	travel.y = 0.0
	var look := (travel.normalized() * 0.9 + frame.basis * t.hips_forward * 0.2 - Vector3.UP * 0.3).normalized()
	var head := frame * (pose.hips.origin + t.spine_up * 0.62)
	if t.airborne:
		var flipping: bool = t.game.trick_active and t.game.trick_progress < 1.0 and t.game.feet_off > 0.05
		if flipping:
			look = (t.deck.origin + t.deck.basis.z * 0.1 - head).normalized()
		elif t.game.time_to_land < 0.6:
			look = (t.game.landing_point + travel.normalized() * 1.2 - head).normalized().slerp(look, 0.35).normalized()
	elif t.grounded:
		look = look.rotated(frame.basis.y, clampf(motion.yaw_rate * 0.22, -0.5, 0.5))
		if t.game.crouch_held:
			# Eyes on the board, lining up the pop.
			var board := (t.deck.origin + t.deck.basis.z * 0.35 - head).normalized()
			look = look.slerp(board, 0.35 * crouch.value).normalized()
	if t.step > 0.0:
		# A glance down at where the foot is going.
		look = (look - Vector3.UP * 0.4 * t.step).normalized()
	head_forward = head_forward.slerp(look, 1.0 - exp(-feel.head_rate * t.dt)).normalized()
	# Only as far round as a neck turns from the chest.
	var local := t.to_rig * head_forward
	var chest_forward := pose.chest.z
	var angle := chest_forward.angle_to(local)
	if angle > 1.45:
		local = chest_forward.slerp(local, 1.45 / angle).normalized()
	# Level with the horizon, whatever the board and the body are doing.
	var level := (t.to_rig * Vector3.UP).lerp(t.spine_up, 1.0 - feel.head_level).normalized()
	pose.head = _basis_from_forward(local, level)


# --- Arms -------------------------------------------------------------------------------

## Each arm is driven at the shoulder (see Arm), so it moves as a limb. Arms
## are heavy and a rider does not hold them up for nothing: they hang, and move
## for a reason, for as long as the reason lasts.
##
## Rest. Standing still they hang at the sides. Rolling they are a little
## readier the faster the board goes, but still low.
##
## Reactions. What moves them on the ground is change, not state: the board
## turning under a body that has not yet leaned to match, being thrown forward
## or back, the board coming round, a landing. Each of those is a signal that
## dies away once things are steady, so the arms go and come back: at the start
## of a carve and at each change of edge they swing against the lean and part
## from the body, then settle low while the carve is held.
##
## Actions. A pop swings them up with it (front arm a beat ahead of the back
## one), as far as the pop is big, and they come down to meet the landing. Only
## where balancing really goes on (a manual, a rail, a long time in the air)
## do they stay out, and then they keep working. Pushing, they swing against
## the legs: the arm on the pushing side forward as its leg drives back, the
## other arm back.
##
## The two arms are not mirrors: the trailing one answers a moment later and a
## little less. They are held from the shoulders rather than fixed to the
## chest, so they hang while the trunk leans. They have weight (dragged by the
## shoulders, floating when the rider is light, pulled down by a landing), and
## the hands follow loosely from the wrist.
func _update_arms(t: Tick) -> void:
	var toes := t.face.x
	var manual: bool = t.grounded and t.game.manual_time > 0.0
	var use := feel.arm_use
	# A board standing still asks nothing of the arms.
	var live := smoothstep(0.3, 3.0, motion.speed)
	var ready := smoothstep(0.4, maxf(feel.arm_ready_speed, 0.5), motion.speed)
	_pop_age += t.dt
	if t.game.just_landed:
		_gestures += 1

	var front_arm := ARM_HANG.lerp(ARM_ROLL_FRONT, ready)
	var back_arm := ARM_HANG.lerp(ARM_ROLL, ready)

	# Balancing for a while: a manual (more of it the faster), a rail, a slide,
	# and the air once it has gone on longer than a hop.
	var hold := 0.0
	if t.airborne:
		hold = 0.75 * smoothstep(0.35, 0.9, t.game.air_time)
	elif t.grinding:
		hold = 0.6
	elif manual:
		hold = 0.35 + 0.4 * smoothstep(1.5, 6.0, motion.speed)
	elif t.game.state == RiderInputs.State.SLIDE:
		hold = 0.55 * live
	hold = clampf(hold * use, 0.0, 1.0)
	_arm_hold = move_toward(_arm_hold, hold, t.dt * (3.5 if hold > _arm_hold else 2.2))
	front_arm = front_arm.lerp(ARM_BALANCE_FRONT, _arm_hold)
	back_arm = back_arm.lerp(ARM_BALANCE_BACK, _arm_hold)

	# Reactions. Across the board: against the lean, mostly while the body is
	# still getting there (the board has turned and the rider is catching up),
	# only a little of it kept while the lean is held. The arms part from the
	# body as they do.
	var react := live * use * feel.arm_balance
	var lean_now := lean.value * toes
	var lean_off := (_lean_target - lean.value) * toes
	var lean_rate := lean.velocity * toes
	var across := -(lean_now * 0.4 + lean_off * 1.6 + lean_rate * 0.12) * react
	var part := (absf(lean_off) * 1.3 + absf(lean_rate) * 0.08 + absf(lean_now) * 0.3) * react
	# Along the board the two arms seesaw: thrown toward one end, the arm at
	# the other lifts.
	var along := clampf(pitch.value * 0.5 + (_pitch_target - pitch.value) * 1.8 + pitch.velocity * 0.1, -0.3, 0.3) * react
	if manual or t.grinding:
		# Balancing on two wheels or a rail is never still: the arms answer the
		# board as it tips, and work with every small correction the body makes.
		var tipping := (t.to_rig * t.game.angular_velocity).x
		var busy := feel.arm_balance * _arm_hold / 0.6
		along += (clampf(tipping * 0.1, -0.35, 0.35) + _sway.y * 5.0) * busy
		across += -toes * _sway.x * 4.0 * busy
	# The board coming round under the rider (a kickturn, a revert, a slide):
	# the shoulders and arms are left behind it, and open.
	var turned := hips_swing.value * live * use
	var open := absf(turned) * 0.7
	# A landing: the arms part to steady it as the legs give, then come back.
	var brace := absorb * use
	# Coiled to pop: the back arm draws back, the front hand comes forward, and
	# with a spin wound up both go round against it.
	var coil := crouch.value * (0.35 + 0.65 * ready) if t.grounded and t.game.crouch_held else 0.0
	var wound := turned * 0.8 - t.game.steer * 0.5 * coil

	front_arm += Vector3(part + open - along, across if across > 0.0 else across * 0.5, -0.1 * part)
	back_arm += Vector3((part + open) * 0.85 + along, across if across > 0.0 else across * 1.15, -0.1 * part)
	front_arm += Vector3(0.3, 0.15, 0.35) * brace + Vector3(-0.03, 0.12, 0.2) * coil
	back_arm += Vector3(0.35, 0.0, 0.3) * brace + Vector3(0.0, -0.22, 0.12) * coil

	# The pop: thrown up with it and let down again, the front arm up and
	# forward with the elbow bent, the back one out behind, a beat later. A
	# trick keeps them lower and closer in than a plain ollie. No two pops are
	# thrown quite alike.
	var lift := 0.0
	if t.airborne:
		var tricky: bool = t.game.trick_active and t.game.trick_turns_board
		var size := _pop_size * (0.6 if tricky else 1.0) * feel.pop_arm_lift * (1.0 + 0.18 * _vary(1.0))
		var behind := _pop_age - 0.05 - 0.02 * _vary(2.0)
		var lift_front := smoothstep(0.0, 0.13, _pop_age) * (1.0 - smoothstep(0.28, 0.7, _pop_age)) * size
		var lift_back := smoothstep(0.0, 0.15, behind) * (1.0 - smoothstep(0.3, 0.75, behind)) * size * (1.0 + 0.15 * _vary(3.0))
		front_arm += Vector3(0.5, 0.55, 0.55) * lift_front
		back_arm += Vector3(0.75, -0.2, 0.3) * lift_back
		lift = maxf(lift_front, lift_back)
		# Reaching down for the ground as it comes.
		var meet := 1.0 - smoothstep(0.0, 0.22, t.game.time_to_land)
		front_arm = front_arm.lerp(Vector3(0.32, 0.32, 0.55), meet * 0.8)
		back_arm = back_arm.lerp(Vector3(0.34, 0.08, 0.5), meet * 0.8)
		# Spinning fast the arms come in; they open again to stop the turn.
		var spin := clampf(absf(t.game.spin_rate) / 8.0, 0.0, 1.0) * (1.0 - meet)
		front_arm = front_arm.lerp(Vector3(0.3, 0.55, 1.35), spin)
		back_arm = back_arm.lerp(Vector3(0.3, 0.45, 1.3), spin)

	# The trailing arm does all of that a moment after the leading one.
	_trail_target = _trail_target.lerp(back_arm, 1.0 - exp(-t.dt / (0.045 + 0.015 * _vary(4.0))))
	back_arm = _trail_target

	# Pushing: swinging against the legs, as in an easy stride, not a sprint.
	# The arm on the pushing side (the back one) comes forward as its leg
	# drives back and the other arm goes back; as the foot swings forward to
	# plant they change places. The arm coming forward stays low: the upper arm
	# only part of the way up, the elbow bent, the hand in front of the body
	# below the chest rather than thrust out ahead. The arm going back hangs
	# about straight down beside the hip, which against a trunk leaning forward
	# is as far back as a shoulder goes. An arm takes a moment to answer, so it
	# is asked a little ahead of the leg. Bigger pushes, bigger swings.
	var stride := clampf(t.leg + _leg_rate * feel.push_arm_lead, -0.4, 1.3)
	var swing := (0.8 + 0.4 * t.power) * feel.push_arm_swing
	# What of the trunk's lean the arms still take (see _arm_frame), put back.
	var hang := _push_bend(t) * 0.9 * (1.0 - feel.arm_level)
	var front_swing := 0.12 - 0.32 * stride * swing
	var back_swing := -0.1 + 0.42 * stride * swing
	front_arm = front_arm.lerp(_push_arm(hang, front_swing), t.push)
	back_arm = back_arm.lerp(_push_arm(hang, back_swing), t.push)

	# Arms that are working are held firm; hanging, they are loose and the
	# body's motion swings them more.
	var working := clampf(maxf(maxf(_arm_hold, part * 2.5 + absf(along) * 2.0 + open), maxf(brace, lift)), 0.0, 1.0)
	var tone := 1.0 + feel.arm_tone * maxf(working, t.push * 0.5)
	for arm: Arm in [arm_l, arm_r]:
		arm.raise.stiffness = feel.arm_stiffness * tone
		arm.raise.damping = feel.arm_damping * sqrt(tone)
		arm.swing.stiffness = feel.arm_stiffness * tone
		arm.swing.damping = feel.arm_damping * sqrt(tone)
		arm.bend.stiffness = feel.elbow_stiffness * tone
		arm.bend.damping = feel.elbow_damping * sqrt(tone)

	# The shoulders lift with the arms and with each breath.
	var breath := (t.breath * 0.5 + 0.5) * 0.02 * feel.breath_amount
	pose.shoulder_lift_l = clampf(arm_l.raise.value * 0.22, 0.0, 0.4) + breath
	pose.shoulder_lift_r = clampf(arm_r.raise.value * 0.22, 0.0, 0.4) + breath
	var joint_l := solver.shoulder_joint(pose.hips, pose.chest, true, pose.shoulder_lift_l)
	var joint_r := solver.shoulder_joint(pose.hips, pose.chest, false, pose.shoulder_lift_r)
	_track_shoulders(t, joint_l, joint_r)
	var carry := _arm_frame(t)
	var left_arm := front_arm if t.front_left else back_arm
	var right_arm := back_arm if t.front_left else front_arm
	# Going round with (or against) the board: one arm forward, the other back,
	# the more the further out they are.
	left_arm.y -= wound * (0.4 + left_arm.x)
	right_arm.y += wound * (0.4 + right_arm.x)
	# An arm lies against the side of the body; it does not pass through it.
	# The arms hang upright while the trunk leans, so when the chest tips
	# toward one side the arm on the other is pushed out by that much.
	var tipped := asin(clampf(pose.chest.y.dot(carry.x), -1.0, 1.0))
	left_arm.x = maxf(left_arm.x, ARM_CLEAR + maxf(-tipped, 0.0))
	right_arm.x = maxf(right_arm.x, ARM_CLEAR + maxf(tipped, 0.0))
	var loose := 1.0 - 0.5 * working
	arm_l.update(left_arm, _arm_drive(t, arm_l, carry, true) * loose, t.dt)
	arm_r.update(right_arm, _arm_drive(t, arm_r, carry, false) * loose, t.dt)
	var left_reach := _arm_reach(arm_l, joint_l, carry, 1.0)
	var right_reach := _arm_reach(arm_r, joint_r, carry, -1.0)
	pose.hand_l = left_reach[0]
	pose.elbow_l = left_reach[1]
	pose.hand_r = right_reach[0]
	pose.elbow_r = right_reach[1]
	# A relaxed hand droops from the wrist and trails the forearm; a working one
	# is held more in line with it.
	var down := t.to_rig * Vector3.DOWN
	var reaches := [left_reach, right_reach]
	for i in 2:
		var forearm: Vector3 = reaches[i][2]
		var want := (forearm + down * feel.wrist_droop * (1.0 - 0.6 * working)).normalized()
		var hand: Vector3 = (_hand_dir[i] as Vector3).slerp(want, 1.0 - exp(-t.dt * feel.wrist_follow)).normalized()
		# No further from the forearm than a wrist bends.
		var bent := forearm.angle_to(hand)
		if bent > 0.8:
			hand = forearm.slerp(hand, 0.8 / bent).normalized()
		_hand_dir[i] = hand
	pose.hand_dir_l = _hand_dir[0]
	pose.hand_dir_r = _hand_dir[1]
	if t.game.grab_blend > 0.0:
		# The grabbing hand reaches down to the deck edge.
		var reach := t.deck_in_rig * (t.game.grab_point + Vector3.UP * (DECK_TOP + 0.03))
		var left_hand: bool = t.game.grab_front_hand == t.front_left
		if left_hand:
			pose.hand_l = pose.hand_l.lerp(reach, t.game.grab_blend)
		else:
			pose.hand_r = pose.hand_r.lerp(reach, t.game.grab_blend)


## An arm in the stride of a push, `swing` forward (or back) of hanging: coming
## forward the elbow bends and the hand comes in front of the body; going back
## the arm straightens and clears the hip.
static func _push_arm(hang: float, swing: float) -> Vector3:
	return Vector3(0.14 - 0.1 * clampf(swing, -1.0, 1.0), hang + swing, clampf(0.62 + 0.55 * swing, 0.35, 1.0))


## A repeatable number in -1..1 for this gesture, so no two are quite alike
## (and every run of the game is still the same).
func _vary(salt: float) -> float:
	var x := sin(float(_gestures) * 12.9898 + salt * 78.233) * 43758.5453
	return ((x - floorf(x)) * 2.0 - 1.0) * feel.arm_variety


## The frame the arms are held in: facing the way the chest faces, but mostly
## upright rather than tipped with the trunk. So an arm at rest hangs from the
## shoulder however far the rider leans or folds, and arms held out to balance
## stay level while the body moves under them.
func _arm_frame(t: Tick) -> Basis:
	var up := pose.chest.y.slerp(t.to_rig * Vector3.UP, clampf(feel.arm_level, 0.0, 1.0)).normalized()
	var across := up.cross(pose.chest.z)
	if across.length_squared() < 1e-6:
		return pose.chest
	across = across.normalized()
	return Basis(across, up, across.cross(up))


## Shoulder acceleration in the world, from where the joints went this tick.
func _track_shoulders(t: Tick, left: Vector3, right: Vector3) -> void:
	var joints := [t.frame * left, t.frame * right]
	for i in 2:
		var joint: Vector3 = joints[i]
		if not _shoulders_primed:
			_shoulder[i] = joint
			_shoulder_velocity[i] = motion.velocity
			_shoulder_acceleration[i] = Vector3.ZERO
		var velocity: Vector3 = (joint - _shoulder[i]) / t.dt
		var raw: Vector3 = ((velocity - _shoulder_velocity[i]) / t.dt).limit_length(40.0)
		_shoulder_acceleration[i] = (_shoulder_acceleration[i] as Vector3).lerp(raw, 0.3)
		_shoulder[i] = joint
		_shoulder_velocity[i] = velocity
	_shoulders_primed = true


## What the body's motion does to a held arm (angular acceleration on raise,
## swing, bend): the shoulder accelerating one way swings the arm the other,
## and the arm's weight changes with the load, lifting it when the rider is
## light and dragging it down in a compression.
func _arm_drive(t: Tick, arm: Arm, carry: Basis, left: bool) -> Vector3:
	var side := 1.0 if left else -1.0
	var world: Vector3 = _shoulder_acceleration[0 if left else 1]
	# Free fall moves the whole body together: only the rest is felt.
	world += Vector3.UP * motion.gravity * (1.0 - motion.loaded)
	var local := (t.frame.basis * carry).transposed() * world
	var inertia := feel.arm_inertia / ARM_PENDULUM
	var weight := (motion.felt.y / motion.gravity - 1.0) * motion.gravity / ARM_PENDULUM * feel.arm_float
	var raise := -local.x * side * inertia - weight * sin(arm.raise.value)
	var swing := -local.z * inertia - weight * sin(arm.swing.value)
	# The forearm hangs from the elbow and trails the upper arm.
	var bend := -local.z * inertia * 0.8 - arm.swing.velocity * 1.2
	return Vector3(clampf(raise, -60.0, 60.0), clampf(swing, -60.0, 60.0), clampf(bend, -60.0, 60.0))


## Hand position, elbow pole and forearm direction (rig space) for an arm at its
## current angles, from its shoulder joint, in the frame the arms are held in.
## `side` is +1 for the left arm (the frame's +X). The arm hangs straight down,
## swings forward about the shoulder line, then lifts out to the side; the
## forearm bends forward from the elbow.
func _arm_reach(arm: Arm, shoulder: Vector3, chest_basis: Basis, side: float) -> Array:
	var upper := Basis(chest_basis.z, arm.raise.value * side) * (Basis(chest_basis.x, -arm.swing.value) * -chest_basis.y)
	var toward := chest_basis.z + chest_basis.y * 0.15
	var across := toward - upper * upper.dot(toward)
	across = across.normalized() if across.length_squared() > 1e-6 else chest_basis.z
	var lower := upper * cos(arm.bend.value) + across * sin(arm.bend.value)
	var elbow := shoulder + upper * solver.upper_arm_length
	var hand := elbow + lower * solver.lower_arm_length
	var line := (hand - shoulder).normalized()
	var pole := (elbow - shoulder) - line * line.dot(elbow - shoulder)
	return [hand, pole.normalized() if pole.length_squared() > 1e-8 else -chest_basis.z, lower.normalized()]


## Basis whose +Z faces `forward` and +Y is as close to `up` as possible.
static func _basis_from_forward(forward: Vector3, up: Vector3) -> Basis:
	var z := forward.normalized()
	var x := up.cross(z)
	if x.length_squared() < 1e-8:
		x = Vector3.RIGHT
	x = x.normalized()
	return Basis(x, z.cross(x), z)
