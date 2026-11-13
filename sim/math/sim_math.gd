class_name SimMath

const DT := 1.0 / 60.0
const FREQUENCY := 60.0
## A finite stand-in for an unbounded limit (the largest 32-bit float).
const FLOAT_MAX := 3.4028234663852886e38
const ZERO_BASIS := Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO)
const SQRT_2 := sqrt(2.0)


## Rotation matrix of q. Valid for non-unit q.
static func basis_from_quaternion(q: Quaternion) -> Basis:
	var x := q.x * SQRT_2
	var y := q.y * SQRT_2
	var z := q.z * SQRT_2
	var w := q.w * SQRT_2
	var dx := 0.5 - x * x
	var dy := 0.5 - y * y
	var dz := 0.5 - z * z
	return Basis(
		Vector3(dy + dz, x * y + w * z, z * x - w * y),
		Vector3(x * y - w * z, dz + dx, y * z + w * x),
		Vector3(z * x + w * y, y * z - w * x, dx + dy))


## Hamilton product a * b.
static func quaternion_product(a: Quaternion, b: Quaternion) -> Quaternion:
	return Quaternion(
		a.x * b.w + b.x * a.w + (a.y * b.z - a.z * b.y),
		a.y * b.w + b.y * a.w + (a.z * b.x - a.x * b.z),
		a.z * b.w + b.z * a.w + (a.x * b.y - a.y * b.x),
		a.w * b.w - (a.x * b.x + a.y * b.y + a.z * b.z))


## q += 0.5 * (rotation, 0) * q, then normalize.
static func integrate_orientation(q: Quaternion, r: Vector3) -> Quaternion:
	var c := Quaternion(
		q.x + 0.5 * (r.x * q.w + (r.y * q.z - r.z * q.y)),
		q.y + 0.5 * (r.y * q.w + (r.z * q.x - r.x * q.z)),
		q.z + 0.5 * (r.z * q.w + (r.x * q.y - r.y * q.x)),
		q.w - 0.5 * (r.x * q.x + r.y * q.y + r.z * q.z))
	var length_squared := c.x * c.x + c.y * c.y + c.z * c.z + c.w * c.w
	return c * (1.0 / sqrt(length_squared))


static func normalize_q(q: Quaternion) -> Quaternion:
	var length_squared := q.x * q.x + q.y * q.y + q.z * q.z + q.w * q.w
	return q * (1.0 / sqrt(length_squared))


## Dominant-component matrix to quaternion.
static func quaternion_from_basis(b: Basis) -> Quaternion:
	var m00 := b.x.x
	var m01 := b.y.x
	var m02 := b.z.x
	var m10 := b.x.y
	var m11 := b.y.y
	var m12 := b.z.y
	var m20 := b.x.z
	var m21 := b.y.z
	var m22 := b.z.z
	var trace := m00 + m11 + m22
	var sum: float
	var parts: Array[float]
	var dominant: int
	if trace > 0.0:
		sum = (m00 + m11) + (m22 + 1.0)
		parts = [m21 - m12, m02 - m20, m10 - m01, 0.0]
		dominant = 3
	elif m00 > m11 and m00 > m22:
		sum = (m00 - m11) + (1.0 - m22)
		parts = [0.0, m01 + m10, m02 + m20, m21 - m12]
		dominant = 0
	elif m11 > m22:
		sum = (m11 - m00) + (1.0 - m22)
		parts = [m01 + m10, 0.0, m12 + m21, m02 - m20]
		dominant = 1
	else:
		sum = (-m00 - m11) + (m22 + 1.0)
		parts = [m02 + m20, m12 + m21, 0.0, m10 - m01]
		dominant = 2
	var inverse_root := 1.0 / sqrt(sum)
	for i in 4:
		parts[i] *= inverse_root * 0.5
	parts[dominant] = sum * inverse_root * 0.5
	return Quaternion(parts[0], parts[1], parts[2], parts[3])


## R * diag(local_inverse_inertia) * R^T.
static func world_inverse_inertia(b: Basis, local_inverse_inertia: Vector3) -> Basis:
	return b * Basis.from_scale(local_inverse_inertia) * b.transposed()


## The six rows of the relative quaternion conj(a) * b and its angular Jacobian.
## Returns [axis0, axis1, axis2, relative].
static func relative_rotation_jacobian(a: Quaternion, b: Quaternion) -> Array:
	var xx := a.x * b.x
	var xy := a.x * b.y
	var xz := a.x * b.z
	var xw := a.x * b.w
	var yx := a.y * b.x
	var yy := a.y * b.y
	var yz := a.y * b.z
	var yw := a.y * b.w
	var zx := a.z * b.x
	var zy := a.z * b.y
	var zz := a.z * b.z
	var zw := a.z * b.w
	var wx := a.w * b.x
	var wy := a.w * b.y
	var wz := a.w * b.z
	var ww := a.w * b.w
	return [
		Vector3(((ww + xx) - yy) - zz, ((yx + xy) + wz) + zw, ((xz + zx) - wy) - yw),
		Vector3(((yx + xy) - wz) - zw, ((ww + yy) - zz) - xx, ((yz + zy) + wx) + xw),
		Vector3(((xz + zx) + yw) + wy, ((zy + yz) - wx) - xw, ((ww + zz) - xx) - yy),
		Quaternion(((wx - xw) + zy) - yz, ((wy - yw) + xz) - zx, ((wz - zw) + yx) - xy, ((ww + zz) + yy) + xx),
	]


## Three column vectors -> Godot Basis.
static func basis_from_columns(columns: Array) -> Basis:
	return Basis(
		Vector3(columns[0][0], columns[0][1], columns[0][2]),
		Vector3(columns[1][0], columns[1][1], columns[1][2]),
		Vector3(columns[2][0], columns[2][1], columns[2][2]))


static func rotation_x(angle: float) -> Basis:
	var s := sin(angle)
	var c := cos(angle)
	return Basis(Vector3(1.0, 0.0, 0.0), Vector3(0.0, c, s), Vector3(0.0, -s, c))


static func rotation_y(angle: float) -> Basis:
	var s := sin(angle)
	var c := cos(angle)
	return Basis(Vector3(c, 0.0, -s), Vector3(0.0, 1.0, 0.0), Vector3(s, 0.0, c))


## Velocity cap that publishes the squared cap.
static func clamp_length(value: Vector3, maximum: float) -> Vector3:
	var squared := value.length_squared()
	var maximum_squared := maximum * maximum
	if squared > maximum_squared:
		return value * sqrt(maximum_squared / squared)
	return value
