class_name VirtualPad
extends Node

enum Action { PUSH, BRAKE, POP, KICKFLIP, HEELFLIP, SHUVIT, FS_SHUVIT, BOARD, NOLLIE, RESPAWN }

const KEYS := {
	Action.PUSH: KEY_W,
	Action.BRAKE: KEY_S,
	Action.POP: KEY_SPACE,
	Action.KICKFLIP: KEY_Q,
	Action.HEELFLIP: KEY_E,
	Action.SHUVIT: KEY_Z,
	Action.FS_SHUVIT: KEY_X,
	Action.BOARD: KEY_C,
	Action.NOLLIE: KEY_SHIFT,
	Action.RESPAWN: KEY_R,
}
## Gamepad buttons. Push and brake are the right and left triggers.
const BUTTONS := {
	Action.POP: JOY_BUTTON_A,
	Action.KICKFLIP: JOY_BUTTON_X,
	Action.HEELFLIP: JOY_BUTTON_B,
	Action.SHUVIT: JOY_BUTTON_LEFT_SHOULDER,
	Action.FS_SHUVIT: JOY_BUTTON_RIGHT_SHOULDER,
	Action.BOARD: JOY_BUTTON_Y,
	Action.NOLLIE: JOY_BUTTON_LEFT_STICK,
	Action.RESPAWN: JOY_BUTTON_BACK,
}

## Camera turn per mouse pixel (radians).
@export var mouse_sensitivity := 0.0032
## Camera turn rate at full right-stick deflection (radians per second).
@export var stick_look_speed := 3.2
## A/D ramp (units per second), so carving is analog.
@export var key_ramp_rate := 6.0
@export var key_release_rate := 9.0
@export var gamepad_deadzone := 0.12

## Steering -1 (A, left) .. +1 (D, right).
var steer := 0.0
## Camera input this tick in radians: x turns right, y tips the view down.
var look := Vector2.ZERO
## While a menu is open the mouse is left free for it.
var ui_open := false

var _down: Array[bool] = []
var _was_down: Array[bool] = []
var _pressed: Array[bool] = []
var _released: Array[bool] = []
var _held: Array[float] = []
## Presses seen as events since the last sample, so a tap shorter than a tick still counts.
var _latched: Array[bool] = []
var _mouse_accumulated := Vector2.ZERO


func _init() -> void:
	for _a in Action.size():
		_down.append(false)
		_was_down.append(false)
		_pressed.append(false)
		_released.append(false)
		_held.append(0.0)
		_latched.append(false)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		_mouse_accumulated += (event as InputEventMouseMotion).relative
	elif event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED and not ui_open:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		var key := (event as InputEventKey).physical_keycode
		if key == KEY_ESCAPE:
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		for action in KEYS:
			if KEYS[action] == key:
				_latched[action] = true


## Read the devices. Call once at the start of each physics tick.
func sample(delta: float) -> void:
	var pads := Input.get_connected_joypads()
	for action in Action.size():
		var down := _latched[action] or (KEYS.has(action) and Input.is_physical_key_pressed(KEYS[action]))
		for device in pads:
			if BUTTONS.has(action) and Input.is_joy_button_pressed(device, BUTTONS[action]):
				down = true
			elif action == Action.PUSH and Input.get_joy_axis(device, JOY_AXIS_TRIGGER_RIGHT) > 0.5:
				down = true
			elif action == Action.BRAKE and Input.get_joy_axis(device, JOY_AXIS_TRIGGER_LEFT) > 0.5:
				down = true
		_down[action] = down
		_latched[action] = false
	_sample_steer(delta, pads)
	look = _mouse_accumulated * mouse_sensitivity
	_mouse_accumulated = Vector2.ZERO
	for device in pads:
		var stick := Vector2(Input.get_joy_axis(device, JOY_AXIS_RIGHT_X), Input.get_joy_axis(device, JOY_AXIS_RIGHT_Y))
		if stick.length() > gamepad_deadzone:
			look += stick * stick_look_speed * delta


## Force an action down (or up) for this tick. Between `sample()` and `commit()`.
func hold(action: Action, is_down := true) -> void:
	_down[action] = is_down


## Turn this tick's states into presses, releases and hold times.
func commit(delta: float) -> void:
	for action in Action.size():
		_pressed[action] = _down[action] and not _was_down[action]
		_released[action] = _was_down[action] and not _down[action]
		if _down[action]:
			_held[action] = 0.0 if _pressed[action] else _held[action] + delta
		_was_down[action] = _down[action]


func down(action: Action) -> bool:
	return _down[action]


## Went down this tick.
func pressed(action: Action) -> bool:
	return _pressed[action]


## Came up this tick.
func released(action: Action) -> bool:
	return _released[action]


## Seconds the current press has lasted (or the last one lasted, once released).
func held_time(action: Action) -> float:
	return _held[action]


func any_down() -> bool:
	return _down.has(true)


func _sample_steer(delta: float, pads: Array[int]) -> void:
	var target := 0.0
	if Input.is_physical_key_pressed(KEY_A):
		target -= 1.0
	if Input.is_physical_key_pressed(KEY_D):
		target += 1.0
	var rising := absf(target) > absf(steer) and signf(target) == signf(steer) or steer == 0.0
	steer = move_toward(steer, target, (key_ramp_rate if rising else key_release_rate) * delta)
	for device in pads:
		var x := Input.get_joy_axis(device, JOY_AXIS_LEFT_X)
		if absf(x) > gamepad_deadzone:
			steer = clampf(x, -1.0, 1.0)
