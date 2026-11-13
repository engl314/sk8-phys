class_name RiderPose
extends RefCounted

var hips := Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, 0.0))
## Global orientation the upper chest should reach (spread over the spine).
var chest := Basis.IDENTITY
## Global orientation of the head (spread over neck and head).
var head := Basis.IDENTITY
## Ankle positions, toe directions and sole normals.
var foot_l := Vector3(0.1, 0.08, 0.0)
var foot_r := Vector3(-0.1, 0.08, 0.0)
var toe_l := Vector3.BACK
var toe_r := Vector3.BACK
var sole_l := Vector3.UP
var sole_r := Vector3.UP
## Where each knee points.
var knee_l := Vector3.BACK
var knee_r := Vector3.BACK
## Wrist positions and elbow directions.
var hand_l := Vector3(0.3, 0.9, 0.0)
var hand_r := Vector3(-0.3, 0.9, 0.0)
var elbow_l := Vector3.BACK
var elbow_r := Vector3.BACK
## Which way each hand points from the wrist (zero: in line with the forearm).
var hand_dir_l := Vector3.ZERO
var hand_dir_r := Vector3.ZERO
## How far each shoulder is shrugged up toward the ear (radians at the collarbone).
var shoulder_lift_l := 0.0
var shoulder_lift_r := 0.0
