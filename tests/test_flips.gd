extends OllieTest

const Action := VirtualPad.Action
## Space goes down here and the trick buttons at PRESS_TICK.
const CROUCH_TICK := 30
const PRESS_TICK := 60

var park: TestPark
var skater: SkaterController
var landed: Array[String] = []
var bails: Array[String] = []


func _setup(speed := 4.5) -> void:
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


## Crouch on Space from CROUCH_TICK, then at PRESS_TICK press each button for
## its tick count ({action: ticks}). No buttons: Space is let go at PRESS_TICK.
## `crouch` false skips Space, so the buttons pop on their own. `after` runs
## every tick from PRESS_TICK on, with ticks since then.
func _script(buttons: Dictionary, crouch := true, after := Callable()) -> Callable:
	return func(tick: int) -> void:
		var pad := skater.pad
		var space_until := PRESS_TICK if buttons.is_empty() else PRESS_TICK + 6
		pad.hold(Action.POP, crouch and tick >= CROUCH_TICK and tick < space_until)
		for action in buttons:
			pad.hold(action, tick >= PRESS_TICK and tick < PRESS_TICK + int(buttons[action]))
		if after.is_valid() and tick >= PRESS_TICK:
			after.call(tick - PRESS_TICK)


## Lowest deck up.y, and the most the deck's heading turned (summed tick by
## tick, so a 360 reads as 360).
func _run(ticks: int) -> Dictionary:
	var stats := {"min_up": 1.0, "shuv": 0.0}
	var last := skater.board.deck().basis.z
	var turned := 0.0
	for _i in ticks:
		await tree.physics_frame
		var deck := skater.board.deck()
		stats.min_up = minf(stats.min_up, deck.basis.y.y)
		var f := deck.basis.z
		f.y = 0.0
		if f.length() > 0.3:
			turned += rad_to_deg(Vector2(last.x, last.z).angle_to(Vector2(f.x, f.z)))
			last = f
			stats.shuv = maxf(stats.shuv, absf(turned))
	return stats


func _expect(buttons: Dictionary, expected: String, flips: bool, shuv_degrees := 0.0, crouch := true) -> void:
	await _setup()
	skater.scripted_input = _script(buttons, crouch)
	var stats: Dictionary = await _run(150)
	print("    %s: landed %s, bails %s, lowest deck up %.2f, widest shuv %.0f deg" % [expected, landed, bails, stats.min_up, stats.shuv])
	check(landed.size() == 1 and landed[0] == expected, "landed '%s' (got %s, bails %s)" % [expected, landed, bails])
	if flips:
		check(stats.min_up < -0.5, "the board turned over (lowest up.y %.2f)" % stats.min_up)
	if shuv_degrees > 0.0:
		check(stats.shuv > shuv_degrees - 25.0, "the board shoved round (%.0f deg)" % stats.shuv)
	_teardown()


func test_kickflip() -> void:
	await _expect({Action.KICKFLIP: 5}, "Kickflip", true)


func test_heelflip() -> void:
	await _expect({Action.HEELFLIP: 5}, "Heelflip", true)


func test_a_trick_button_pops_on_its_own() -> void:
	await _expect({Action.KICKFLIP: 5}, "Kickflip", true, 0.0, false)


func test_two_buttons_make_a_varial_kickflip() -> void:
	await _expect({Action.KICKFLIP: 5, Action.SHUVIT: 6}, "Varial Kickflip", true, 150.0)


func test_heel_and_frontside_make_a_varial_heelflip() -> void:
	await _expect({Action.HEELFLIP: 6, Action.FS_SHUVIT: 5}, "Varial Heelflip", true, 150.0)


func test_holding_the_shuvit_button_makes_a_360() -> void:
	await _expect({Action.SHUVIT: 30}, "360 Shove-it", false, 330.0)


func test_360_flip() -> void:
	await _expect({Action.KICKFLIP: 5, Action.SHUVIT: 30}, "360 Flip", true, 330.0)


func test_nollie_and_nollie_kickflip() -> void:
	await _expect({Action.NOLLIE: 70}, "Nollie", false)
	await _expect({Action.NOLLIE: 70, Action.KICKFLIP: 5}, "Nollie Kickflip", true)


func test_pop_shuvit_swaps_the_nose() -> void:
	var sign_before := 1.0
	await _setup()
	sign_before = skater.rider.facing_sign
	skater.scripted_input = _script({Action.SHUVIT: 5})
	var stats: Dictionary = await _run(150)
	print("    pop shove-it: landed %s, bails %s, shuv %.0f deg, facing sign %+.0f -> %+.0f" % [landed, bails, stats.shuv, sign_before, skater.rider.facing_sign])
	check(landed == ["Pop Shove-it"], "landed a Pop Shove-it (%s %s)" % [landed, bails])
	check(skater.rider.facing_sign == -sign_before, "the deck's tail is now the rider's nose")
	_teardown()


func test_holding_the_flip_button_makes_a_double() -> void:
	await _setup(5.0)
	skater.scripted_input = _script({Action.KICKFLIP: 30})
	await _run(160)
	print("    held kickflip: landed %s bails %s" % [landed, bails])
	check(landed.size() == 1 and (landed[0].begins_with("Double") or landed[0].begins_with("Triple")), "a double or triple (%s %s)" % [landed, bails])
	_teardown()


func test_flip_button_after_an_ollie_is_a_late_flip() -> void:
	await _setup(5.0)
	skater.scripted_input = _script({}, true, func(t: int) -> void:
		skater.pad.hold(Action.KICKFLIP, t >= 6 and t < 10))
	await _run(160)
	print("    late flip: landed %s bails %s" % [landed, bails])
	check(landed == ["Late Kickflip"], "a late kickflip (%s %s)" % [landed, bails])
	_teardown()


func test_grab_lands_when_released_in_time() -> void:
	await _setup(5.0)
	skater.scripted_input = _script({}, true, func(t: int) -> void:
		skater.pad.hold(Action.BOARD, t > 8 and t < 22))
	await _run(160)
	print("    grab: landed %s bails %s" % [landed, bails])
	check(landed == ["Indy"], "an Indy (%s %s)" % [landed, bails])
	_teardown()


func test_w_with_the_grab_is_a_nosegrab() -> void:
	await _setup(5.0)
	skater.scripted_input = _script({}, true, func(t: int) -> void:
		skater.pad.hold(Action.BOARD, t > 8 and t < 22)
		skater.pad.hold(Action.PUSH, t > 9 and t < 22))
	await _run(160)
	print("    nosegrab: landed %s bails %s" % [landed, bails])
	check(landed == ["Nosegrab"], "a Nosegrab (%s %s)" % [landed, bails])
	_teardown()


func test_holding_a_grab_into_the_landing_bails() -> void:
	await _setup(5.0)
	skater.scripted_input = _script({}, true, func(t: int) -> void:
		skater.pad.hold(Action.BOARD, t > 8))
	await _run(160)
	check(bails.size() == 1, "bailed (%s %s)" % [landed, bails])
	_teardown()
