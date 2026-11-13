class_name VerletRagdoll
extends RefCounted

## The physics tick the ragdoll is stepped at (s).
const TICK := 1.0 / 60.0
const RADIUS := 0.055
const JOINTS := [
	"Hips", "Spine", "Chest", "UpperChest", "Neck", "Head", "HeadTop",
	"LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
	"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "LeftToes",
	"RightUpperLeg", "RightLowerLeg", "RightFoot", "RightToes",
]
const BONES := [
	["Hips", "Spine"], ["Spine", "Chest"], ["Chest", "UpperChest"], ["UpperChest", "Neck"], ["Neck", "Head"], ["Head", "HeadTop"],
	["UpperChest", "LeftUpperArm"], ["LeftUpperArm", "LeftLowerArm"], ["LeftLowerArm", "LeftHand"],
	["UpperChest", "RightUpperArm"], ["RightUpperArm", "RightLowerArm"], ["RightLowerArm", "RightHand"],
	["Hips", "LeftUpperLeg"], ["LeftUpperLeg", "LeftLowerLeg"], ["LeftLowerLeg", "LeftFoot"], ["LeftFoot", "LeftToes"],
	["Hips", "RightUpperLeg"], ["RightUpperLeg", "RightLowerLeg"], ["RightLowerLeg", "RightFoot"], ["RightFoot", "RightToes"],
	# Braces that keep the torso and pelvis from folding flat.
	["LeftUpperLeg", "RightUpperLeg"], ["LeftUpperArm", "RightUpperArm"], ["LeftUpperArm", "Spine"], ["RightUpperArm", "Spine"],
	["LeftUpperLeg", "Chest"], ["RightUpperLeg", "Chest"], ["Hips", "UpperChest"], ["Neck", "HeadTop"], ["UpperChest", "Head"],
]

var gravity := 9.8
var hold_time := 0.2
var damping := 0.995
var friction := 0.55
var time := 0.0
var position := {}
var previous := {}
var _rest_length := []
var _hold := {}
var _hold_origin := Vector3.ZERO
var _cast := PhysicsShapeQueryParameters3D.new()
var _sphere := SphereShape3D.new()


func _init() -> void:
	_sphere.radius = RADIUS
	_cast.shape = _sphere


## Start from the skeleton's current pose (world space) moving at `velocity`,
## with an extra `tumble` spin about the hips.
func start(skeleton: Skeleton3D, velocity: Vector3, tumble: Vector3) -> void:
	time = 0.0
	position.clear()
	previous.clear()
	_hold.clear()
	var to_world := skeleton.global_transform
	for joint in JOINTS:
		var p: Vector3
		if joint == "HeadTop":
			p = to_world * (skeleton.get_bone_global_pose(skeleton.find_bone("Head")) * Vector3(0.0, 0.2, 0.0))
		else:
			p = to_world * skeleton.get_bone_global_pose(skeleton.find_bone(joint)).origin
		position[joint] = p
		_hold[joint] = p
	_hold_origin = position.Hips
	var hips: Vector3 = position.Hips
	for joint in JOINTS:
		var p: Vector3 = position[joint]
		var spin := tumble.cross(p - hips)
		previous[joint] = p - (velocity + spin) * TICK
	_rest_length.clear()
	for bone in BONES:
		_rest_length.append((position[bone[0]] as Vector3).distance_to(position[bone[1]]))


func step(space: PhysicsDirectSpaceState3D, dt: float) -> void:
	time += dt
	var g := Vector3(0.0, -gravity, 0.0) * dt * dt
	var hold := 1.0 - smoothstep(0.0, hold_time, time)
	var hips_shift: Vector3 = position.Hips - _hold_origin
	for joint in JOINTS:
		var p: Vector3 = position[joint]
		var motion: Vector3 = (p - previous[joint]) * damping
		previous[joint] = p
		var next := p + motion + g
		if hold > 0.0:
			# Fading drive toward the bail pose, carried along with the hips.
			var target: Vector3 = _hold[joint] + hips_shift
			next = next.lerp(target, hold * 0.12)
		position[joint] = next
	for _iteration in 6:
		for i in BONES.size():
			var a: String = BONES[i][0]
			var b: String = BONES[i][1]
			var pa: Vector3 = position[a]
			var pb: Vector3 = position[b]
			var delta := pb - pa
			var length := delta.length()
			if length < 1e-6:
				continue
			var correction: Vector3 = delta * ((length - _rest_length[i]) / length * 0.5)
			position[a] = pa + correction
			position[b] = pb - correction
	for joint in JOINTS:
		_collide(space, joint)


## Keep a particle out of the level, scrubbing its sliding speed on contact.
func _collide(space: PhysicsDirectSpaceState3D, joint: String) -> void:
	var from: Vector3 = previous[joint]
	var to: Vector3 = position[joint]
	_cast.transform = Transform3D(Basis.IDENTITY, from)
	_cast.motion = to - from
	var result := space.cast_motion(_cast)
	if result.is_empty() or result[0] >= 1.0:
		return
	var safe := from + (to - from) * result[0]
	_cast.transform = Transform3D(Basis.IDENTITY, safe + (to - from) * 0.02)
	_cast.motion = Vector3.ZERO
	var info := space.get_rest_info(_cast)
	var normal: Vector3 = info.get("normal", Vector3.UP)
	var velocity := to - from
	var into := velocity.dot(normal)
	var tangent := velocity - normal * into
	# Land at the contact point, keep a damped slide along the surface.
	position[joint] = safe + tangent * (1.0 - friction)
	previous[joint] = safe


## Mean particle speed (m/s), for "has the body settled".
func speed() -> float:
	var total := 0.0
	for joint in JOINTS:
		total += ((position[joint] as Vector3) - previous[joint]).length()
	return total / JOINTS.size() / TICK
