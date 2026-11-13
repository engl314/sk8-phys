extends OllieTest

func _ride(pumping: bool) -> Array[float]:
	var park := TestPark.new()
	tree.root.add_child(park)
	var skater := SkaterController.new()
	tree.root.add_child(skater)
	skater.respawn(Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(12.0, TestPark.FLOOR_HEIGHT, 0.0)))
	skater.board.set_velocity(Vector3(4.5, 0.0, 0.0))
	# W from the first wall on, so the start on the flat bottom isn't a push.
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.hold(VirtualPad.Action.PUSH, pumping and tick > 30)
	var peaks: Array[float] = []
	var best := -99.0
	var last_side := 0
	for i in 900:
		await tree.physics_frame
		var deck := skater.board.deck()
		var side := 1 if deck.position.x > 12.0 else -1
		var height := deck.position.y - TestPark.FLOOR_HEIGHT
		if side != last_side and last_side != 0:
			peaks.append(best)
			best = -99.0
		last_side = side
		best = maxf(best, height)
	if pumping:
		check(skater.rider.push_count == 0, "W pumped instead of pushing (%d pushes)" % skater.rider.push_count)
	skater.queue_free()
	park.queue_free()
	return peaks


func test_pumping_beats_coasting() -> void:
	var coast := await _ride(false)
	var pump := await _ride(true)
	print("    wall peaks coasting %s" % [coast.map(func(h: float) -> String: return "%.2f" % h)])
	print("    wall peaks pumping  %s" % [pump.map(func(h: float) -> String: return "%.2f" % h)])
	check(coast.size() >= 3 and pump.size() >= 3, "several passes (%d / %d)" % [coast.size(), pump.size()])
	if coast.size() >= 3 and pump.size() >= 3:
		check(pump[2] > coast[2] + 0.05, "pumping holds more height by the third wall (%.2f vs %.2f)" % [pump[2], coast[2]])
