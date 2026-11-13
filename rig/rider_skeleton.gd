class_name RiderSkeleton

## bone name -> [parent, rest joint position in skeleton space]
const JOINTS := {
	"Hips": ["", Vector3(0.0, 0.98, 0.0)],
	"Spine": ["Hips", Vector3(0.0, 1.08, 0.0)],
	"Chest": ["Spine", Vector3(0.0, 1.22, 0.0)],
	"UpperChest": ["Chest", Vector3(0.0, 1.35, 0.0)],
	"Neck": ["UpperChest", Vector3(0.0, 1.49, 0.0)],
	"Head": ["Neck", Vector3(0.0, 1.58, 0.0)],
	"LeftShoulder": ["UpperChest", Vector3(0.04, 1.45, 0.0)],
	"LeftUpperArm": ["LeftShoulder", Vector3(0.23, 1.45, 0.0)],
	"LeftLowerArm": ["LeftUpperArm", Vector3(0.51, 1.45, 0.0)],
	"LeftHand": ["LeftLowerArm", Vector3(0.76, 1.45, 0.0)],
	"RightShoulder": ["UpperChest", Vector3(-0.04, 1.45, 0.0)],
	"RightUpperArm": ["RightShoulder", Vector3(-0.23, 1.45, 0.0)],
	"RightLowerArm": ["RightUpperArm", Vector3(-0.51, 1.45, 0.0)],
	"RightHand": ["RightLowerArm", Vector3(-0.76, 1.45, 0.0)],
	"LeftUpperLeg": ["Hips", Vector3(0.1, 0.93, 0.0)],
	"LeftLowerLeg": ["LeftUpperLeg", Vector3(0.1, 0.505, 0.0)],
	"LeftFoot": ["LeftLowerLeg", Vector3(0.1, 0.08, 0.0)],
	"LeftToes": ["LeftFoot", Vector3(0.1, 0.02, 0.13)],
	"RightUpperLeg": ["Hips", Vector3(-0.1, 0.93, 0.0)],
	"RightLowerLeg": ["RightUpperLeg", Vector3(-0.1, 0.505, 0.0)],
	"RightFoot": ["RightLowerLeg", Vector3(-0.1, 0.08, 0.0)],
	"RightToes": ["RightFoot", Vector3(-0.1, 0.02, 0.13)],
}

## First child of each bone, which sets the direction of its +Y axis.
const AIM := {
	"Hips": "Spine", "Spine": "Chest", "Chest": "UpperChest", "UpperChest": "Neck", "Neck": "Head",
	"LeftShoulder": "LeftUpperArm", "LeftUpperArm": "LeftLowerArm", "LeftLowerArm": "LeftHand",
	"RightShoulder": "RightUpperArm", "RightUpperArm": "RightLowerArm", "RightLowerArm": "RightHand",
	"LeftUpperLeg": "LeftLowerLeg", "LeftLowerLeg": "LeftFoot", "LeftFoot": "LeftToes",
	"RightUpperLeg": "RightLowerLeg", "RightLowerLeg": "RightFoot", "RightFoot": "RightToes",
}


static func build() -> Skeleton3D:
	var skeleton := Skeleton3D.new()
	skeleton.name = "Skeleton3D"
	var globals := {}
	for bone in JOINTS:
		var parent: String = JOINTS[bone][0]
		var position: Vector3 = JOINTS[bone][1]
		var global := Transform3D(rest_basis(bone), position)
		globals[bone] = global
		var index := skeleton.add_bone(bone)
		var local := global
		if parent != "":
			skeleton.set_bone_parent(index, skeleton.find_bone(parent))
			local = (globals[parent] as Transform3D).affine_inverse() * global
		skeleton.set_bone_rest(index, local)
		skeleton.set_bone_pose_position(index, local.origin)
		skeleton.set_bone_pose_rotation(index, local.basis.get_rotation_quaternion())
	return skeleton


## +Y along the bone toward its child, +Z toward the character's front.
static func rest_basis(bone: String) -> Basis:
	var position: Vector3 = JOINTS[bone][1]
	var y := Vector3.UP
	if AIM.has(bone):
		y = ((JOINTS[AIM[bone]][1] as Vector3) - position).normalized()
	elif bone.ends_with("Hand"):
		y = Vector3(signf(position.x), 0.0, 0.0)
	elif bone.ends_with("Toes"):
		y = Vector3.BACK
	var z_hint := Vector3.BACK if absf(y.dot(Vector3.BACK)) < 0.9 else Vector3.UP
	return basis_from_y(y, z_hint)


## Orthonormal basis with +Y along `y` and +Z as close to `z_hint` as possible.
static func basis_from_y(y: Vector3, z_hint: Vector3) -> Basis:
	y = y.normalized()
	var z := (z_hint - y * y.dot(z_hint))
	if z.length_squared() < 1e-8:
		z = Vector3.BACK if absf(y.z) < 0.9 else Vector3.RIGHT
		z = (z - y * y.dot(z))
	z = z.normalized()
	return Basis(y.cross(z), y, z)
