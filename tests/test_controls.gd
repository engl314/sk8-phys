extends OllieTest

const Action := VirtualPad.Action

var park: TestPark
var skater: SkaterController
var landed: Array[String] = []


func _setup(speed: float) -> void:
	park = TestPark.new()
	tree.root.add_child(park)
	skater = SkaterController.new()
	tree.root.add_child(skater)
	skater.respawn(Transform3D(Basis.IDENTITY, Vector3(25.0, TestPark.FLOOR_HEIGHT, -40.0)))
	skater.board.set_velocity(Vector3(0.0, 0.0, speed))
	landed.clear()
	skater.director.trick_landed.connect(func(n: String) -> void: landed.append(n))


func _teardown() -> void:
	skater.queue_free()
	park.queue_free()


func _run(ticks: int, each := Callable()) -> void:
	for i in ticks:
		await tree.physics_frame
		if each.is_valid():
			each.call(i)


## Speed after `ticks` with `action` held throughout (or nothing held).
func _speed_after(action: int, ticks: int, speed: float) -> float:
	await _setup(speed)
	skater.scripted_input = func(_tick: int) -> void:
		if action >= 0:
			skater.pad.hold(action)
	await _run(ticks)
	var result := skater.board.speed()
	_teardown()
	return result


func test_w_pushes_and_s_brakes() -> void:
	var coast := await _speed_after(-1, 120, 3.0)
	var push := await _speed_after(Action.PUSH, 120, 3.0)
	var brake := await _speed_after(Action.BRAKE, 120, 3.0)
	print("    after 2 s from 3 m/s: coasting %.2f, W %.2f, S %.2f m/s" % [coast, push, brake])
	check(push > coast + 0.5, "W speeds up (%.2f vs %.2f)" % [push, coast])
	check(brake < coast - 0.5, "S slows down (%.2f vs %.2f)" % [brake, coast])


func test_s_with_a_turn_powerslides() -> void:
	await _setup(5.0)
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.hold(Action.BRAKE, tick > 10 and tick < 50)
		skater.pad.steer = 1.0 if tick > 10 and tick < 50 else 0.0
	var slid := 0
	for i in 90:
		await tree.physics_frame
		if skater.rider.state == RidingModel.State.SLIDE:
			slid += 1
	print("    powerslide: %d ticks sliding, speed %.2f, state %s" % [slid, skater.board.speed(), skater.rider.state_name()])
	check(slid > 15, "slid (%d ticks)" % slid)
	check(skater.rider.state == RidingModel.State.GROUND and skater.board.deck().basis.y.y > 0.95, "rolling upright again")
	_teardown()


func test_powerslide_right_after_landing_reverts() -> void:
	await _setup(4.5)
	var landing := {"tick": -1}
	skater.director.trick_landed.connect(func(n: String) -> void:
		if n == "Ollie":
			landing.tick = skater.tick)
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.hold(Action.POP, tick >= 30 and tick < 60)
		var since: int = tick - landing.tick
		var sliding: bool = landing.tick > 0 and since >= 2 and since < 40
		skater.pad.hold(Action.BRAKE, sliding)
		skater.pad.steer = 1.0 if sliding else 0.0
	await _run(200)
	print("    revert: landed %s, state %s, upright %.2f" % [landed, skater.rider.state_name(), skater.board.deck().basis.y.y])
	check(landed == ["Ollie", "Revert"], "an ollie, then a revert (%s)" % [landed])
	_teardown()


func test_holding_c_manuals_and_shift_c_nose_manuals() -> void:
	for nose in [false, true]:
		await _setup(4.0)
		skater.scripted_input = func(tick: int) -> void:
			skater.pad.hold(Action.BOARD, tick > 10 and tick < 100)
			skater.pad.hold(Action.NOLLIE, nose and tick > 10 and tick < 14)
		var lifted := 0
		for i in 130:
			await tree.physics_frame
			var f := skater.rider.frame
			if i > 30 and i < 100 and (not f.front_wheels_down if not nose else not f.back_wheels_down):
				lifted += 1
		var label := "Nose Manual" if nose else "Manual"
		print("    %s: wheels up %d of 69 ticks, landed %s" % [label, lifted, landed])
		check(lifted > 50, "%s lifted the other wheels (%d ticks)" % [label, lifted])
		check(landed.has(label), "scored a %s (%s)" % [label, landed])
		_teardown()


func test_mouse_orbits_the_camera_and_it_swings_back() -> void:
	await _setup(3.0)
	var camera := SkateCamera.new()
	camera.target = skater
	tree.root.add_child(camera)
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.hold(Action.PUSH, tick < 60)
		if tick == 20:
			skater.pad.look = Vector2(1.2, 0.3)
	await _run(25)
	var turned := camera.orbit_yaw
	var raised := camera.orbit_pitch
	await _run(240)
	print("    camera: orbit %.2f rad / pitch %.2f after the look, %.2f / %.2f later" % [turned, raised, camera.orbit_yaw, camera.orbit_pitch])
	check(absf(turned + 1.2) < 0.01 and absf(raised - 0.3) < 0.01, "the look turned the orbit")
	check(absf(camera.orbit_yaw) < 0.2 and absf(camera.orbit_pitch) < 0.1, "swung back behind the rider")
	camera.queue_free()
	_teardown()
