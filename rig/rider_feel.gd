class_name RiderFeel
extends Resource

const SAVE_PATH := "res://tuning/default_feel.tres"

@export_group("Weight")
## The legs as a spring under the pelvis: how fast they answer (Hz) and how much
## they ring. Rebound is damped harder so a landing settles instead of bouncing.
@export var weight_frequency := 2.6
@export var weight_damping := 0.55
@export var weight_rebound_damping := 0.95
## How far the legs give to the board's own vertical acceleration (bumps,
## transitions, going light over a crest). 0 = rigid legs.
@export var weight_load := 0.6
## Downward pelvis speed per m/s of landing impact, and how much softer the
## legs go while they absorb it (share of the usual frequency).
@export var landing_give := 0.95
@export var landing_softness := 0.4
## Upward pelvis speed (m/s) as the legs snap straight at the pop.
@export var pop_extension := 1.0
## Fastest the legs can change the hip height (m/s): the snap of a pop.
@export var leg_speed := 4.0
## How much taller than the working stance the rider stands when just rolling (m).
@export var stand_tall := 0.05
## How much of the rider's own rising and dropping the body is late for, and
## carries past (0 = the hips go exactly where the legs put them).
@export var weight_carry := 0.5
## Downward pelvis speed (m/s) as the feet catch a flipping board.
@export var catch_give := 0.5
## How far the knees come up under the body in the air (m), beyond the crouch.
@export var air_tuck := 0.11

@export_group("Standing")
## Standing still, the rider puts the back foot down beside the board rather
## than balancing on it (off: both feet stay on the board).
@export var stand_foot_down := true
## Seconds at rest before the foot goes down.
@export var stand_delay := 0.2
## How long the step down takes, and the step back up onto the board (s).
@export var stand_step_time := 0.38
@export var stand_step_up_time := 0.3
## Downward pelvis speed (m/s) as the weight comes onto the foot: the knee gives.
@export var stand_give := 0.5
## Hip height above the board standing with a foot down (m): the leg on the
## ground nearly straight.
@export var stand_height := 0.86

@export_group("Push")
## Hip height above the board pushing slowly (m): as tall as rolling along,
## the driving leg nearly straight where it meets and leaves the ground.
@export var push_height := 0.86
## How far the hips drop into each push and rise out of it (m), pushing slowly.
@export var push_bob := 0.05
## How far the trunk goes forward into the drive (radians), pushing slowly.
@export var push_lean := 0.12
## Seconds the arms are asked ahead of the leg, so they swing with it.
@export var push_arm_lead := 0.13
## How far the arms swing in a push (1 = an easy stride; 2 = pumping like a sprinter).
@export var push_arm_swing := 1.0
## Pushes grow with speed: short and upright setting off, at their longest and
## lowest from this speed up (m/s).
@export var push_full_speed := 6.0
## How much longer the stroke gets at speed: the foot reaches further ahead to
## plant and lets go further behind (0 = the same short stroke at any speed).
@export var push_stride := 1.0
## How far the leg carries on back and up after the foot leaves the ground.
@export var push_follow_through := 1.0
## How much lower the rider gets to push at full speed (m), to stay over the board.
@export var push_speed_crouch := 0.06
## How much further forward the trunk goes into a push at full speed (radians).
@export var push_speed_lean := 0.26

@export_group("Balance")
## The lean that keeps the rider over the board, and how it gets there: below 1
## damping overshoots; a negative response leaves the body behind first.
@export var balance_frequency := 1.7
@export var balance_damping := 0.6
@export var balance_response := -0.35
## Share of the physically balanced lean taken, across the board and along it.
@export var lean_gain := 0.6
@export var lean_along_gain := 0.55
@export var lean_limit := 0.42
@export var lean_along_limit := 0.2
## Share of a carve's lean the spine takes back, so the legs lean more than the chest.
@export var angulation := 0.4
## Lean (radians) toward the raised end in a manual.
@export var manual_shift := 0.2

@export_group("Spine")
## Hips turning after the board (reverts, powerslides, landings).
@export var hips_frequency := 2.6
@export var hips_damping := 0.6
## Chest following the hips.
@export var chest_frequency := 2.8
@export var chest_damping := 0.6
## How much the trunk is thrown by the body's own acceleration.
@export var chest_inertia := 0.3
## Extra fold at the waist (radians per metre) as the legs are pushed down.
@export var compression_fold := 1.6
## Shoulders wound against a spin while crouched (radians at full steer).
@export var spin_windup := 0.4
## Seconds the shoulders run ahead of a spin, and of a turn on the ground.
@export var spin_lead := 0.05
@export var turn_lead := 0.14

@export_group("Head")
## How fast the eyes go to what they are looking at (1/s).
@export var head_rate := 9.0
## How level the head stays as the body leans (1 = always level).
@export var head_level := 0.65

@export_group("Arms")
@export var arm_stiffness := 80.0
@export var arm_damping := 14.0
## The elbow is looser than the shoulder, so the forearm trails.
@export var elbow_stiffness := 55.0
@export var elbow_damping := 8.5
## How much the arms are dragged by the shoulders' own motion. 0 = held rigid.
@export var arm_inertia := 0.3
## How much the arms float when light and get pulled down under load.
@export var arm_float := 0.3
## How strongly the arms counter the body's lean.
@export var arm_balance := 1.0
## How much the arms do: the size of their reactions and of the balancing they
## hold in a manual, on a rail or in a long air. 0 = they only hang.
@export var arm_use := 1.0
## How much firmer the arms are held while they are working than hanging loose.
@export var arm_tone := 1.3
## How upright the arms are held while the trunk leans and folds under them:
## 0 = fixed to the chest, 1 = they hang from the shoulders and stay level.
@export var arm_level := 0.8
## Standing still the arms hang; rolling they are a little readier. The speed
## (m/s) from which they are as ready as they get.
@export var arm_ready_speed := 4.0
## How far the arms swing up with a pop (a deep ollie; a quick tap gets less).
@export var pop_arm_lift := 1.0
## How much one gesture differs from the last (0 = every pop the same arms).
@export var arm_variety := 1.0
## The hands: how far a relaxed wrist droops (0 = held in line with the
## forearm) and how quickly the hand follows the arm (lower = it trails more).
@export var wrist_droop := 0.45
@export var wrist_follow := 16.0
## Upward kick on the arms at the pop.
@export var pop_arm_throw := 1.6

@export_group("Feet")
## How far the feet shift on the board to set up a pop (0 = stay in the riding stance).
@export var setup_stance := 1.0
## How much the ankles roll and the heels lift through a pop.
@export var foot_articulation := 1.0

@export_group("Life")
## Breaths per second and how visible they are.
@export var breath_rate := 0.27
@export var breath_amount := 1.0
## The small corrections of someone balancing (more when slow, on a rail or in a manual).
@export var sway_amount := 1.0
