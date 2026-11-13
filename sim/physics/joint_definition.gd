class_name JointDefinition
extends RefCounted

## How the joint holds the two swing axes: both locked, within a cone, a
## hinge about B's Y (with or without a limit), or free.
enum Swing { LOCKED, CONE, LIMITED_HINGE, HINGE, FREE }
## How it holds the twist about A's X: locked, within a limit, or free.
enum Twist { LOCKED, LIMITED, FREE }

## Body indices of bodies A and B.
var body_a := 0
var body_b := 0
var linear_slack := Vector3.ZERO
var linear_speed_limit := Vector3.ZERO
var twist_speed_limit := 0.0
var swing_speed_limit := 0.0
var swing_limit_cosine := 1.0
var twist_limit_cosine := 1.0
var swing_kind := Swing.LOCKED
var twist_kind := Twist.LOCKED
var orientation_a := Quaternion.IDENTITY
var anchor_a := Vector3.ZERO
var orientation_b := Quaternion.IDENTITY
var anchor_b := Vector3.ZERO
var linear_frame_b := Quaternion.IDENTITY
