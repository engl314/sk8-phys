extends OllieTest

var park: TestPark
var board: BoardPhysics
var rider: RidingModel
var collider: BoardCollider
var input: RidingInput
var space: PhysicsDirectSpaceState3D


func _setup(speed: float) -> void:
	park = TestPark.new()
	tree.root.add_child(park)
	await tree.physics_frame
	space = park.get_world_3d().direct_space_state
	board = BoardPhysics.new()
	rider = RidingModel.new(SkateTuning.new())
	collider = BoardCollider.new()
	input = RidingInput.new()
	board.spawn(Transform3D(Basis.IDENTITY, Vector3(25.0, TestPark.FLOOR_HEIGHT + BoardSpec.LEVEL_GROUND_DECK_HEIGHT, -40.0)), true)
	board.set_velocity(Vector3(0.0, 0.0, speed))
	await _run(20)


func _run(ticks: int, each := Callable()) -> void:
	for i in ticks:
		await tree.physics_frame
		if each.is_valid():
			each.call(i)
		var targets := rider.update(board, input)
		collider.wheel_material = rider.wheel_material()
		board.step(collider.gather(board, space), targets)
		board.clear_forces()


func _manual(balance: float, label: String) -> void:
	await _setup(4.0)
	input.balance = balance
	var stats := {"pitch": [], "off": 0, "ticks": 0}
	await _run(180, func(i: int) -> void:
		if i < 30:
			return
		var deck := board.deck()
		stats.pitch.append(rad_to_deg(asin(clampf(deck.basis.z.y, -1.0, 1.0))))
		stats.ticks += 1
		var lifted := not (rider.frame.front_wheels_down if balance > 0.0 else rider.frame.back_wheels_down)
		if lifted:
			stats.off += 1)
	var pitches: Array = stats.pitch
	var mean := 0.0
	for p in pitches:
		mean += p
	mean /= pitches.size()
	var lifted_fraction: float = float(stats.off) / stats.ticks
	print("    %s: mean pitch %.1f deg (min %.1f, max %.1f), lifted wheels %.0f%% of the time, speed %.2f" % [label, mean, pitches.min(), pitches.max(), lifted_fraction * 100.0, board.speed()])
	var sign := signf(balance)
	check(mean * sign > 3.0 and mean * sign < 16.0, "deck pitched into the manual (%.1f deg)" % mean)
	check(lifted_fraction > 0.75, "the other wheels stay up (%.0f%%)" % (lifted_fraction * 100.0))
	check(board.deck().basis.y.y > 0.9, "upright")
	check(board.speed() > 2.0, "still rolling (%.2f)" % board.speed())
	park.queue_free()


func test_manual_balances_on_the_back_wheels() -> void:
	await _manual(0.5, "manual")


func test_nose_manual_balances_on_the_front_wheels() -> void:
	await _manual(-0.5, "nose manual")


func test_letting_go_drops_the_wheels() -> void:
	await _setup(4.0)
	input.balance = 0.5
	await _run(90)
	input.balance = 0.0
	await _run(40)
	check(rider.frame.wheel_contacts == 4, "all four wheels back down (%d)" % rider.frame.wheel_contacts)
	park.queue_free()


func test_revert_swings_the_board_half_a_turn() -> void:
	await _setup(4.0)
	var start := board.deck().basis.z
	rider.start_revert(1.0)
	await _run(60)
	var turned := rad_to_deg(Vector3(start.x, 0, start.z).angle_to(Vector3(board.deck().basis.z.x, 0, board.deck().basis.z.z)))
	print("    revert: turned %.0f deg, state %s, speed %.2f" % [turned, rider.state_name(), board.speed()])
	check(turned > 150.0, "board turned around (%.0f deg)" % turned)
	check(rider.state == RidingModel.State.GROUND, "back to riding (%s)" % rider.state_name())
	check(board.speed() > 1.0, "kept rolling (%.2f)" % board.speed())
	park.queue_free()
