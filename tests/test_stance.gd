extends OllieTest

const Action := VirtualPad.Action

var park: TestPark
var skater: SkaterController
var landed: Array[String] = []


func _setup(velocity: Vector3) -> void:
	park = TestPark.new()
	tree.root.add_child(park)
	skater = SkaterController.new()
	tree.root.add_child(skater)
	skater.respawn(Transform3D(Basis.IDENTITY, Vector3(25.0, TestPark.FLOOR_HEIGHT, -40.0)))
	skater.board.set_velocity(velocity)
	landed.clear()
	skater.director.trick_landed.connect(func(n: String) -> void: landed.append(n))


func _teardown() -> void:
	skater.queue_free()
	park.queue_free()


func _run(ticks: int) -> void:
	for _i in ticks:
		await tree.physics_frame


func test_landing_a_180_rides_away_switch() -> void:
	await _setup(Vector3(0.0, 0.0, 4.0))
	var start_sign := skater.rider.facing_sign
	# Ollie with a spin, roll on, push with W, then ollie again.
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.hold(Action.POP, tick >= 30 and tick < 60 or tick >= 230 and tick < 260)
		skater.pad.steer = -1.0 if tick > 60 and tick < 80 else 0.0
		skater.pad.hold(Action.PUSH, tick >= 140 and tick < 200)
	await _run(130)
	var switched := skater.animator.is_switch()
	var forward := skater.rider.frame.forward_speed
	var speed_before := skater.board.speed()
	print("    after the 180: landed %s, switch %s, stance %s, control sign %+.0f -> %+.0f, forward speed %.2f" % [
		landed, switched, RiderAnimator.Stance.keys()[skater.animator.stance], start_sign, skater.rider.facing_sign, forward])
	check(landed == ["FS 180 Ollie"], "landed a FS 180 Ollie (%s)" % [landed])
	check(switched and skater.animator.stance == RiderAnimator.Stance.GOOFY, "now riding goofy")
	check(skater.rider.facing_sign == -start_sign, "the tail is the nose now")
	check(forward > 1.0, "rolling forward, not fakie (%.2f)" % forward)
	await _run(80)
	var speed_after := skater.board.speed()
	print("    W after the 180: %.2f -> %.2f m/s" % [speed_before, speed_after])
	check(speed_after > speed_before + 0.3, "W pushes the way it's going (%.2f -> %.2f)" % [speed_before, speed_after])
	await _run(120)
	print("    next trick: %s" % [landed])
	check(landed.size() >= 2 and landed[1] == "Switch Ollie", "the next ollie is a Switch Ollie (%s)" % [landed])
	_teardown()


func test_rolling_backwards_switches_and_respawn_resets() -> void:
	await _setup(Vector3(0.0, 0.0, -2.5))
	await _run(40)
	print("    rolled backwards: switch %s, forward speed %.2f" % [skater.animator.is_switch(), skater.rider.frame.forward_speed])
	check(skater.animator.is_switch(), "switched stance")
	check(skater.rider.frame.forward_speed > 1.0, "forward is the way of travel (%.2f)" % skater.rider.frame.forward_speed)
	check(skater.board.deck().basis.y.y > 0.95, "still upright")
	skater.respawn(Transform3D(Basis.IDENTITY, Vector3(25.0, TestPark.FLOOR_HEIGHT, -40.0)))
	check(not skater.animator.is_switch() and skater.rider.facing_sign == 1.0, "respawn rides the rider's own stance")
	_teardown()


## World position of a skeleton bone.
func _bone(name: String) -> Transform3D:
	var skeleton := skater.animator.skeleton
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name))


func test_pushing_turns_the_body_and_drives_the_foot_back() -> void:
	await _setup(Vector3.ZERO)
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.hold(Action.PUSH, tick < 200)
	var ground := TestPark.FLOOR_HEIGHT
	var best_facing := -1.0
	var lowest_foot := 99.0
	var furthest_back := 0.0
	var on_tail_between := 0
	var first_contact := -1
	for i in 260:
		await tree.physics_frame
		var rider := skater.rider
		var deck := skater.deck_effective()
		# Regular: the right foot pushes.
		var foot := deck.affine_inverse() * _bone("RightFoot").origin
		var hips_forward := _bone("Hips").basis.z
		if rider.push_phase == RidingModel.PushPhase.DRIVE:
			if first_contact < 0:
				first_contact = i
			best_facing = maxf(best_facing, hips_forward.dot(deck.basis.z))
			lowest_foot = minf(lowest_foot, _bone("RightFoot").origin.y - ground)
			furthest_back = minf(furthest_back, foot.z)
		elif first_contact >= 0 and i < 190 and rider.is_pushing():
			# Between pushes the foot swings through without standing on the tail.
			if foot.z < -0.15 and absf(foot.x) < 0.12 and foot.y < 0.11:
				on_tail_between += 1
	var rest := skater.deck_effective().affine_inverse() * _bone("RightFoot").origin
	print("    push: hips face the nose %.2f, push foot %.3f m above the ground, back to z %.2f, %d ticks on the tail between pushes, rests at %s" % [
		best_facing, lowest_foot, furthest_back, on_tail_between, rest])
	check(best_facing > 0.9, "hips turn to face the nose (%.2f)" % best_facing)
	check(lowest_foot < 0.12, "the push foot reaches the ground (%.3f m)" % lowest_foot)
	check(furthest_back < -0.3, "the foot drives back past the tail truck (%.2f)" % furthest_back)
	check(on_tail_between == 0, "no stepping back on the tail between pushes (%d ticks)" % on_tail_between)
	check(rest.z < -0.15 and rest.y > 0.05, "the foot ends back on the tail (%s)" % rest)
	_teardown()


func test_arms_hold_steady_riding_and_come_up_with_a_pop() -> void:
	await _setup(Vector3(0.0, 0.0, 5.0))
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.hold(Action.POP, tick >= 70 and tick < 100)
	await _run(60)
	# Rolling steadily at 5 m/s the hands sit by the body instead of trailing.
	var deck := skater.deck_effective()
	var hips := deck.affine_inverse() * _bone("Hips").origin
	var trail := 0.0
	for hand in ["LeftHand", "RightHand"]:
		var local := deck.affine_inverse() * _bone(hand).origin
		trail = minf(trail, local.z - hips.z)
	var riding_height := maxf(_bone("LeftHand").origin.y, _bone("RightHand").origin.y) - _bone("Hips").origin.y
	var riding_span := _bone("LeftHand").origin.distance_to(_bone("RightHand").origin)
	var air_height := -9.0
	var air_span := 0.0
	for _i in 80:
		await tree.physics_frame
		if skater.director.airborne and skater.director.air_time > 0.12 and skater.director.time_to_land > 0.15:
			var top := maxf(_bone("LeftHand").origin.y, _bone("RightHand").origin.y) - _bone("Hips").origin.y
			air_height = maxf(air_height, top)
			air_span = maxf(air_span, _bone("LeftHand").origin.distance_to(_bone("RightHand").origin))
	print("    arms: furthest hand %.2f m behind the hips at 5 m/s; highest hand %.2f m above the hips riding, %.2f in the air; hands %.2f m apart riding, %.2f in the air" % [
		-trail, riding_height, air_height, riding_span, air_span])
	check(trail > -0.35, "hands don't trail at speed (%.2f m behind)" % -trail)
	check(air_height > riding_height + 0.2, "the arms come up in the air (%.2f vs %.2f)" % [air_height, riding_height])
	check(air_span > riding_span + 0.1, "and open a little as they do (%.2f m apart vs %.2f)" % [air_span, riding_span])
	_teardown()
