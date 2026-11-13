extends OllieTest

var park: TestPark
var board: BoardPhysics
var rider: RidingModel
var collider: BoardCollider
var input: RidingInput
var space: PhysicsDirectSpaceState3D


func _setup(heading_z := 1.0, speed := 0.0) -> void:
	park = TestPark.new()
	tree.root.add_child(park)
	await tree.physics_frame
	space = park.get_world_3d().direct_space_state
	board = BoardPhysics.new()
	var tuning := SkateTuning.new()
	rider = RidingModel.new(tuning)
	collider = BoardCollider.new()
	input = RidingInput.new()
	var basis := Basis.IDENTITY if heading_z > 0.0 else Basis(Vector3.UP, PI)
	board.spawn(Transform3D(basis, Vector3(25.0, TestPark.FLOOR_HEIGHT + BoardSpec.LEVEL_GROUND_DECK_HEIGHT, -40.0)), true)
	if speed != 0.0:
		board.set_velocity(basis.z * speed)
	await _run(20)


func _teardown() -> void:
	park.queue_free()


func _run(ticks: int, each := Callable()) -> void:
	for i in ticks:
		await tree.physics_frame
		if each.is_valid():
			each.call(i)
		var targets := rider.update(board, input)
		collider.wheel_material = rider.wheel_material()
		board.step(collider.gather(board, space), targets)
		board.clear_forces()
		input.push_pressed = false


func _upright() -> bool:
	return board.deck().basis.y.y > 0.97


func test_pushing_builds_speed_then_coasts() -> void:
	await _setup()
	var speeds: Array[float] = []
	await _run(360, func(i: int) -> void:
		input.push_held = true
		if i % 60 == 0:
			speeds.append(board.speed()))
	input.push_held = false
	var pushed_speed := board.speed()
	print("    speeds while pushing: %s -> %.2f m/s (%d pushes)" % [speeds.map(func(s: float) -> String: return "%.2f" % s), pushed_speed, rider.push_count])
	check(pushed_speed > 4.0 and pushed_speed <= rider.tuning.push_top_speed + 0.3, "push speed %.2f in range" % pushed_speed)
	check(_upright(), "upright while pushing")
	check(rider.state == RidingModel.State.GROUND, "still grounded")
	await _run(180)
	var coasted := board.speed()
	print("    after 3 s coasting: %.2f m/s" % coasted)
	check(coasted < pushed_speed and coasted > pushed_speed - 1.5, "coasting loses a little speed (%.2f -> %.2f)" % [pushed_speed, coasted])
	# The board drifts ~0.0015 rad/s per m/s: the
	# faster and further it goes, the further off the line.
	var travelled := board.deck().position.z + 40.0
	var drift := absf(board.deck().position.x - 25.0)
	print("    drifted %.2f m sideways over %.1f m" % [drift, travelled])
	check(drift < travelled * 0.09, "pushed nearly straight (%.2f m off the line in %.1f m)" % [drift, travelled])
	_teardown()


## Pushing gets the board moving quickly, and at speed the pushes come further
## apart: the rider glides between them rather than paddling.
func test_pushes_are_strong_and_come_slower_at_speed() -> void:
	await _setup()
	var plants: Array[int] = []
	var speeds: Array[float] = []
	var hangs: Array[int] = []
	# (A lambda keeps its own copy of a plain local, so the count lives in an array.)
	var seen: Array[int] = [0]
	await _run(480, func(i: int) -> void:
		input.push_held = true
		if rider.push_count != seen[0]:
			seen[0] = rider.push_count
			plants.append(i)
			speeds.append(board.speed())
			hangs.append(0)
		if rider.push_phase == RidingModel.PushPhase.HANG:
			hangs[hangs.size() - 1] += 1)
	var gaps: Array[int] = []
	for i in range(1, plants.size()):
		gaps.append(plants[i] - plants[i - 1])
	print("    speed at each plant: %s" % [speeds.map(func(s: float) -> String: return "%.1f" % s)])
	print("    ticks between plants: %s, gliding: %s" % [gaps, hangs])
	check(speeds.size() > 5 and speeds[4] > 5.0, "four pushes from a standstill reach 5 m/s (%.1f)" % speeds[4])
	check(speeds[1] > 1.5 and speeds[1] < 2.4, "the first push gives a good shove, not a launch (%.1f m/s)" % speeds[1])
	check(gaps[0] <= 41 and hangs[0] == 0, "slow pushes follow straight on from each other (%d ticks apart)" % gaps[0])
	var last := gaps.size() - 1
	check(speeds[last] > 6.5 and gaps[last] >= gaps[0] + 10, "fast ones come further apart (%d ticks at %.1f m/s)" % [gaps[last], speeds[last]])
	var slower := true
	for i in range(1, gaps.size()):
		slower = slower and gaps[i] >= gaps[i - 1] - 1
	check(slower, "the faster, the longer the glide between (%s)" % [gaps])
	check(board.speed() <= rider.tuning.push_top_speed + 0.3, "never past the top pushing speed (%.2f)" % board.speed())
	# Letting go of W in the glide ends it: no extra push.
	var count := rider.push_count
	while rider.push_phase != RidingModel.PushPhase.HANG:
		await _run(1, func(_i: int) -> void: input.push_held = true)
	await _run(2, func(_i: int) -> void: input.push_held = true)
	input.push_held = false
	count = rider.push_count
	await _run(90)
	check(rider.push_count == count and rider.push_phase == RidingModel.PushPhase.NONE, "letting go while gliding stops the pushing (%d more)" % (rider.push_count - count))
	# A tapped push still comes after the glide.
	input.push_pressed = true
	await _run(1)
	while rider.push_phase != RidingModel.PushPhase.DRIVE:
		await _run(1)
	await _run(4)
	input.push_pressed = true
	count = rider.push_count
	await _run(90)
	check(rider.push_count == count + 1, "a tap during a push queues one more through the glide (%d more)" % (rider.push_count - count))
	_teardown()


func test_carving_turns_left_and_right() -> void:
	await _setup(1.0, 4.0)
	var start_heading := _heading()
	input.turn = 1.0
	await _run(90)
	var left_turn := wrapf(_heading() - start_heading, -PI, PI)
	print("    full left for 1.5 s at %.1f m/s: %.0f degrees" % [board.speed(), rad_to_deg(left_turn)])
	check(left_turn > deg_to_rad(40.0), "turned left (%.0f deg)" % rad_to_deg(left_turn))
	check(_upright(), "upright after left carve")
	check(rider.frame.wheel_contacts == 4, "all wheels down in the carve (%d)" % rider.frame.wheel_contacts)
	var mid := _heading()
	input.turn = -1.0
	await _run(90)
	var right_turn := wrapf(_heading() - mid, -PI, PI)
	print("    full right for 1.5 s: %.0f degrees" % rad_to_deg(right_turn))
	check(right_turn < -deg_to_rad(40.0), "turned right (%.0f deg)" % rad_to_deg(right_turn))
	input.turn = 0.0
	_teardown()


func test_brake_stops_the_board() -> void:
	await _setup(1.0, 4.0)
	input.brake = 1.0
	var stopped := {"at": -1}
	await _run(300, func(i: int) -> void:
		if stopped.at < 0 and board.speed() < 0.05:
			stopped.at = i)
	input.brake = 0.0
	print("    braking from 4 m/s stopped after %.2f s" % (stopped.at / 60.0))
	check(stopped.at > 0 and stopped.at < 240, "stopped within 4 s")
	check(_upright(), "upright after braking")
	_teardown()


func test_powerslide_turns_board_across_and_slows() -> void:
	await _setup(1.0, 5.5)
	input.slide = true
	input.slide_direction = 1.0
	var result := {"widest": 0.0}
	await _run(50, func(_i: int) -> void:
		var v := board.deck().linear_velocity
		v.y = 0.0
		var f := board.deck().basis.z
		f.y = 0.0
		if v.length() > 0.5:
			result.widest = maxf(result.widest, absf(v.signed_angle_to(f, Vector3.UP))))
	var widest: float = result.widest
	var slid_speed := board.speed()
	print("    powerslide: widest angle %.0f deg, speed 5.5 -> %.2f" % [rad_to_deg(widest), slid_speed])
	check(rider.state == RidingModel.State.SLIDE or rider.state == RidingModel.State.GROUND, "stayed on the ground (%s)" % rider.state_name())
	check(widest > deg_to_rad(55.0), "board swung across (%.0f deg)" % rad_to_deg(widest))
	check(slid_speed < 4.5, "slide scrubbed speed (%.2f)" % slid_speed)
	check(_upright(), "upright in the slide")
	input.slide = false
	await _run(90)
	check(_upright(), "upright after the slide")
	_teardown()


func _heading() -> float:
	var f := board.deck().basis.z
	return atan2(f.x, f.z)
