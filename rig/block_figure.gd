class_name BlockFigure
extends Node3D

const GLASS := preload("res://rig/glass.gdshader")

## [bone, width, depth, light]: a box running the length of the bone. The arms
## hang beside the chest, not in it: the shoulder joints sit half an arm's
## width outside the chest block (see RiderSkeleton), so an arm at the rider's
## side lies flush against the body.
const LIMBS := [
	["LeftUpperArm", 0.11, 0.12, true], ["LeftLowerArm", 0.1, 0.105, false],
	["RightUpperArm", 0.11, 0.12, false], ["RightLowerArm", 0.1, 0.105, true],
	["LeftUpperLeg", 0.17, 0.18, true], ["LeftLowerLeg", 0.145, 0.15, false],
	["RightUpperLeg", 0.17, 0.18, false], ["RightLowerLeg", 0.145, 0.15, true],
]
## [bone, size, centre in the bone's frame, light].
const BLOCKS := [
	["Hips", Vector3(0.34, 0.18, 0.24), Vector3(0.0, -0.01, 0.0), false],
	["Spine", Vector3(0.3, 0.14, 0.2), Vector3(0.0, 0.075, 0.0), true],
	["UpperChest", Vector3(0.35, 0.3, 0.26), Vector3(0.0, 0.0, 0.0), true],
	["Neck", Vector3(0.11, 0.1, 0.11), Vector3(0.0, 0.045, 0.0), false],
	["Head", Vector3(0.28, 0.3, 0.29), Vector3(0.0, 0.16, 0.01), true],
	["LeftHand", Vector3(0.1, 0.12, 0.09), Vector3(0.0, 0.055, 0.0), true],
	["RightHand", Vector3(0.1, 0.12, 0.09), Vector3(0.0, 0.055, 0.0), false],
	# Feet in the toes' frame (+Y along the foot, +Z up off the sole): the toe
	# joint sits 0.015 above the sole, 0.13 ahead of the ankle.
	["LeftToes", Vector3(0.12, 0.28, 0.08), Vector3(0.0, -0.07, 0.025), true],
	["RightToes", Vector3(0.12, 0.28, 0.08), Vector3(0.0, -0.07, 0.025), false],
]

@export var light_color := Color(0.84, 0.86, 0.9)
@export var dark_color := Color(0.07, 0.09, 0.2)
## How much of each block's own colour covers the glass (the shader's color_coat).
@export var tint := 0.7

var skeleton: Skeleton3D
var _blocks: Array[MeshInstance3D] = []
var _shadows: Array[MeshInstance3D] = []
## Per block: bone index and the box's place in that bone's frame.
var _bones: Array[int] = []
var _offsets: Array[Transform3D] = []


func setup(target: Skeleton3D) -> void:
	skeleton = target
	var light := _material(light_color)
	var dark := _material(dark_color)
	for limb in LIMBS:
		var bone := skeleton.find_bone(limb[0])
		var length := _length(bone)
		_add(bone, Vector3(limb[1], length, limb[2]), Vector3(0.0, length * 0.5, 0.0), light if limb[3] else dark)
	for block in BLOCKS:
		_add(skeleton.find_bone(block[0]), block[1], block[2], light if block[3] else dark)


## Re-place the blocks from the skeleton's current pose (skeleton space).
func sync() -> void:
	if skeleton == null:
		return
	for i in _blocks.size():
		var t := skeleton.get_bone_global_pose(_bones[i]) * _offsets[i]
		_blocks[i].transform = t
		_shadows[i].transform = t


func _add(bone: int, size: Vector3, centre: Vector3, material: Material) -> void:
	var box := BoxMesh.new()
	box.size = size
	var instance := MeshInstance3D.new()
	instance.mesh = box
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(instance)
	_blocks.append(instance)
	var shadow := MeshInstance3D.new()
	shadow.mesh = box
	shadow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
	add_child(shadow)
	_shadows.append(shadow)
	_bones.append(bone)
	_offsets.append(Transform3D(Basis.IDENTITY, centre))


## Distance from a bone to its first child (its rest length).
func _length(bone: int) -> float:
	for child in skeleton.get_bone_children(bone):
		return skeleton.get_bone_rest(child).origin.length()
	return 0.1


func _material(color: Color) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = GLASS
	material.set_shader_parameter("color", color)
	material.set_shader_parameter("color_coat", tint)
	material.set_shader_parameter("rim_amount", 0.45)
	material.set_shader_parameter("refraction_strength", 0.3)
	material.set_shader_parameter("blur_amount", 3.0)
	material.set_shader_parameter("roughness", 0.15)
	return material
