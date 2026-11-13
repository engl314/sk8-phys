class_name RiderInputs
extends RefCounted

## What the board is on. SLIDE is a powerslide or revert: still on the ground.
enum State { GROUND, SLIDE, AIR, GRIND, BAIL }
## Where a push has got to: the foot coming to the ground, on it and driving,
## held behind while the rider glides (only at speed), swinging forward again.
enum Push { NONE, REACH, DRIVE, SWING, HANG }

# --- Where the board is and how it is moving (world space) ---------------------

## The deck's centre, as the rider stands on it: +Z the way they are riding.
## (A game that lets the rider ride either end forward turns this half a turn
## and calls RiderAnimator.swap_stance().)
var deck := Transform3D.IDENTITY
## The frame the body is built in. On the ground: the deck. In the air: at the
## deck's centre but upright on the rider's heading, so the board can pitch
## and flip under the feet without the body going with it.
var frame := Transform3D.IDENTITY
var velocity := Vector3.ZERO
## The deck's own turning (rad/s about each world axis).
var angular_velocity := Vector3.ZERO
## Speed along the deck's +Z; negative when rolling backward.
var forward_speed := 0.0
## Up out of whatever the board is on.
var ground_normal := Vector3.UP
var gravity := 9.8

# --- What it is doing -----------------------------------------------------------

var state := State.GROUND
## True for the one tick the board comes down onto something.
var just_landed := false
## Seconds a manual has been held (0 when not in one).
var manual_time := 0.0
## How far the rider is over to one side of a rail (radians, as a lean).
var grind_lean := 0.0

# --- What the player is asking for ------------------------------------------------

## -1..1, positive to the left.
var steer := 0.0
## -1..1: which end is being lifted in a manual (positive: the nose).
var balance := 0.0
## 0..1 how far the rider should be crouched.
var crouch := 0.0
## Crouching to pop (rather than, say, to pump a transition).
var crouch_held := false
## A nollie is being set up (popping off the nose).
var nollie_held := false

# --- Pushing -------------------------------------------------------------------------

var push_phase := Push.NONE
## 0..1 through the current phase.
var push_progress := 0.0
## Another push follows this one.
var push_again := false
## How long this push's glide lasts (the HANG phase), in seconds.
var push_hang := 0.0
## How long the other phases last, in seconds.
var push_reach_time := 0.16
var push_drive_time := 0.26
var push_swing_time := 0.24

# --- In the air ------------------------------------------------------------------------

## Off the ground on a jump or a drop (not on a rail).
var airborne := false
## Seconds since leaving the ground, and until coming back to it (a prediction).
var air_time := 0.0
var time_to_land := INF
## Where it will come down (world space).
var landing_point := Vector3.ZERO
## How fast the rider is spinning about their own up (rad/s).
var spin_rate := 0.0

# --- The trick under way -------------------------------------------------------------------

## A trick was popped (an ollie counts), and whether it was started late, in the air.
var trick_active := false
var trick_late := false
## It is one that flips or spins the board under the feet (not a plain ollie).
var trick_turns_board := false
## 0..1 through the board's rotation; 1 once it is caught.
var trick_progress := 0.0
## The board is turning under the feet right now.
var board_turning := false
## How far the trick has turned the board from flat, in the deck's own space.
var trick_basis := Basis.IDENTITY
## 0..1 how far the feet have to be off the board for it.
var feet_off := 0.0
## How far the front foot has slid up the board on the pop (m).
var front_foot_slide := 0.0
## -1..1: which way the kicking foot flicks off the edge.
var kick_side := 0.0
## It was popped off the nose.
var nollie := false

# --- A grab ------------------------------------------------------------------------------------

var grabbing := false
## 0..1 how far the hand has reached the board.
var grab_blend := 0.0
## Where on the deck the hand goes (deck space).
var grab_point := Vector3.ZERO
## The front hand does it (else the back one).
var grab_front_hand := true

# --- The board itself ----------------------------------------------------------------------------

## Height of the deck's centre above level ground when rolling.
var deck_ride_height := 0.0875
var deck_width := 0.24
## Length of the flat middle of the deck; beyond it the nose and tail rise at these angles.
var deck_flat_length := 0.59
var nose_kick_degrees := 13.0
var tail_kick_degrees := 12.5


## On the ground, rolling or sliding.
func grounded() -> bool:
	return state == State.GROUND or state == State.SLIDE


func pushing() -> bool:
	return push_phase != Push.NONE
