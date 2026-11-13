extends Node3D

var park: TestPark
var skater: SkaterController
var camera: SkateCamera
var overlay: DebugOverlay

var _screenshot_path := ""
var _screenshot_frames: Array[int] = [180]
var _side_view := false
var _front_view := false
var _back_view := false
var _demo := ""
var _frame := 0
var _captured := {}


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--screenshot="):
			_screenshot_path = arg.get_slice("=", 1)
		elif arg.begins_with("--frames="):
			_screenshot_frames.clear()
			for value in arg.get_slice("=", 1).split(","):
				_screenshot_frames.append(int(value))
		elif arg == "--side-view":
			_side_view = true
		elif arg == "--front-view":
			_front_view = true
		elif arg == "--back-view":
			_back_view = true
		elif arg.begins_with("--demo="):
			_demo = arg.get_slice("=", 1)
		elif arg.begins_with("--slowmo="):
			Engine.time_scale = clampf(float(arg.get_slice("=", 1)), 0.05, 1.0)
	_build_environment()
	park = TestPark.new()
	park.name = "TestPark"
	add_child(park)
	skater = SkaterController.new()
	skater.name = "Skater"
	skater.autopilot = "--autopilot" in OS.get_cmdline_user_args()
	add_child(skater)
	if _demo == "bail":
		skater.respawn(Transform3D(Basis.IDENTITY, Vector3(25.0, TestPark.FLOOR_HEIGHT, -40.0)))
		skater.board.set_velocity(Vector3(0.0, 0.0, 6.0))
		skater.scripted_input = _bail_demo_input
	elif _demo == "grind":
		skater.respawn(Transform3D(Basis.IDENTITY, Vector3(-7.0, TestPark.FLOOR_HEIGHT, 3.0)))
		skater.board.set_velocity(Vector3(0.0, 0.0, 4.8))
		skater.scripted_input = _grind_demo_input
	elif _demo != "":
		skater.respawn(Transform3D(Basis.IDENTITY, Vector3(25.0, TestPark.FLOOR_HEIGHT, -40.0)))
		skater.scripted_input = _demo_input
	else:
		skater.respawn(TestPark.SPAWN)
	camera = SkateCamera.new()
	camera.name = "Camera"
	camera.target = skater
	add_child(camera)
	camera.make_current()
	# The side view places the camera itself each frame.
	camera.set_physics_process(not _side_view and not _front_view and not _back_view)
	overlay = DebugOverlay.new()
	overlay.skater = skater
	add_child(overlay)
	var hud := TrickHud.new()
	hud.skater = skater
	hud.score = skater.score
	add_child(hud)
	var panel := TuningPanel.new()
	panel.skater = skater
	add_child(panel)
	if "--panel" in OS.get_cmdline_user_args():
		panel.call_deferred("_toggle")


func _build_environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.36, 0.55, 0.82)
	sky_material.sky_horizon_color = Color(0.72, 0.8, 0.9)
	sky_material.ground_horizon_color = Color(0.6, 0.62, 0.64)
	sky.sky_material = sky_material
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.ssao_enabled = true
	var world_environment := WorldEnvironment.new()
	world_environment.environment = environment
	add_child(world_environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-52.0, -35.0, 0.0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	sun.directional_shadow_max_distance = 60.0
	add_child(sun)


func _process(_delta: float) -> void:
	if _side_view or _front_view or _back_view:
		# Fixed camera on the rider, following the drawn (interpolated) frame so it
		# stays smooth in slow motion: beside them to check posture, or ahead of
		# them looking back down the board to check lean.
		var frame := skater.animator.get_global_transform_interpolated()
		var offset := frame.basis.x * -2.4 if _side_view else frame.basis.z * (-2.6 if _back_view else 2.6)
		offset.y = 0.0
		camera.global_position = frame.origin + offset.normalized() * offset.length() + Vector3.UP * 0.9
		camera.look_at(frame.origin + Vector3.UP * 0.7, Vector3.UP)
	if _screenshot_path == "":
		return
	_frame += 1
	# Screenshot targets count physics ticks, so captures line up with the simulation.
	var due := -1
	for target in _screenshot_frames:
		if skater.tick >= target and not _captured.has(target):
			due = target
			break
	if due >= 0:
		_captured[due] = true
		var image := get_viewport().get_texture().get_image()
		var path := _screenshot_path.get_basename() + "_%d.png" % due if _screenshot_frames.size() > 1 else _screenshot_path
		image.save_png(path)
		print("saved screenshot %s at tick %d" % [path, skater.tick])
		if due == _screenshot_frames.max():
			get_tree().quit()


## Unattended demo for screenshots: push up to speed, then crouch and pop.
## --demo=ollie | kickflip | heelflip | shuvit | treflip | spin | push (keep pushing in a straight line)
##   | carve (S-turns) | brake (coast, then stop) | manual (hold a manual)
##   | stand (stand still, push off, stop, ollie on the spot)
func _demo_input(tick: int) -> void:
	var pad := skater.pad
	pad.steer = 0.0
	if _demo == "stand":
		# Stand a moment, push off, brake to a stop, stand again, then ollie on the spot.
		pad.hold(VirtualPad.Action.PUSH, tick >= 90 and tick < 200)
		pad.hold(VirtualPad.Action.BRAKE, tick >= 260 and tick < 420)
		pad.hold(VirtualPad.Action.POP, tick >= 480 and tick < 510)
		return
	pad.hold(VirtualPad.Action.PUSH, tick < 150 or _demo == "push")
	if tick < 150 or _demo == "push":
		return
	if _demo == "carve":
		# A second each way, hard over.
		pad.steer = 1.0 if (tick - 150) / 60 % 2 == 0 else -1.0
		return
	if _demo == "brake":
		pad.hold(VirtualPad.Action.BRAKE, tick >= 200)
		return
	if _demo == "manual":
		pad.hold(VirtualPad.Action.BOARD, tick >= 180 and tick < 330)
		return
	var cycle := (tick - 150) % 150
	var buttons := {"kickflip": [VirtualPad.Action.KICKFLIP], "heelflip": [VirtualPad.Action.HEELFLIP],
		"shuvit": [VirtualPad.Action.SHUVIT], "treflip": [VirtualPad.Action.KICKFLIP, VirtualPad.Action.SHUVIT]}
	if buttons.has(_demo):
		pad.hold(VirtualPad.Action.POP, cycle >= 20 and cycle < 56)
		for button: VirtualPad.Action in buttons[_demo]:
			# Holding a shove-it button makes it a 360 (with a kickflip: a 360 flip).
			pad.hold(button, cycle >= 50 and cycle < (80 if _demo == "treflip" else 54))
	else:
		pad.hold(VirtualPad.Action.POP, cycle >= 20 and cycle < 50)
	if _demo == "spin" and cycle >= 52 and cycle < 72:
		pad.steer = -1.0


func _grind_demo_input(tick: int) -> void:
	skater.pad.hold(VirtualPad.Action.POP, tick >= 6 and tick < 36)


## --demo=bail: ollie and land sideways.
func _bail_demo_input(tick: int) -> void:
	var pad := skater.pad
	pad.hold(VirtualPad.Action.POP, tick >= 10 and tick < 40)
	pad.steer = 0.3 if tick >= 42 and tick < 120 else 0.0
