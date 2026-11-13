extends OllieTest

func _make_park() -> TestPark:
	var park := TestPark.new()
	tree.root.add_child(park)
	return park


func _step(board: BoardPhysics, collider: BoardCollider, space: PhysicsDirectSpaceState3D, ticks: int, steer := Vector2.ZERO, push := 0.0) -> void:
	for _i in ticks:
		await tree.physics_frame
		var contacts := collider.gather(board, space)
		if push != 0.0:
			board.queue_force(board.deck().basis.z * push, Vector3.ZERO)
		board.step(contacts, steer)
		board.clear_forces()


func test_board_settles_on_platform() -> void:
	var park := _make_park()
	await tree.physics_frame
	var board := BoardPhysics.new()
	var spawn := TestPark.SPAWN
	spawn.origin.y += BoardSpec.LEVEL_GROUND_DECK_HEIGHT + 0.01
	board.spawn(spawn, true)
	var collider := BoardCollider.new()
	var space := park.get_world_3d().direct_space_state
	await _step(board, collider, space, 120)
	check_near(board.deck().position.y, TestPark.HEIGHT + BoardSpec.LEVEL_GROUND_DECK_HEIGHT, 2e-3, "deck ride height on platform")
	check(board.wheel_contact_count() == 4, "four wheels in contact (got %d)" % board.wheel_contact_count())
	check(board.speed() < 0.02, "board at rest (speed %.4f)" % board.speed())
	park.queue_free()


func test_board_rolls_down_ramp_and_speeds_up() -> void:
	var park := _make_park()
	await tree.physics_frame
	var board := BoardPhysics.new()
	var spawn := TestPark.SPAWN
	spawn.origin.y += BoardSpec.LEVEL_GROUND_DECK_HEIGHT + 0.01
	spawn.origin.z = 3.0
	board.spawn(spawn, true)
	board.set_velocity(Vector3(0.0, 0.0, 1.5))
	var collider := BoardCollider.new()
	var space := park.get_world_3d().direct_space_state
	await _step(board, collider, space, 300)
	var deck := board.deck()
	print("    after ramp: pos %s speed %.2f up %s" % [deck.position, board.speed(), deck.basis.y])
	check(deck.position.y < TestPark.FLOOR_HEIGHT + 0.2, "reached the floor (y %.3f)" % deck.position.y)
	check(board.speed() > 3.0, "gained speed downhill (%.2f m/s)" % board.speed())
	check(deck.basis.y.y > 0.95, "still upright (up %s)" % deck.basis.y)
	check(absf(deck.position.x) < 0.5, "rolled straight (x %.3f)" % deck.position.x)
	park.queue_free()
