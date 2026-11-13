class_name SkateCamera
extends Camera3D

## distance (m), elevation (deg), framing pitch (deg), board offset (m above the deck).
const SHOTS := {
	"rolling_slow": [1.8, 7.0, -4.0, 0.9],
	"rolling_fast": [2.5, 5.0, -2.0, 0.9],
	"air": [2.8, 12.0, -2.0, 0.9],
}
## Speeds (m/s) between the slow and fast chase shots.
const SLOW_SPEED := 1.5
const FAST_SPEED := 6.5
## The collision sphere kept clear between the pivot and the camera.
const COLLISION_RADIUS := 0.13
## How far the mouse can tip the view: below and above the shot's elevation.
const ORBIT_PITCH_MIN := deg_to_rad(-12.0)
const ORBIT_PITCH_MAX := deg_to_rad(60.0)

## Seconds the mouse must rest before the camera swings back behind the rider.
@export var recenter_delay := 1.2
## Swing-back rate (1/s) and the speed (m/s) the rider must be moving for it.
@export var recenter_rate := 2.2
@export var recenter_speed := 1.0

var target: SkaterController
## Mouse orbit on top of the shot (radians).
var orbit_yaw := 0.0
var orbit_pitch := 0.0
var _look_rest := 99.0

var heading := CameraFollower.new()
var elevation := CameraFollower.new()
var distance := CameraFollower.new()
var pitch := CameraFollower.new()
var pivot_height := CameraFollower.new()
var _pivot := Vector3.ZERO
var _initialised := false
var _ray := PhysicsRayQueryParameters3D.new()
var _sphere := SphereShape3D.new()
var _cast := PhysicsShapeQueryParameters3D.new()


func _ready() -> void:
	fov = 74.0
	near = 0.04
	heading.angular = true
	heading.configure(deg_to_rad(4.0), deg_to_rad(45.0), deg_to_rad(320.0), deg_to_rad(240.0), deg_to_rad(1100.0), 0.0)
	elevation.configure(deg_to_rad(2.0), deg_to_rad(25.0), deg_to_rad(120.0), deg_to_rad(90.0), deg_to_rad(500.0), 0.0)
	distance.configure(0.1, 1.5, 6.0, 4.0, 20.0, 0.0)
	pitch.configure(deg_to_rad(1.0), deg_to_rad(10.0), deg_to_rad(90.0), deg_to_rad(60.0), deg_to_rad(400.0), 0.0)
	pivot_height.configure(0.02, 0.6, 6.0, 8.0, 60.0, 0.0)
	_sphere.radius = COLLISION_RADIUS
	_cast.shape = _sphere


func _physics_process(delta: float) -> void:
	if target == null:
		return
	_orbit(delta)
	var shot := _shot()
	var subject := target.camera_subject()
	var goal_heading := target.camera_heading()
	var goal_elevation := deg_to_rad(shot[1])
	if not _initialised:
		heading.reset(goal_heading)
		elevation.reset(goal_elevation)
		distance.reset(shot[0])
		pitch.reset(deg_to_rad(shot[2]))
		pivot_height.reset(subject.y + shot[3])
		_initialised = true
	var h := heading.update(delta, goal_heading)
	var e := elevation.update(delta, goal_elevation)
	var d := distance.update(delta, shot[0])
	var p := pitch.update(delta, deg_to_rad(shot[2]))
	var y := pivot_height.update(delta, subject.y + shot[3])
	_pivot = Vector3(subject.x, y, subject.z)
	h += orbit_yaw
	e = clampf(e + orbit_pitch, deg_to_rad(-8.0), deg_to_rad(75.0))

	# Behind the subject along the heading, raised by the elevation angle.
	var back := Vector3(-sin(h) * cos(e), sin(e), -cos(h) * cos(e))
	var wanted := _pivot + back * d
	var placed := _avoid(_pivot, wanted)
	global_position = placed
	var look := (_pivot - placed).normalized()
	if look.length_squared() < 0.5:
		look = -back
	var right := look.cross(Vector3.UP).normalized()
	look = look.rotated(right, p)
	look_at(placed + look, Vector3.UP)


## Mouse look: turn the orbit, then ease it back once the mouse rests.
func _orbit(delta: float) -> void:
	var look := target.pad.look
	if look.length_squared() > 0.0:
		_look_rest = 0.0
		# Mouse right turns the view right (heading decreases); mouse down raises the camera.
		orbit_yaw = wrapf(orbit_yaw - look.x, -PI, PI)
		orbit_pitch = clampf(orbit_pitch + look.y, ORBIT_PITCH_MIN, ORBIT_PITCH_MAX)
		return
	_look_rest += delta
	if _look_rest < recenter_delay or target.velocity().length() < recenter_speed:
		return
	var k := 1.0 - exp(-recenter_rate * delta)
	orbit_yaw = lerp_angle(orbit_yaw, 0.0, k)
	orbit_pitch = lerpf(orbit_pitch, 0.0, k)


func _shot() -> Array:
	var speed := target.velocity().length()
	if not target.is_grounded():
		return SHOTS.air
	var t := clampf((speed - SLOW_SPEED) / (FAST_SPEED - SLOW_SPEED), 0.0, 1.0)
	return _blend(SHOTS.rolling_slow, SHOTS.rolling_fast, t)


static func _blend(a: Array, b: Array, t: float) -> Array:
	var out := []
	for i in a.size():
		out.append(lerpf(a[i], b[i], t))
	return out


## Keep a 0.13 m sphere between the pivot and the camera clear of the level.
func _avoid(from: Vector3, to: Vector3) -> Vector3:
	var space := get_world_3d().direct_space_state
	_cast.transform = Transform3D(Basis.IDENTITY, from)
	_cast.motion = to - from
	var result := space.cast_motion(_cast)
	if result.is_empty():
		return to
	return from.lerp(to, maxf(result[0], 0.05))
