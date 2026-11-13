@tool
class_name TestPark
extends Node3D

const HEIGHT := -0.035
const FLOOR_HEIGHT := HEIGHT - 1.5
const HALF_PIPE_RADIUS := 2.5

## Where the skater starts: on the platform, facing +Z down the ramp.
const SPAWN := Transform3D(Basis.IDENTITY, Vector3(0.0, HEIGHT, 0.0))

@export var rebuild := false:
	set(value):
		if value:
			_build()

var _quads: Array = []


func _ready() -> void:
	_build()


func _build() -> void:
	for child in get_children():
		child.free()
	_quads.clear()
	_add_floor()
	_add_platform()
	_add_half_pipe()
	_add_climbing_block()
	_add_kicker(Vector3(-8.0, FLOOR_HEIGHT, 10.0), 1.2, 0.35, 1.6)
	_add_box(Vector3(-14.0, FLOOR_HEIGHT, 4.0), Vector3(-12.0, FLOOR_HEIGHT + 0.25, 12.0))
	var colors := [Color(0.47, 0.48, 0.5), Color(0.62, 0.6, 0.56), Color(0.55, 0.57, 0.62), Color(0.5, 0.5, 0.48)]
	_emit("Course", colors[1])
	_add_rails()


func _add_floor() -> void:
	var f := FLOOR_HEIGHT
	_quads.append([Vector3(-50, f, -50), Vector3(50, f, -50), Vector3(50, f, 50), Vector3(-50, f, 50)])


func _add_platform() -> void:
	var top := [Vector3(-3, HEIGHT, -4), Vector3(3, HEIGHT, -4), Vector3(3, HEIGHT, 4), Vector3(-3, HEIGHT, 4)]
	_quads.append(top)
	for i in [0, 1, 3]:
		var a: Vector3 = top[i]
		var b: Vector3 = top[(i + 1) % 4]
		_quads.append([b, a, Vector3(a.x, FLOOR_HEIGHT, a.z), Vector3(b.x, FLOOR_HEIGHT, b.z)])
	# Downhill straight ahead from spawn, eased into both horizontal surfaces.
	var segments := 48
	var length := 12.0
	var point := func(i: int) -> Vector2:
		var t := float(i) / segments
		var blend := t * t * (3.0 - 2.0 * t)
		return Vector2(4.0 + length * t, HEIGHT + (FLOOR_HEIGHT - HEIGHT) * blend)
	for i in segments:
		var p0: Vector2 = point.call(i)
		var p1: Vector2 = point.call(i + 1)
		_quads.append([Vector3(-3, p0.y, p0.x), Vector3(3, p0.y, p0.x), Vector3(3, p1.y, p1.x), Vector3(-3, p1.y, p1.x)])


func _add_half_pipe() -> void:
	var segments := 32
	var profile: Array[Vector2] = []
	for i in range(segments, -1, -1):
		var angle := PI * 0.5 * i / segments
		profile.append(Vector2(12.0 - 2.0 - HALF_PIPE_RADIUS * sin(angle), FLOOR_HEIGHT + HALF_PIPE_RADIUS * (1.0 - cos(angle))))
	for i in segments + 1:
		var angle := PI * 0.5 * i / segments
		profile.append(Vector2(12.0 + 2.0 + HALF_PIPE_RADIUS * sin(angle), FLOOR_HEIGHT + HALF_PIPE_RADIUS * (1.0 - cos(angle))))
	for i in profile.size() - 1:
		var p0 := profile[i]
		var p1 := profile[i + 1]
		if p0.y == FLOOR_HEIGHT and p1.y == FLOOR_HEIGHT:
			continue
		_quads.append([Vector3(p0.x, p0.y, -6), Vector3(p1.x, p1.y, -6), Vector3(p1.x, p1.y, 6), Vector3(p0.x, p0.y, 6)])
	var deck_y := FLOOR_HEIGHT + HALF_PIPE_RADIUS
	for xs in [[6.5, 7.5], [16.5, 17.5]]:
		_quads.append([Vector3(xs[0], deck_y, -6), Vector3(xs[1], deck_y, -6), Vector3(xs[1], deck_y, 6), Vector3(xs[0], deck_y, 6)])


func _add_climbing_block() -> void:
	_add_box(Vector3(-9, FLOOR_HEIGHT, -2), Vector3(-5, FLOOR_HEIGHT + 2.2, 2))


## A wedge rising along +Z: `length` long, `height` tall at its lip, `width` wide.
func _add_kicker(start: Vector3, length: float, height: float, width: float) -> void:
	var x0 := start.x - width * 0.5
	var x1 := start.x + width * 0.5
	var z0 := start.z
	var z1 := start.z + length
	var y0 := start.y
	var y1 := start.y + height
	# Curved face: a quarter-circle-ish ease so the lip is not a sharp edge.
	var segments := 10
	for i in segments:
		var t0 := float(i) / segments
		var t1 := float(i + 1) / segments
		var h0 := y0 + height * (t0 * t0)
		var h1 := y0 + height * (t1 * t1)
		var za := z0 + length * t0
		var zb := z0 + length * t1
		_quads.append([Vector3(x0, h0, za), Vector3(x1, h0, za), Vector3(x1, h1, zb), Vector3(x0, h1, zb)])
	_quads.append([Vector3(x1, y1, z1), Vector3(x0, y1, z1), Vector3(x0, y0, z1), Vector3(x1, y0, z1)])
	for side in [[x0, -1.0], [x1, 1.0]]:
		var x: float = side[0]
		for i in segments:
			var t0 := float(i) / segments
			var t1 := float(i + 1) / segments
			_quads.append([Vector3(x, y0, z0 + length * t0), Vector3(x, y0, z0 + length * t1),
				Vector3(x, y0 + height * t1 * t1, z0 + length * t1), Vector3(x, y0 + height * t0 * t0, z0 + length * t0)])


## Closed axis-aligned box from `low` to `high`.
func _add_box(low: Vector3, high: Vector3) -> void:
	var top := [Vector3(low.x, high.y, low.z), Vector3(high.x, high.y, low.z), Vector3(high.x, high.y, high.z), Vector3(low.x, high.y, high.z)]
	_quads.append(top)
	for i in 4:
		var a: Vector3 = top[i]
		var b: Vector3 = top[(i + 1) % 4]
		_quads.append([b, a, Vector3(a.x, low.y, a.z), Vector3(b.x, low.y, b.z)])


## Box rails with their spline on the top centre.
func _add_rails() -> void:
	var rails := [
		["low_flat_rail", Vector3(-7, FLOOR_HEIGHT + 0.45, 7), Vector3(-7, FLOOR_HEIGHT + 0.45, 15), 0.10, 0.10],
		["high_flat_rail", Vector3(4.5, FLOOR_HEIGHT + 0.70, 8), Vector3(4.5, FLOOR_HEIGHT + 0.70, 16), 0.10, 0.10],
		["halfpipe_left_coping", Vector3(7.5, FLOOR_HEIGHT + 2.5, -6), Vector3(7.5, FLOOR_HEIGHT + 2.5, 6), 0.08, 0.08],
		["halfpipe_right_coping", Vector3(16.5, FLOOR_HEIGHT + 2.5, -6), Vector3(16.5, FLOOR_HEIGHT + 2.5, 6), 0.08, 0.08],
		["platform_back_edge", Vector3(-3, HEIGHT, -4), Vector3(3, HEIGHT, -4), 0.0, 0.0],
		["platform_right_edge", Vector3(3, HEIGHT, -4), Vector3(3, HEIGHT, 4), 0.0, 0.0],
		["platform_left_edge", Vector3(-3, HEIGHT, 4), Vector3(-3, HEIGHT, -4), 0.0, 0.0],
	]
	for i in rails.size():
		var r: Array = rails[i]
		var rail := GrindRail.new()
		rail.name = r[0]
		rail.start = r[1]
		rail.end = r[2]
		rail.width = r[3]
		rail.thickness = r[4]
		add_child(rail)
		if r[3] == 0.0:
			continue
		_quads.clear()
		var start: Vector3 = r[1]
		var end: Vector3 = r[2]
		var half: float = r[3] * 0.5
		_add_box(Vector3(start.x - half, start.y - r[4], start.z), Vector3(start.x + half, start.y, end.z))
		if i <= 1:
			for z in [start.z + 0.6, end.z - 0.6]:
				_add_box(Vector3(start.x - 0.04, FLOOR_HEIGHT, z - 0.04), Vector3(start.x + 0.04, start.y - r[4], z + 0.04))
		_emit(r[0] + "_mesh", Color(0.75, 0.42, 0.18) if i <= 1 else Color(0.82, 0.82, 0.85))


## Turns the pending quads into one static body with a matching mesh.
func _emit(node_name: String, color: Color) -> void:
	var faces := PackedVector3Array()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for quad in _quads:
		for tri in [[0, 2, 1], [0, 3, 2]]:
			var a: Vector3 = quad[tri[0]]
			var b: Vector3 = quad[tri[1]]
			var c: Vector3 = quad[tri[2]]
			var n := (b - a).cross(c - a)
			if n.length_squared() < 1e-12:
				continue
			n = n.normalized()
			# Godot treats clockwise triangles as front faces.
			for v in [a, c, b]:
				st.set_normal(n)
				st.set_uv(Vector2(v.x + v.y, v.z + v.y) * 0.5)
				st.add_vertex(v)
				faces.append(v)
	var mesh := st.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.85
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.uv1_triplanar = false
	var instance := MeshInstance3D.new()
	instance.name = node_name
	instance.mesh = mesh
	instance.material_override = material
	add_child(instance)
	var body := StaticBody3D.new()
	body.name = node_name + "_body"
	var shape := ConcavePolygonShape3D.new()
	shape.backface_collision = true
	shape.set_faces(faces)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)
	_quads.clear()
