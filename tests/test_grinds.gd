extends OllieTest

var park: TestPark
var skater: SkaterController
var started: Array[String] = []
var ended: Array = []
var landed: Array[String] = []
var bails: Array[String] = []


func _setup(x: float, z: float, speed: float, yaw := 0.0) -> void:
	park = TestPark.new()
	tree.root.add_child(park)
	skater = SkaterController.new()
	tree.root.add_child(skater)
	var basis := Basis(Vector3.UP, yaw)
	skater.respawn(Transform3D(basis, Vector3(x, TestPark.FLOOR_HEIGHT, z)))
	skater.board.set_velocity(basis.z * speed)
	started.clear()
	ended.clear()
	landed.clear()
	bails.clear()
	skater.grind.grind_started.connect(func(n: String) -> void: started.append(n))
	skater.grind.grind_ended.connect(func(n: String, s: float) -> void: ended.append([n, s]))
	skater.director.trick_landed.connect(func(n: String) -> void: landed.append(n))
	skater.director.bailed.connect(func(r: String) -> void: bails.append(r))


func _teardown() -> void:
	skater.queue_free()
	park.queue_free()


## Hold Space for half a second and let go at `pop_tick`; to pop out, crouch
## again and let go at `out_pop`, leaning right (D) as it goes.
func _ollie_at(pop_tick: int, out_pop := -1) -> Callable:
	return func(tick: int) -> void:
		var pad := skater.pad
		var out := out_pop > 0 and tick >= out_pop - 12 and tick < out_pop
		pad.hold(VirtualPad.Action.POP, tick >= pop_tick - 30 and tick < pop_tick or out)
		pad.steer = 1.0 if out_pop > 0 and tick >= out_pop - 4 and tick < out_pop + 10 else 0.0


func _run(ticks: int) -> Dictionary:
	var stats := {"grind_ticks": 0, "min_y": 99.0}
	for _i in ticks:
		await tree.physics_frame
		if skater.grind.active:
			stats.grind_ticks += 1
			stats.min_y = minf(stats.min_y, skater.board.deck().position.y)
	return stats


func test_ollie_onto_rail_grinds_to_the_end() -> void:
	await _setup(-7.0, 3.0, 4.8)
	skater.scripted_input = _ollie_at(36)
	var stats: Dictionary = await _run(300)
	print("    rail: started %s, ended %s, grind %.2f s, landed %s, bails %s, lowest deck y %.2f" % [started, ended, stats.grind_ticks / 60.0, landed, bails, stats.min_y])
	check(started.any(func(n: String) -> bool: return n.contains("50-50")), "a 50-50 (%s)" % [started])
	check(stats.grind_ticks > 60, "ground along the rail (%.2f s)" % (stats.grind_ticks / 60.0))
	check(stats.min_y > TestPark.FLOOR_HEIGHT + 0.4, "stayed up on the rail (lowest %.2f)" % stats.min_y)
	check(bails.is_empty(), "no bail (%s)" % [bails])
	check(skater.rider.is_grounded() and skater.board.deck().basis.y.y > 0.95, "rode away on the floor")
	_teardown()


func test_pop_out_of_a_grind() -> void:
	await _setup(-7.0, 3.0, 4.8)
	skater.scripted_input = _ollie_at(36, 110)
	var stats: Dictionary = await _run(300)
	print("    pop out: started %s, ended %s, landed %s, bails %s" % [started, ended, landed, bails])
	check(started.size() >= 1, "grind started")
	check(ended.size() >= 1 and ended[0][1] < 1.6, "popped out early (%s)" % [ended])
	check(bails.is_empty(), "no bail (%s)" % [bails])
	check(skater.rider.is_grounded() and skater.board.deck().position.y < TestPark.FLOOR_HEIGHT + 0.2, "back on the floor beside the rail")
	_teardown()
