class_name RiderPoseSolver
extends RefCounted

const SPINE := ["Spine", "Chest", "UpperChest"]
const SPINE_SHARE := [0.35, 0.7, 1.0]
## Foot bones point toward the toes and slightly down at rest.
const FOOT_PITCH := 0.43

var skeleton: Skeleton3D
var _bone := {}
var _rest_offset := {}
var _global := {}
var upper_leg_length := 0.425
var lower_leg_length := 0.425
var upper_arm_length := 0.28
var lower_arm_length := 0.25


func _init(target: Skeleton3D) -> void:
	skeleton = target
	for i in skeleton.get_bone_count():
		var name := skeleton.get_bone_name(i)
		_bone[name] = i
		_rest_offset[name] = skeleton.get_bone_rest(i).origin
	upper_leg_length = (_rest_offset.LeftLowerLeg as Vector3).length()
	lower_leg_length = (_rest_offset.LeftFoot as Vector3).length()
	upper_arm_length = (_rest_offset.LeftLowerArm as Vector3).length()
	lower_arm_length = (_rest_offset.LeftHand as Vector3).length()


func leg_length() -> float:
	return upper_leg_length + lower_leg_length


## Hip joint position for one side under a given hips transform.
func hip_joint(hips: Transform3D, left: bool) -> Vector3:
	return hips * (_rest_offset["LeftUpperLeg" if left else "RightUpperLeg"] as Vector3)


## Upper-arm (shoulder) joint for one side under the given hips and chest, where
## apply() will put it. `lift` shrugs the collarbone up (radians).
func shoulder_joint(hips: Transform3D, chest: Basis, left: bool, lift := 0.0) -> Vector3:
	var hips_q := hips.basis.get_rotation_quaternion()
	var chest_q := chest.get_rotation_quaternion()
	var t := hips
	for i in SPINE.size():
		t = Transform3D(Basis(hips_q.slerp(chest_q, SPINE_SHARE[i])), t * (_rest_offset[SPINE[i]] as Vector3))
	var side := "Left" if left else "Right"
	var shoulder := Transform3D(_collarbone(chest, left, lift), t * (_rest_offset[side + "Shoulder"] as Vector3))
	return shoulder * (_rest_offset[side + "UpperArm"] as Vector3)


## The shoulder bone's basis: out along the chest, tipped up by `lift`.
static func _collarbone(chest: Basis, left: bool, lift: float) -> Basis:
	var outward := (chest.x if left else -chest.x) * cos(lift) + chest.y * sin(lift)
	return RiderSkeleton.basis_from_y(outward, chest.z).orthonormalized()


func apply(pose: RiderPose) -> void:
	_global.clear()
	_set_global("Hips", pose.hips)
	var hips_q := pose.hips.basis.get_rotation_quaternion()
	var chest_q := pose.chest.get_rotation_quaternion()
	var parent := "Hips"
	for i in SPINE.size():
		_set_child(SPINE[i], parent, Basis(hips_q.slerp(chest_q, SPINE_SHARE[i])))
		parent = SPINE[i]
	var head_q := pose.head.get_rotation_quaternion()
	_set_child("Neck", "UpperChest", Basis(chest_q.slerp(head_q, 0.45)))
	_set_child("Head", "Neck", Basis(head_q))
	_leg(true, pose.foot_l, pose.toe_l, pose.sole_l, pose.knee_l)
	_leg(false, pose.foot_r, pose.toe_r, pose.sole_r, pose.knee_r)
	_arm(true, pose.hand_l, pose.elbow_l, pose.chest, pose.shoulder_lift_l, pose.hand_dir_l)
	_arm(false, pose.hand_r, pose.elbow_r, pose.chest, pose.shoulder_lift_r, pose.hand_dir_r)
	_write()


## Pose the skeleton from joint positions (skeleton space), e.g. a ragdoll's.
## Only rotations are derived; bones keep their rest lengths.
func apply_positions(p: Dictionary) -> void:
	_global.clear()
	var left: Vector3 = p.LeftUpperLeg - p.RightUpperLeg
	var spine_up: Vector3 = p.Spine - p.Hips
	var hips_basis := RiderSkeleton.basis_from_y(spine_up, left.cross(spine_up))
	_set_global("Hips", Transform3D(hips_basis, p.Hips))
	var front := hips_basis.z
	var chain := [["Spine", "Hips", "Chest"], ["Chest", "Spine", "UpperChest"], ["UpperChest", "Chest", "Neck"],
		["Neck", "UpperChest", "Head"], ["Head", "Neck", "HeadTop"]]
	for link in chain:
		_set_child(link[0], link[1], RiderSkeleton.basis_from_y((p[link[2]] as Vector3) - (p[link[0]] as Vector3), front))
	for side in ["Left", "Right"]:
		var outward: Vector3 = (p[side + "UpperArm"] as Vector3) - (p.UpperChest as Vector3)
		_set_child(side + "Shoulder", "UpperChest", RiderSkeleton.basis_from_y(outward, front))
		for link in [["UpperArm", "Shoulder", "LowerArm"], ["LowerArm", "UpperArm", "Hand"]]:
			_set_child(side + link[0], side + link[1], RiderSkeleton.basis_from_y((p[side + link[2]] as Vector3) - (p[side + link[0]] as Vector3), front))
		_set_child(side + "Hand", side + "LowerArm", (_global[side + "LowerArm"] as Transform3D).basis)
		_set_child(side + "UpperLeg", "Hips", RiderSkeleton.basis_from_y((p[side + "LowerLeg"] as Vector3) - (p[side + "UpperLeg"] as Vector3), front))
		_set_child(side + "LowerLeg", side + "UpperLeg", RiderSkeleton.basis_from_y((p[side + "Foot"] as Vector3) - (p[side + "LowerLeg"] as Vector3), front))
		var toe: Vector3 = (p[side + "Toes"] as Vector3) - (p[side + "Foot"] as Vector3)
		var shin: Vector3 = (p[side + "LowerLeg"] as Vector3) - (p[side + "Foot"] as Vector3)
		_set_child(side + "Foot", side + "LowerLeg", RiderSkeleton.basis_from_y(toe, shin))
		_set_child(side + "Toes", side + "Foot", RiderSkeleton.basis_from_y(toe, shin))
	_write()


func _write() -> void:
	for name in _global:
		var index: int = _bone[name]
		var global: Transform3D = _global[name]
		var parent_index := skeleton.get_bone_parent(index)
		var local := global
		if parent_index >= 0:
			local = (_global[skeleton.get_bone_name(parent_index)] as Transform3D).affine_inverse() * global
		skeleton.set_bone_pose_position(index, local.origin)
		skeleton.set_bone_pose_rotation(index, local.basis.get_rotation_quaternion())


func _set_global(name: String, transform: Transform3D) -> void:
	_global[name] = transform


## Child bone at its rest offset from the parent, with the given global basis.
func _set_child(name: String, parent: String, basis: Basis) -> Transform3D:
	var origin := (_global[parent] as Transform3D) * (_rest_offset[name] as Vector3)
	var t := Transform3D(basis.orthonormalized(), origin)
	_global[name] = t
	return t


func _leg(left: bool, ankle: Vector3, toe: Vector3, sole: Vector3, knee_dir: Vector3) -> void:
	var side := "Left" if left else "Right"
	var hip := (_global.Hips as Transform3D) * (_rest_offset[side + "UpperLeg"] as Vector3)
	var solved := TwoBoneIK.solve(hip, upper_leg_length, lower_leg_length, ankle, knee_dir)
	var knee: Vector3 = solved[0]
	var end: Vector3 = solved[1]
	_set_child(side + "UpperLeg", "Hips", RiderSkeleton.basis_from_y(knee - hip, knee_dir))
	_set_child(side + "LowerLeg", side + "UpperLeg", RiderSkeleton.basis_from_y(end - knee, knee_dir))
	var toe_flat := (toe - sole * sole.dot(toe)).normalized()
	var foot_y := (toe_flat * cos(FOOT_PITCH) - sole * sin(FOOT_PITCH)).normalized()
	_set_child(side + "Foot", side + "LowerLeg", RiderSkeleton.basis_from_y(foot_y, sole))
	_set_child(side + "Toes", side + "Foot", RiderSkeleton.basis_from_y(toe_flat, sole))


func _arm(left: bool, hand: Vector3, elbow_dir: Vector3, chest: Basis, lift: float, hand_dir: Vector3) -> void:
	var side := "Left" if left else "Right"
	_set_child(side + "Shoulder", "UpperChest", _collarbone(chest, left, lift))
	var shoulder := (_global[side + "Shoulder"] as Transform3D) * (_rest_offset[side + "UpperArm"] as Vector3)
	var solved := TwoBoneIK.solve(shoulder, upper_arm_length, lower_arm_length, hand, elbow_dir)
	var elbow: Vector3 = solved[0]
	var wrist: Vector3 = solved[1]
	_set_child(side + "UpperArm", side + "Shoulder", RiderSkeleton.basis_from_y(elbow - shoulder, elbow_dir))
	_set_child(side + "LowerArm", side + "UpperArm", RiderSkeleton.basis_from_y(wrist - elbow, elbow_dir))
	var pointing := hand_dir if hand_dir.length_squared() > 1e-6 else wrist - elbow
	_set_child(side + "Hand", side + "LowerArm", RiderSkeleton.basis_from_y(pointing, elbow_dir))
