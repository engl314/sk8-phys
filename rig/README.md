# The rider rig

A procedural skateboarder. There are no animation clips: every physics tick,
the rig works out a whole body from what the board is doing (where it is, how
it moves, what pushes on it) and poses a skeleton to match.

## How a tick works

The game drives the rig with one call per physics tick: it fills in
`rider.inputs` with the board's state, then calls `rider.step(delta)`.

```gdscript
func _physics_process(delta: float) -> void:
	var game := rider.inputs
	game.deck = board_transform                # +Z toward the nose
	game.frame = board_transform               # in the air: same place, but upright
	game.velocity = board_velocity
	game.forward_speed = board_velocity.dot(board_transform.basis.z)
	game.state = RiderInputs.State.GROUND
	game.steer = steer_input                   # -1..1, positive left
	game.crouch = 1.0 if crouching else 0.0
	rider.step(delta)
```

Those fields alone give a rider who rolls, carves, crouches and steps off when
the board stops. Every other input adds a behaviour on top.

Inside `step()`, four things happen:

1. **The rig works out what the rider feels.** `rider_motion.gd` turns the
   board's motion into the force through the feet: 1 g straight up when
   rolling on the flat, tipped over in a turn, stronger in a compression, none
   in the air. Jolts too sharp to follow are treated as impacts.
2. **The body is built from the ground up**, in stages: feet, balance, pelvis
   height, hips, chest, head, arms. Each stage works from what the earlier
   ones decided.
3. **Every target is smoothed.** Nothing jumps straight to where it is aimed.
   Springs and rate- and acceleration-limited followers (`motion_filters.gd`)
   carry each part there, and this is where most of the sense of weight comes
   from.
4. **The pose is put on the skeleton.** The stages fill in a `RiderPose`: the
   hips, the chest and head orientations, ankle and wrist positions, and which
   way the knees and elbows point. `rider_pose_solver.gd` fits the skeleton
   to it, using two-bone IK (`two_bone_ik.gd`) for the legs and arms.

On the ground the rig works in the deck's frame. In the air it switches to an
upright frame on the rider's heading, so the board can pitch and flip under
the feet while the body stays upright.

In a fall, the posed body hands over to a Verlet ragdoll
(`verlet_ragdoll.gd`), which collides with the world until the game ends the
fall.

## What the rig reads

`rider_inputs.gd` is the complete list, with units and meanings. In groups:

| Group | Fields | If the game leaves it unset |
| --- | --- | --- |
| Board motion | `deck`, `frame`, `velocity`, `angular_velocity`, `forward_speed`, `ground_normal`, `gravity` | required |
| State | `state`, `just_landed`, `manual_time`, `grind_lean` | always on the ground; no landings, manuals or rails |
| Player | `steer`, `balance`, `crouch`, `crouch_held`, `nollie_held` | never crouches or leans into a steer |
| Pushing | `push_phase`, `push_progress`, `push_again`, `push_hang`, the three phase times | never pushes |
| Air | `airborne`, `air_time`, `time_to_land`, `landing_point`, `spin_rate` | no jump posture |
| Trick | `trick_active`, `trick_late`, `trick_turns_board`, `trick_progress`, `board_turning`, `trick_basis`, `feet_off`, `front_foot_slide`, `kick_side`, `nollie` | feet stay on a board that flips under them |
| Grab | `grabbing`, `grab_blend`, `grab_point`, `grab_front_hand` | no grabs |
| Board size | `deck_ride_height`, `deck_width`, `deck_flat_length`, nose and tail kick angles | a standard street deck |

The game also reports events as they happen, as calls on `RiderAnimator`:

- `pop(strength)` at the moment of a pop.
- `swap_stance()` when the rider turns to ride the other end forward (the
  `deck` turns half a turn in the same tick), and `reset_stance()` on a
  respawn.
- `start_ragdoll(velocity)` and `stop_ragdoll()` for a fall.

The rig reports back `hip_height()` and `crouch.value` (posture the board
simulation can work from; neither depends on the visible body), `facing()`,
`is_switch()`, and during a fall `is_ragdoll()`, `ragdoll_hips()` and
`ragdoll_speed()`.

In this project the board simulation and the rig meet in one place:
`_tell_rider()` in `game/skater_controller.gd`, which sets every field.

## Conventions

- Metres, seconds, radians. Board space: +Z toward the nose, +Y up, +X to the
  left of someone facing the nose.
- Written for a fixed 60 Hz physics tick. Most of it takes `dt`, but a few
  rates (the crouch, the ragdoll) are per tick.
- Deterministic: no randomness anywhere, so the same inputs give the same body.

## What is tuned to this rider and this board

- The body's proportions live in `rider_skeleton.gd`; the solver reads bone
  lengths from the skeleton.
- Heights and foot placements (the constants at the top of
  `rider_animator.gd`) are fixed values in metres for a 1.78 m rider. They are
  not read from the skeleton.
- How the rider moves (weight, lean, arms, pushing, standing) is all in
  `rider_feel.gd`. The filters read it every tick, so it can be changed while
  the game runs.
- The figure itself is `block_figure.gd`: boxes hung on the bones, standing in
  for a character model.

## The files

| File | What it is |
| --- | --- |
| `rider_inputs.gd` | what the game supplies |
| `rider_animator.gd` | the body, built in stages: feet, balance, pelvis, hips, chest, head, arms |
| `rider_motion.gd` | what the rider feels, worked out from the board's motion |
| `rider_feel.gd` | the tunable feel |
| `motion_filters.gd` | springs and second-order filters |
| `rider_pose.gd`, `rider_pose_solver.gd`, `two_bone_ik.gd` | pose targets and the IK that puts them on the skeleton |
| `rider_skeleton.gd` | the humanoid skeleton (Godot's standard bone names) |
| `block_figure.gd`, `glass.gdshader` | the blocky figure |
| `verlet_ragdoll.gd` | the fall |
