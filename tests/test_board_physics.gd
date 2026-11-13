extends OllieTest

const CONTACT_PADDING := 0.05


func test_board_settles_at_ride_height() -> void:
	var board := BoardPhysics.new()
	board.spawn(Transform3D(Basis.IDENTITY, Vector3(0.0, BoardSpec.LEVEL_GROUND_DECK_HEIGHT + 0.01, 0.0)))
	var material := ContactMaterial.make(0.9, 0.7, 0.0)
	var worst_sink := 0.0
	for tick in 240:
		var contacts: Array[BoardContact] = []
		for wheel in BoardSpec.WHEELS:
			var center: Vector3 = board.bodies[wheel].position
			if center.y - BoardSpec.WHEEL_RADIUS < CONTACT_PADDING:
				contacts.append(BoardContact.make(wheel, center - Vector3(0.0, BoardSpec.WHEEL_RADIUS, 0.0),
					Vector3(center.x, 0.0, center.z), Vector3.UP, material))
		board.step(contacts, Vector2.ZERO)
		if tick > 120:
			worst_sink = minf(worst_sink, board.deck().linear_velocity.y)
	check_near(board.deck().position.y, BoardSpec.LEVEL_GROUND_DECK_HEIGHT, 1e-3, "deck ride height")
	check(worst_sink > -0.002, "deck sink rate at rest %.5f m/s" % worst_sink)
	print("    solver step %d usec" % board.last_step_usec)
