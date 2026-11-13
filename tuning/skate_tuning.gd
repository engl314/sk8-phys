class_name SkateTuning
extends Resource

@export_group("World")
@export var gravity := 9.8
@export var solver_iterations := 50
## Wheel / floor contact materials. The floor's
## restitution of 1 means the wheel's (lower) restitution always wins.
@export var wheel_static_friction := 0.9
@export var wheel_dynamic_friction := 0.7
@export var wheel_restitution := 0.0
## Wheel angular drag: in contact, in the air (stored x 60).
@export var wheel_angular_drag_air := 0.006

@export_group("Rolling")
## Speeding up / slowing down: fraction of the speed error closed per tick.
@export var rolling_gain_up := 0.6
@export var rolling_gain_down := 0.6
## How far the target speed may stray from the measured speed.
@export var rolling_target_slack := 0.12
@export var slope_gravity := 9.8
@export var slope_max_acceleration := 9.0
## Rolling resistance (m/s^2) against surface speed (m/s).
@export var rolling_resistance := LinearCurve.make([[0.0, 0.1], [4.0, 0.16], [8.0, 0.3], [14.0, 0.55]])
## Extra friction after this many seconds without input.
@export var idle_friction_delay := 2.5
@export var idle_friction := LinearCurve.make([[0.0, 0.04], [10.0, 0.08]])
@export var manual_friction := LinearCurve.make([[0.0, 0.22], [10.0, 0.4]])

@export_group("Steering")
## Truck angle (rad) at full steer before the speed and input curves.
@export var steer_truck_angle := 0.28
@export var steer_sharp_turn_boost := 0.6
## Per-tick blend of the turn input (1 = no smoothing).
@export var steer_input_blend := 0.22
@export var steer_speed_range := 10.0
@export var steer_vs_speed := LinearCurve.make([[0.0, 1.0], [0.3, 0.9], [1.0, 0.55]])
@export var steer_response := LinearCurve.make([[0.0, 0.0], [0.5, 0.42], [1.0, 1.0]])
@export var steer_push_recovery := 0.04
@export var steer_push_loss := 0.04
@export var steer_push_minimum := 0.55
@export var steer_in_manual := 0.45
@export var truck_follow_blend := 0.35

@export_group("Side grip")
## Lateral force per m/s of side slip.
@export var grip_strength := 36.0
## Seconds after landing over which grip ramps in.
@export var grip_ramp_time := 0.35
@export var grip_ramp := LinearCurve.make([[0.0, 0.35], [1.0, 1.0]])
## Loss of grip with slope angle (normalized 0..1 of 90 degrees) and speed/10.
@export var grip_loss_vs_slope := LinearCurve.make([[0.0, 0.0], [0.6, 0.1], [1.0, 0.5]])
@export var grip_loss_vs_speed := LinearCurve.make([[0.0, 0.0], [1.0, 0.15]])
## Grip scale for the softest wheels, blended by wheel hardness.
@export var grip_soft_wheels := 0.7
@export var wheel_hardness := 1.0

@export_group("Line up")
## Line-up force: yaw (rad/tick) per m/s of sideways velocity error.
@export var line_up_strength := 0.012
@export var line_up_ramp := LinearCurve.make([[0.0, 0.2], [1.0, 1.0]])
@export var line_up_steer_cutoff := 0.6
@export var line_up_ramp_soft_wheels := 0.6

@export_group("Turning")
## Direct turn request: yaw displacement per tick at full steer.
@export var turn_strength := 0.014
@export var turn_vs_speed := LinearCurve.make([[0.0, 0.75], [2.5, 1.0], [7.0, 0.85], [12.0, 0.55]])
## Extra authority when spinning against the steer.
@export var turn_against_spin := LinearCurve.make([[0.0, 1.0], [3.0, 1.6]])
## Fall-line assist on slopes.
@export var fall_line_strength := 0.004
@export var fall_line_speed_range := 10.0
@export var fall_line_vs_speed := LinearCurve.make([[0.0, 0.0], [0.3, 1.0], [1.0, 1.0]])
@export var fall_line_vs_slope := LinearCurve.make([[0.0, 0.0], [0.05, 0.0], [0.4, 1.0]])
@export var manual_turn_rate := LinearCurve.make([[0.0, 60.0], [10.0, 30.0]])
@export var manual_turn_blend := 0.15
@export var manual_turn_wrong_wheels := 0.5

@export_group("Levelling")
## Restoring roll/pitch (rad/tick) against the angle from the riding plane
## (normalized 0..1 of 90 degrees).
@export var level_pitch_vs_angle := LinearCurve.make([[0.0, 0.0], [0.25, 0.0], [0.6, 0.012], [1.0, 0.03]])
@export var level_roll_vs_angle := LinearCurve.make([[0.0, 0.0], [0.12, 0.0], [0.5, 0.012], [1.0, 0.03]])

@export_group("Rider weight")
## Rider weight on the board: each foot pushes down this far (m) either side of the deck centre.
@export var foot_spacing := 0.2
## Weight through each foot just after landing, easing over landing_weight_time
## to riding_weight * speed/8.
@export var landing_weight := 260.0
@export var riding_weight := 140.0
@export var landing_weight_time := 0.3

@export_group("Push")
@export var push_top_speed := 8.0
## Per-tick speed change cap at standstill and at maximum pushable speed. These
## are what limit a push in practice: one from a standstill gives about 1.8 m/s.
@export var push_cap_standstill := 0.12
@export var push_cap_top_speed := 0.05
## Speed gained by one push against current speed.
@export var push_gain_vs_speed := LinearCurve.make([[0.0, 2.0], [3.0, 1.6], [6.0, 1.1], [8.0, 0.5]])
@export var push_reach_time := 0.16
@export var push_drive_time := 0.26
@export var push_swing_time := 0.24
## Pushing at speed is not one stroke straight after another: the rider glides
## a moment with the leg behind before the next. Seconds of that at maximum
## pushable speed, and the speed below which there is none.
@export var push_hang_time := 0.25
@export var push_hang_from_speed := 2.5
## Pushes queued while one is running chain straight into the next.
@export var push_buffer_time := 0.35

@export_group("Brakes")
@export var foot_brake_force := 55.0
@export var tail_brake_force := 85.0
@export var brake_cutoff_speed := 0.15
## Below 2x this speed a held brake applies full linear drag (a dead stop).
@export var brake_hold_speed := 0.35

@export_group("Powerslide")
## Board angle at full slide: 0.5 = 90 degrees across the direction of travel.
@export var slide_full_angle := 0.5
@export var slide_build_rate := 3.5
@export var slide_angle_response := LinearCurve.make([[0.0, 0.0], [0.5, 0.42], [1.0, 1.0]])
@export var slide_response_vs_speed := LinearCurve.make([[0.0, 0.0], [10.0, 0.0]])
@export var slide_side_drag_vs_angle := LinearCurve.make([[0.0, 0.0], [90.0, 0.0]])
@export var slide_side_drag_vs_speed := LinearCurve.make([[0.0, 0.0], [10.0, 0.0]])
## Powerslide drag per m/s of sideways slip (negative opposes travel).
@export var slide_drag := LinearCurve.make([[0.0, -5.0], [3.0, -9.0], [8.0, -12.0]])
@export var slide_drag_soft_wheels := 0.6
@export var slide_yaw_soft_wheels := 0.8
@export var slide_yaw_scale := 0.11
@export var slide_yaw_spring := 0.6
@export var slide_yaw_damping := -0.02
@export var slide_drag_height := -0.05
@export var slide_start_speed := 1.2
## Wheel contact material while sliding (the wheels skid instead of rolling).
@export var slide_wheel_static_friction := 0.14
@export var slide_wheel_dynamic_friction := 0.1

@export_group("Air")
## Ground -> air after this long without contact, air -> ground after this long in the air.
@export var min_air_time := 0.08


func wheel_material() -> ContactMaterial:
	return ContactMaterial.make(wheel_static_friction, wheel_dynamic_friction, wheel_restitution)

@export_group("Pop")
## Target centre-of-mass height above the ground (m), between
## the weakest and strongest flick, scaled by speed. Pop speed is
## sqrt(2 g (target - current COM height)), so crouching first pops higher.
@export var pop_base_height := 0.8
@export var pop_weak_height := 0.92
@export var pop_strong_height := 1.13
@export var pop_speed_range := 8.0
@export var pop_weak_vs_speed := LinearCurve.make([[0.0, 0.9], [1.0, 1.08]])
@export var pop_strong_vs_speed := LinearCurve.make([[0.0, 0.92], [1.0, 1.08]])
## Pop along the ground normal, weaker on steep ground (slope fraction of 90 deg).
@export var pop_vs_slope := LinearCurve.make([[0.0, 1.0], [0.5, 0.85], [1.0, 0.7]])
@export var pop_slope_minimum := 0.5
## The steer nudges the pop direction: sideways (x) and forward (z) factors.
@export var pop_steer_sideways := 0.06
@export var pop_steer_forward := 0.05

@export_group("Air")
## Body spin (A/D in the air): top speed and how fast it is reached.
@export var spin_top_speed_degrees := 560.0
@export var spin_acceleration_degrees := 3600.0
## Spin assist: in the last moments of air, turn toward the nearer rolling direction.
@export var landing_align_time := 0.22
@export var landing_align_strength := 1.2
## Board-to-travel angle that still lands, against tangential speed.
@export var landable_angle := LinearCurve.make([[0.0, 70.0], [3.0, 52.0], [8.0, 40.0]])
## Guide drive while airborne (angular only): spring / strength.
@export var air_pose_spring := 20000.0
@export var air_pose_strength := 36000.0
## The pop's pitch carries momentum: how fast the board answers its key angles
## (Hz) and how much it swings past them (lower damping = more).
@export var pop_pitch_frequency := 7.0
@export var pop_pitch_damping := 0.6
## Degrees the board rolls and turns as the front foot drags the nose up.
@export var pop_style_degrees := 7.0
## Degrees the board rocks as the feet catch a flip.
@export var catch_wobble_degrees := 5.0

@export_group("Manual")
## Deck pitch target = manual_tilt_degrees * (0.25 + 0.75 |balance|).
@export var manual_tilt_degrees := 9.0
@export var manual_brake_degrees := 15.0
## Velocity-form PID: the correction accumulates.
@export var manual_proportional := 0.012
@export var manual_integral := 0.002
@export var manual_derivative := -0.35
@export var manual_error_limit_degrees := 10.0
@export var manual_derivative_limit := 0.02
@export var manual_start_kick := 0.15
## Supported by the wrong wheels: the correction bleeds away.
@export var manual_off_wheels_bleed := 0.6
@export var manual_off_wheels_scale := 0.4
## Procedural wobble the player has to ride through.
@export var manual_wobble_rate := 0.6
@export var manual_wobble_degrees := 2.5
@export var manual_wobble_vs_speed := LinearCurve.make([[0.0, 0.3], [6.0, 1.0]])
## Balance (0..1) a held manual asks for. Past manual_brake_threshold (S held) the
## deck tips onto its tail as a brake.
@export var manual_balance := 0.45
@export var manual_brake_threshold := 0.86

@export_group("Revert")
## A powerslide started just after landing pivots the board 180 on its wheels.
@export var revert_window := 0.3

@export_group("Pumping")
## Speed from standing up while the ground curves under you.
## Only rising centre-of-mass counts (smoothed, per tick, in metres).
@export var pump_rise_smoothing := 0.3
@export var pump_min_rise := 0.0006
@export var pump_max_rise := 0.02
@export var pump_fade := LinearCurve.make([[0.0, 1.0], [0.5, 1.0], [1.0, 0.5]])
@export var pump_speed_response := LinearCurve.make([[0.0, 0.4], [3.0, 1.0], [10.0, 0.6]])
@export var pump_curve_smoothing := 0.4
@export var pump_speed_up_factor := 6.0
@export var pump_slow_down_factor := 0.8
@export var pump_max_speed_up := 7.0
@export var pump_max_slow_down := 3.0
## Pumps the player did not ask for count for less.
@export var auto_pump_share := 0.35
