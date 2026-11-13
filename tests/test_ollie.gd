extends OllieTest

var park: TestPark
var skater: SkaterController
var landed: Array[String] = []
var bails: Array[String] = []


func _setup(speed: float) -> void:
	park = TestPark.new()
	tree.root.add_child(park)
	skater = SkaterController.new()
	tree.root.add_child(skater)
	skater.respawn(Transform3D(Basis.IDENTITY, Vector3(25.0, TestPark.FLOOR_HEIGHT, -40.0)))
	skater.board.set_velocity(Vector3(0.0, 0.0, speed))
	landed.clear()
	bails.clear()
	skater.director.trick_landed.connect(func(n: String) -> void: landed.append(n))
	skater.director.bailed.connect(func(r: String) -> void: bails.append(r))


func _teardown() -> void:
	skater.queue_free()
	park.queue_free()


## Script: hold Space from `crouch_at`, let go at `pop_at`; steer `spin` after the pop.
func _ollie(crouch_at: int, pop_at: int, spin := 0.0) -> Callable:
	return func(tick: int) -> void:
		var pad := skater.pad
		pad.hold(VirtualPad.Action.POP, tick >= crouch_at and tick < pop_at)
		pad.steer = spin if tick > pop_at else 0.0


func _run(ticks: int) -> Dictionary:
	var floor_y := TestPark.FLOOR_HEIGHT + BoardSpec.LEVEL_GROUND_DECK_HEIGHT
	var stats := {"max_height": 0.0, "air_ticks": 0, "max_pitch": 0.0}
	for _i in ticks:
		await tree.physics_frame
		var deck := skater.board.deck()
		stats.max_height = maxf(stats.max_height, deck.position.y - floor_y)
		if skater.director.airborne:
			stats.air_ticks += 1
			stats.max_pitch = maxf(stats.max_pitch, rad_to_deg(acos(clampf(deck.basis.z.y * 0.0 + Vector3(deck.basis.z.x, 0.0, deck.basis.z.z).length(), -1.0, 1.0))))
	return stats


func test_ollie_pops_and_lands_clean() -> void:
	await _setup(4.0)
	skater.scripted_input = _ollie(30, 60)
	var stats: Dictionary = await _run(150)
	print("    ollie: height %.2f m, air %.2f s, nose pitch up to %.0f deg, landed %s, bails %s" % [stats.max_height, stats.air_ticks / 60.0, stats.max_pitch, landed, bails])
	check(stats.max_height > 0.25, "board cleared the ground (%.2f m)" % stats.max_height)
	check(stats.air_ticks > 20, "real air time (%d ticks)" % stats.air_ticks)
	check(landed.has("Ollie"), "landed an Ollie (%s)" % [landed])
	check(bails.is_empty(), "no bail (%s)" % [bails])
	check(skater.rider.is_grounded(), "back on the ground")
	check(skater.board.deck().basis.y.y > 0.95, "board upright after landing")
	_teardown()


func test_crouch_depth_raises_the_pop() -> void:
	await _setup(3.0)
	skater.scripted_input = _ollie(58, 60)
	var quick: Dictionary = await _run(130)
	_teardown()
	await _setup(3.0)
	skater.scripted_input = _ollie(20, 60)
	var deep: Dictionary = await _run(130)
	print("    pop height: quick tap %.2f m, deep crouch %.2f m" % [quick.max_height, deep.max_height])
	check(deep.max_height > quick.max_height + 0.05, "a deep crouch pops higher")
	_teardown()


## A/D held for the whole air: nearly a full turn, which the spin assist
## finishes so the board rolls away forwards. (A 180: test_stance.)
func test_spinning_the_whole_air_lands_a_360() -> void:
	await _setup(4.0)
	skater.scripted_input = _ollie(30, 60, -1.0)
	await _run(160)
	print("    spin: landed %s bails %s, switch %s" % [landed, bails, skater.animator.is_switch()])
	check(landed == ["FS 360 Ollie"], "landed a FS 360 Ollie (%s)" % [landed])
	check(not skater.animator.is_switch(), "a 360 keeps the stance")
	check(bails.is_empty(), "no bail")
	_teardown()
