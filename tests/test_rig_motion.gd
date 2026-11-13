extends OllieTest

const Action := VirtualPad.Action
const START := Vector3(25.0, TestPark.FLOOR_HEIGHT, -40.0)
## Deck-space height of an ankle standing on level ground beside the board.
const GROUND_ANKLE := RiderAnimator.ANKLE_HEIGHT - BoardSpec.LEVEL_GROUND_DECK_HEIGHT

var park: TestPark
var skater: SkaterController


func _setup(velocity: Vector3, spawn := Transform3D(Basis.IDENTITY, START)) -> void:
	park = TestPark.new()
	tree.root.add_child(park)
	# Let the level reach the physics space, so every run starts from the same world.
	await tree.physics_frame
	await tree.physics_frame
	skater = SkaterController.new()
	tree.root.add_child(skater)
	# A private copy, so a test changing the feel doesn't change it for the rest.
	skater.animator.feel = RiderFeel.new()
	skater.respawn(spawn)
	skater.board.set_velocity(velocity)


func _teardown() -> void:
	skater.queue_free()
	park.queue_free()


## Skeleton bone in the world, and in the deck's frame.
func _bone(name: String) -> Transform3D:
	var skeleton := skater.animator.skeleton
	return skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(name))


func _on_deck(name: String) -> Vector3:
	return skater.deck_effective().affine_inverse() * _bone(name).origin


func test_second_order_overshoots_settles_and_stays_stable() -> void:
	var dt := 1.0 / 60.0
	var soft := MotionFilters.SecondOrder.new(2.0, 0.4, 0.0)
	var firm := MotionFilters.SecondOrder.new(2.0, 1.0, 0.0)
	var lagging := MotionFilters.SecondOrder.new(2.0, 0.6, -1.5)
	var stiff := MotionFilters.SecondOrder.new(40.0, 0.2, 2.0)
	var soft_peak := 0.0
	var firm_peak := 0.0
	var lagging_low := 0.0
	var stiff_peak := 0.0
	soft.update(0.0, dt)
	firm.update(0.0, dt)
	lagging.update(0.0, dt)
	stiff.update(0.0, dt)
	for _i in 240:
		soft_peak = maxf(soft_peak, soft.update(1.0, dt))
		firm_peak = maxf(firm_peak, firm.update(1.0, dt))
		lagging_low = minf(lagging_low, lagging.update(1.0, dt))
		stiff_peak = maxf(stiff_peak, absf(stiff.update(1.0, dt)))
	print("    step response: damping 0.4 peaks at %.2f, 1.0 at %.3f; response -1.5 dips to %.2f first; a 40 Hz follower peaks at %.2f" % [
		soft_peak, firm_peak, lagging_low, stiff_peak])
	check(soft_peak > 1.15 and soft_peak < 1.4, "low damping overshoots (%.2f)" % soft_peak)
	check(firm_peak < 1.01, "critical damping does not (%.3f)" % firm_peak)
	check(lagging_low < -0.05, "a negative response goes the wrong way first (%.2f)" % lagging_low)
	check_near(soft.value, 1.0, 0.01, "settles on the target")
	check_near(lagging.value, 1.0, 0.01, "settles on the target")
	check(stiff_peak < 4.0 and absf(stiff.value - 1.0) < 0.05, "stays stable beyond the tick rate (%.2f)" % stiff_peak)
	# A turning target is followed without trailing; a jump lags, then swings past.
	var rotation := MotionFilters.SpringRotation.new(3.0, 0.5)
	var angle := 0.0
	rotation.update(Quaternion.IDENTITY, dt)
	for _i in 180:
		angle += 2.0 * dt
		rotation.update(Quaternion(Vector3.UP, angle), dt)
	var trailing := MotionFilters.SpringRotation.rotation_vector(rotation.value, Quaternion(Vector3.UP, angle)).length()
	var past := 0.0
	var goal := Quaternion(Vector3.UP, angle + 0.5)
	for _i in 120:
		rotation.update(goal, dt)
		past = maxf(past, MotionFilters.SpringRotation.rotation_vector(goal, rotation.value).dot(Vector3.UP))
	print("    rotation: %.3f rad behind a steady turn; %.2f rad past a half-radian jump" % [trailing, past])
	check(trailing < 0.02, "keeps up with a steady turn (%.3f rad behind)" % trailing)
	check(past > 0.03 and past < 0.3, "swings past a sudden turn and comes back (%.2f rad)" % past)


## Deck positions over a scripted run with the given feel.
func _trajectory(extreme: bool, spawn: Transform3D, velocity: Vector3, ticks: int, script: Callable) -> PackedVector3Array:
	await _setup(velocity, spawn)
	if extreme:
		var feel := skater.animator.feel
		feel.weight_frequency = 0.9
		feel.weight_load = 3.0
		feel.landing_give = 1.5
		feel.pop_extension = 0.0
		feel.air_tuck = 0.0
		feel.lean_gain = 0.1
		feel.lean_along_gain = 1.5
		feel.balance_frequency = 0.6
		feel.chest_inertia = 2.0
		feel.arm_inertia = 2.0
		feel.arm_float = 2.0
		feel.arm_use = 0.0
		feel.stand_foot_down = false
		feel.arm_tone = 3.0
		feel.arm_level = 0.0
		feel.arm_ready_speed = 0.5
		feel.pop_arm_lift = 3.0
		feel.arm_variety = 0.0
		feel.wrist_droop = 2.0
		feel.setup_stance = 0.0
		feel.sway_amount = 6.0
		feel.push_height = 0.7
		feel.push_bob = 0.15
		feel.push_lean = 0.6
		feel.push_full_speed = 2.0
		feel.push_stride = 0.0
		feel.push_follow_through = 2.0
		feel.push_speed_crouch = 0.2
		feel.push_speed_lean = 0.0
	skater.scripted_input = script.bind(skater)
	var out := PackedVector3Array()
	for _i in ticks:
		await tree.physics_frame
		out.append(skater.board.deck().position)
	_teardown()
	return out


func test_the_feel_never_reaches_the_simulation() -> void:
	# An ollie with a carve before it, the half pipe with W pumping, and pushing
	# up to speed from a standstill with an ollie straight out of the last push.
	var ollie := func(tick: int, s: SkaterController) -> void:
		s.pad.steer = 0.8 if tick < 40 else 0.0
		s.pad.hold(Action.POP, tick >= 50 and tick < 80)
	var pump := func(tick: int, s: SkaterController) -> void:
		s.pad.hold(Action.PUSH, tick > 30)
	var push := func(tick: int, s: SkaterController) -> void:
		s.pad.hold(Action.PUSH, tick > 10 and tick < 260)
		s.pad.hold(Action.POP, tick >= 262 and tick < 292)
	# Standing still (a foot down, or not), then an ollie on the spot and a push off.
	var stand := func(tick: int, s: SkaterController) -> void:
		s.pad.hold(Action.POP, tick >= 100 and tick < 130)
		s.pad.hold(Action.PUSH, tick > 260)
	var flat := Transform3D(Basis.IDENTITY, START)
	var pipe := Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(12.0, TestPark.FLOOR_HEIGHT, 0.0))
	var worst := 0.0
	for run in [[flat, Vector3(0.0, 0.0, 4.5), 200, ollie], [pipe, Vector3(4.5, 0.0, 0.0), 420, pump],
			[flat, Vector3.ZERO, 360, push], [flat, Vector3.ZERO, 360, stand]]:
		var plain := await _trajectory(false, run[0], run[1], run[2], run[3])
		var changed := await _trajectory(true, run[0], run[1], run[2], run[3])
		for i in plain.size():
			worst = maxf(worst, plain[i].distance_to(changed[i]))
	print("    wildly different feel: the board's path differs by at most %.9f m" % worst)
	check(worst < 1e-6, "the board goes exactly the same way whatever the feel (%.9f m apart)" % worst)


func test_steady_roll_is_quiet_and_feet_stay_planted() -> void:
	await _setup(Vector3(0.0, 0.0, 5.0))
	for _i in 120:
		await tree.physics_frame
	var names := ["Hips", "UpperChest", "Head", "LeftHand", "RightHand"]
	var previous := {}
	var fastest := 0.0
	var foot_drift := 0.0
	var longest_leg := 0.0
	var reach := skater.animator.solver.leg_length()
	var front := _on_deck("LeftFoot")
	var back := _on_deck("RightFoot")
	for i in 90:
		await tree.physics_frame
		for name in names:
			var p: Vector3 = _on_deck(name)
			if previous.has(name):
				fastest = maxf(fastest, p.distance_to(previous[name]) * 60.0)
			previous[name] = p
		foot_drift = maxf(foot_drift, maxf(_on_deck("LeftFoot").distance_to(front), _on_deck("RightFoot").distance_to(back)))
		for side in ["Left", "Right"]:
			longest_leg = maxf(longest_leg, _bone(side + "UpperLeg").origin.distance_to(_bone(side + "Foot").origin))
	print("    rolling at 5 m/s: body parts drift at up to %.3f m/s over the board, feet move %.4f m, legs reach %.0f%% of their length" % [
		fastest, foot_drift, longest_leg / reach * 100.0])
	check(fastest < 0.12, "the body is quiet when nothing is happening (%.3f m/s)" % fastest)
	check(foot_drift < 0.005, "feet stay where they stand (%.4f m)" % foot_drift)
	check(longest_leg < reach * 0.995, "knees never lock (%.0f%%)" % (longest_leg / reach * 100.0))
	_teardown()


func test_landing_has_weight_and_the_chest_follows_the_hips() -> void:
	await _setup(Vector3(0.0, 0.0, 4.0))
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.hold(Action.POP, tick >= 30 and tick < 60)
	for _i in 28:
		await tree.physics_frame
	var standing := _on_deck("Hips").y
	var head_standing := _on_deck("Head").y
	var landed_at := -1
	var lowest := 99.0
	var lowest_at := 0
	var chest_fold := 0.0
	var chest_fold_at := 0
	var highest_after := 0.0
	var head_drop := 0.0
	var reach := skater.animator.solver.leg_length()
	var longest_leg := 0.0
	var trace: Array[String] = []
	for i in 230:
		await tree.physics_frame
		for side in ["Left", "Right"]:
			longest_leg = maxf(longest_leg, _bone(side + "UpperLeg").origin.distance_to(_bone(side + "Foot").origin))
		if skater.rider.just_landed and landed_at < 0:
			landed_at = i
		if landed_at < 0:
			continue
		var since := i - landed_at
		var hips := _on_deck("Hips").y
		# How far the chest is folded over: its up against the world's.
		var fold := acos(clampf(_bone("UpperChest").basis.y.normalized().dot(Vector3.UP), -1.0, 1.0))
		if since % 4 == 0 and since <= 48:
			trace.append("%d:%.2f/%.0f" % [since, hips, rad_to_deg(fold)])
		if hips < lowest:
			lowest = hips
			lowest_at = since
		if fold > chest_fold and since < 40:
			chest_fold = fold
			chest_fold_at = since
		if since > lowest_at + 4 and since < 100:
			highest_after = maxf(highest_after, hips)
		head_drop = maxf(head_drop, head_standing - _on_deck("Head").y)
	print("    landing (tick:hips m/chest deg): %s" % " ".join(trace))
	print("    hips stand at %.2f m, sink to %.2f m %d ticks after landing, back up to %.2f m at most; chest furthest over at %d ticks; legs reach %.0f%%" % [
		standing, lowest, lowest_at, highest_after, chest_fold_at, longest_leg / reach * 100.0])
	check(landed_at > 0, "landed")
	check(standing - lowest > 0.08, "the legs give on landing (%.2f m)" % (standing - lowest))
	check(lowest_at >= 4 and lowest_at <= 22, "sinking takes a moment, not a frame (%d ticks)" % lowest_at)
	check(highest_after < standing + 0.02, "no bounce above standing (%.2f vs %.2f m)" % [highest_after, standing])
	check(chest_fold_at > lowest_at - 6, "the chest folds as the hips bottom out or after, not before (%d vs %d ticks)" % [chest_fold_at, lowest_at])
	check(longest_leg < reach * 0.995, "knees never lock through the pop and landing (%.0f%%)" % (longest_leg / reach * 100.0))
	_teardown()


func test_carving_leans_in_with_the_head_level() -> void:
	await _setup(Vector3(0.0, 0.0, 5.0))
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.steer = 1.0 if tick > 30 else 0.0
	var hips_lean := 0.0
	var head_lean := 0.0
	var into := 0.0
	for i in 110:
		await tree.physics_frame
		if i < 70:
			continue
		# Lean toward the inside of the turn, measured against the world's up.
		var deck := skater.deck_effective()
		var feet := deck.origin
		var hips := _bone("Hips").origin - feet
		var inside := deck.basis.x * signf(skater.board.deck().angular_velocity.y)
		into = maxf(into, hips.dot(inside))
		# Sideways tip toward the inside of the turn (not the nod of looking down).
		var hips_up := _bone("Hips").basis.y
		var head_up := _bone("Head").basis.y
		hips_lean = maxf(hips_lean, atan2(hips_up.dot(inside), hips_up.dot(Vector3.UP)))
		head_lean = maxf(head_lean, atan2(head_up.dot(inside), head_up.dot(Vector3.UP)))
	print("    carving hard at 5 m/s: hips %.2f m inside the board, tipped %.0f deg; head tipped %.0f deg" % [
		into, rad_to_deg(hips_lean), rad_to_deg(head_lean)])
	check(into > 0.08, "the body leans into the turn (%.2f m)" % into)
	check(head_lean < hips_lean * 0.75, "the head stays more level than the hips (%.0f vs %.0f deg)" % [rad_to_deg(head_lean), rad_to_deg(hips_lean)])
	_teardown()


func test_braking_shifts_the_weight_back_then_returns() -> void:
	await _setup(Vector3(0.0, 0.0, 5.0))
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.hold(Action.BRAKE, tick >= 60 and tick < 100)
	for _i in 58:
		await tree.physics_frame
	var rest := _on_deck("Hips").z
	var furthest_back := 0.0
	var furthest_forward := 0.0
	for i in 200:
		await tree.physics_frame
		var shift := _on_deck("Hips").z - rest
		furthest_back = minf(furthest_back, shift)
		if i > 45:
			furthest_forward = maxf(furthest_forward, shift)
	var settled := _on_deck("Hips").z - rest
	print("    braking: hips go %.3f m toward the tail, swing %.3f m past centre as it lets go, settle at %+.3f m" % [
		-furthest_back, furthest_forward, settled])
	check(furthest_back < -0.04, "weight goes back against the brakes (%.3f m)" % -furthest_back)
	check(furthest_forward > 0.004, "and swings through as they let go (%.3f m)" % furthest_forward)
	check(absf(settled) < 0.02, "then settles over the board (%+.3f m)" % settled)
	_teardown()


## Through one trick in the air: how the legs hold up while the board turns
## under them. Knees are measured against the way the rider faces, in the rig.
func _legs_through(buttons: Array, hold_ticks: int) -> Dictionary:
	await _setup(Vector3(0.0, 0.0, 4.5))
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.hold(Action.POP, tick >= 20 and tick < 56)
		for button: VirtualPad.Action in buttons:
			skater.pad.hold(button, tick >= 50 and tick < 50 + hold_ticks)
	var landed: Array[String] = []
	skater.director.trick_landed.connect(func(n: String) -> void: landed.append(n))
	var out := {"knee": 9.0, "apart": 9.0, "toes": 9.0, "turn": 0.0, "landed": landed, "free": 0}
	var previous := {}
	for _i in 150:
		await tree.physics_frame
		if not skater.director.airborne:
			previous.clear()
			continue
		var to_rig := skater.rider_frame.affine_inverse()
		var face: Vector3 = skater.animator.facing()
		if skater.animator._free > 0.5:
			out.free += 1
		for side in ["Left", "Right"]:
			var hip := to_rig * _bone(side + "UpperLeg").origin
			var knee := to_rig * _bone(side + "LowerLeg").origin
			var ankle := to_rig * _bone(side + "Foot").origin
			# Which way the knee sticks out from the line of the leg.
			var line := (ankle - hip).normalized()
			var bent := (knee - hip) - line * line.dot(knee - hip)
			if bent.length() > 0.03:
				bent = bent.normalized()
				out.knee = minf(out.knee, bent.dot(face))
				if previous.has(side):
					out.turn = maxf(out.turn, bent.angle_to(previous[side]))
				previous[side] = bent
			var toes := (to_rig.basis * _bone(side + "Toes").basis.y).normalized()
			out.toes = minf(out.toes, toes.dot((face + Vector3.BACK * 0.5).normalized()))
		# Regular: the left foot leads.
		out.apart = minf(out.apart, (to_rig * _bone("LeftFoot").origin).z - (to_rig * _bone("RightFoot").origin).z)
	_teardown()
	return out


func test_legs_stay_untwisted_while_the_board_turns_under_them() -> void:
	var tricks := [["Kickflip", [Action.KICKFLIP], 4], ["Heelflip", [Action.HEELFLIP], 4],
		["Pop Shove-it", [Action.SHUVIT], 4], ["FS Pop Shove-it", [Action.FS_SHUVIT], 4],
		["360 Shove-it", [Action.SHUVIT], 40], ["Varial Kickflip", [Action.KICKFLIP, Action.SHUVIT], 4],
		["360 Flip", [Action.KICKFLIP, Action.SHUVIT], 40], ["Hardflip", [Action.KICKFLIP, Action.FS_SHUVIT], 4]]
	for trick in tricks:
		var legs: Dictionary = await _legs_through(trick[1], trick[2])
		print("    %s: landed %s; knees face forward %.2f at worst, turn %.0f deg a tick at most; feet %.2f m apart at least; toes forward %.2f at worst; %d ticks off the board" % [
			trick[0], legs.landed, legs.knee, rad_to_deg(legs.turn), legs.apart, legs.toes, legs.free])
		check(legs.landed.has(trick[0]), "%s landed (%s)" % [trick[0], legs.landed])
		check(legs.free >= 6, "%s: the feet leave the board while it turns (%d ticks)" % [trick[0], legs.free])
		check(legs.knee > 0.2, "%s: knees never point behind the rider (%.2f)" % [trick[0], legs.knee])
		check(legs.turn < deg_to_rad(40.0), "%s: knees never whip round (%.0f deg in a tick)" % [trick[0], rad_to_deg(legs.turn)])
		check(legs.apart > 0.18, "%s: the legs never cross (%.2f m apart)" % [trick[0], legs.apart])
		check(legs.toes > 0.0, "%s: feet never point behind the rider (%.2f)" % [trick[0], legs.toes])


func test_pushing_moves_the_whole_body_without_jerks() -> void:
	await _setup(Vector3.ZERO)
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.hold(Action.PUSH, tick < 260)
	for _i in 100:
		await tree.physics_frame
	# Regular: the right foot pushes. Everything is measured over the board.
	var foot_previous := _on_deck("RightFoot")
	var speed_previous := Vector3.ZERO
	var jerk := 0.0
	var jerk_at := ""
	var hips_low := 9.0
	var hips_high := 0.0
	var fold_low := 9.0
	var fold_high := 0.0
	var foot_back := 0.0
	var ground_back := 0.0
	# For the arms: where the push leg is against where each hand is from its
	# own shoulder (so the trunk's lean is not counted as arm swing).
	var legs: Array[float] = []
	var hands: Array[float] = []
	var other: Array[float] = []
	var trace: Array[String] = []
	for i in 150:
		await tree.physics_frame
		var rider := skater.rider
		var foot := _on_deck("RightFoot")
		var speed := (foot - foot_previous) * 60.0
		# The plant and the first tick of the drive are the ground taking the foot;
		# everywhere else the foot's speed should change smoothly.
		var planted := rider.push_phase == RidingModel.PushPhase.DRIVE
		if i > 1 and not planted:
			var change := (speed - speed_previous).length() * 60.0
			if change > jerk:
				jerk = change
				jerk_at = "%s %.2f" % [RidingModel.PushPhase.keys()[rider.push_phase], rider.push_progress()]
		foot_previous = foot
		speed_previous = speed
		var hips := _on_deck("Hips")
		hips_low = minf(hips_low, hips.y)
		hips_high = maxf(hips_high, hips.y)
		var fold := acos(clampf(_bone("UpperChest").basis.y.normalized().dot(Vector3.UP), -1.0, 1.0))
		fold_low = minf(fold_low, fold)
		fold_high = maxf(fold_high, fold)
		foot_back = minf(foot_back, foot.z)
		if foot.y < GROUND_ANKLE + 0.03:
			ground_back = minf(ground_back, foot.z)
		legs.append(foot.z - hips.z)
		hands.append(_on_deck("RightHand").z - _on_deck("RightUpperArm").z)
		other.append(_on_deck("LeftHand").z - _on_deck("LeftUpperArm").z)
		if i < 44 and i % 2 == 0:
			trace.append("%s%.0f:z%+.2f y%.2f h%.2f" % [RidingModel.PushPhase.keys()[rider.push_phase][0], rider.push_progress() * 9.0, foot.z, foot.y, hips.y])
	var same := _correlation(legs, hands)
	var across := _correlation(legs, other)
	print("    push foot: %s" % " ".join(trace))
	# The drive ends where the foot lets go of the ground; it should carry on past that.
	var carried := ground_back - foot_back
	print("    pushing: hips bob %.3f m, trunk rocks %.0f deg, foot carries %.3f m past the end of the drive, sharpest change of foot speed %.0f m/s2 (%s); push-side arm against its leg %.2f, other arm %.2f" % [
		hips_high - hips_low, rad_to_deg(fold_high - fold_low), carried, jerk, jerk_at, same, across])
	check(hips_high - hips_low > 0.03 and hips_high - hips_low < 0.16, "the hips drop into each push and rise out of it (%.3f m)" % (hips_high - hips_low))
	check(fold_high - fold_low > deg_to_rad(4.0), "the trunk goes into the drive and comes back (%.0f deg)" % rad_to_deg(fold_high - fold_low))
	check(carried > 0.03, "the foot follows through after it leaves the ground (%.3f m)" % carried)
	check(jerk < 110.0, "the swinging foot's speed never jumps (%.0f m/s2 at %s)" % [jerk, jerk_at])
	check(same < -0.4, "the arm on the pushing side goes forward as its leg goes back (%.2f)" % same)
	check(across > 0.4, "and the other arm goes back with the leg (%.2f)" % across)
	_teardown()


## Interior angle of a knee (degrees): 180 is a straight leg.
func _knee(side: String) -> float:
	var knee := _bone(side + "LowerLeg").origin
	return rad_to_deg((_bone(side + "UpperLeg").origin - knee).angle_to(_bone(side + "Foot").origin - knee))


## Pushing from a standstill up to speed, one row per push: the speed it was
## planted at, and what the body did through it.
func _pushes() -> Array[Dictionary]:
	await _setup(Vector3.ZERO)
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.hold(Action.PUSH, tick > 10)
	var rows: Array[Dictionary] = []
	var row := {}
	var last := RidingModel.PushPhase.NONE
	for _i in 480:
		await tree.physics_frame
		var rider := skater.rider
		var hips := _on_deck("Hips")
		var foot := _on_deck("RightFoot")
		if rider.push_phase == RidingModel.PushPhase.DRIVE and last != RidingModel.PushPhase.DRIVE:
			if not row.is_empty():
				rows.append(row)
			# `front` is where the foot came down; `glide` counts the ticks the
			# leg hangs behind before swinging forward, and how it holds there.
			row = {"speed": rider.frame.absolute_speed, "front": foot.z, "back": 9.0, "low": 9.0, "tall": 0.0, "lean": 0.0,
				"head": -9.0, "ticks": 0, "glide": 0, "glide_near": 9.0, "glide_far": -9.0, "glide_low": 9.0,
				"hand_high": -9.0, "elbow_high": -9.0}
		last = rider.push_phase
		if row.is_empty():
			continue
		var up := skater.deck_effective().basis.inverse() * _bone("UpperChest").basis.y
		var lean := atan2(up.z, up.y)
		row.ticks += 1
		row.low = minf(row.low, hips.y)
		row.tall = maxf(row.tall, hips.y)
		row.lean = maxf(row.lean, lean)
		row.head = maxf(row.head, _on_deck("Head").z - _on_deck("LeftFoot").z)
		# The arm that comes forward (the pushing side's): how high its hand and
		# elbow get, from the shoulder.
		var shoulder := _on_deck("RightUpperArm").y
		row.hand_high = maxf(row.hand_high, _on_deck("RightHand").y - shoulder)
		row.elbow_high = maxf(row.elbow_high, _on_deck("RightLowerArm").y - shoulder)
		if rider.push_phase == RidingModel.PushPhase.HANG:
			row.glide += 1
			row.glide_near = minf(row.glide_near, hips.z - foot.z)
			row.glide_far = maxf(row.glide_far, hips.z - foot.z)
			row.glide_low = minf(row.glide_low, foot.y - GROUND_ANKLE)
		if foot.z < row.back:
			# The leg at its furthest behind: the end of the push.
			row.back = foot.z
			row.behind = hips.z - foot.z
			row.lifted = foot.y - GROUND_ANKLE
			row.lean_then = lean
			row.hand = _on_deck("RightHand").z - hips.z
			row.other_hand = _on_deck("LeftHand").z - hips.z
			row.leg = _knee("Right")
			row.support = _knee("Left")
	_teardown()
	return rows


func test_pushes_grow_with_speed_and_end_stretched_out() -> void:
	var rows := await _pushes()
	var slow := rows[0]
	var fast := rows[rows.size() - 1]
	for row in [slow, fast]:
		print("    pushing at %.1f m/s: stroke %.2f m (%+.2f to %+.2f), hips %.2f..%.2f m, trunk %.0f deg forward, foot %.2f m off the ground behind" % [
			row.speed, row.front - row.back, row.front, row.back, row.low, row.tall, rad_to_deg(row.lean), row.lifted])
	check(slow.speed < 2.0 and fast.speed > 5.0, "a slow push and a fast one to compare (%.1f, %.1f m/s)" % [slow.speed, fast.speed])
	# Larger pushes going faster, shorter going slower.
	var slow_stroke: float = slow.front - slow.back
	var fast_stroke: float = fast.front - fast.back
	check(fast_stroke > slow_stroke + 0.3, "the stroke is longer at speed (%.2f m against %.2f m)" % [fast_stroke, slow_stroke])
	check(slow_stroke < 0.65, "and short when slow (%.2f m)" % slow_stroke)
	var shrank := 0.0
	for i in range(2, rows.size()):
		shrank = maxf(shrank, (rows[i - 1].front - rows[i - 1].back) - (rows[i].front - rows[i].back))
	check(shrank < 0.03, "each push is at least as long as the one before while speeding up (shrank %.3f m)" % shrank)
	# Lower over the board at speed, a little.
	check(fast.tall < slow.tall - 0.02 and fast.tall > slow.tall - 0.12, "the rider stays a little lower at speed (%.2f m against %.2f m)" % [fast.tall, slow.tall])
	check(fast.low < slow.low - 0.03, "and sinks further into each push (%.2f m against %.2f m)" % [fast.low, slow.low])
	check(fast.lean > slow.lean + deg_to_rad(12.0), "the trunk goes further forward (%.0f deg against %.0f deg)" % [rad_to_deg(fast.lean), rad_to_deg(slow.lean)])
	check(slow.lean < deg_to_rad(30.0), "a slow push stays fairly upright (%.0f deg)" % rad_to_deg(slow.lean))
	# The end of a big push: the leg stretched out behind and off the ground,
	# the trunk forward over the front foot, the arm on the pushing side
	# reaching ahead and the other back.
	print("    end of the fast push: foot %.2f m behind the hips and %.2f m up, leg %.0f deg, trunk %.0f deg, head %+.2f m from the front foot, hands %+.2f / %+.2f m, support knee %.0f deg" % [
		fast.behind, fast.lifted, fast.leg, rad_to_deg(fast.lean_then), fast.head, fast.hand, fast.other_hand, fast.support])
	check(fast.behind > 0.6, "the leg ends far behind the hips (%.2f m)" % fast.behind)
	check(fast.lifted > 0.15, "with the foot well off the ground (%.2f m)" % fast.lifted)
	check(fast.leg > 135.0, "and the leg nearly straight (%.0f deg at the knee)" % fast.leg)
	check(fast.lean_then > deg_to_rad(30.0) and fast.lean_then < deg_to_rad(60.0), "the trunk is well forward as it does (%.0f deg)" % rad_to_deg(fast.lean_then))
	check(fast.head > 0.0, "the head gets over or past the front foot (%+.2f m)" % fast.head)
	check(fast.hand > 0.3 and fast.other_hand < fast.hand - 0.4, "the arm on the pushing side reaches ahead, the other is back (%+.2f, %+.2f m)" % [fast.hand, fast.other_hand])
	check(fast.support > 80.0 and fast.support < 125.0, "the front knee is bent over the board (%.0f deg)" % fast.support)
	# An easy stride, not a punch: the arm that comes forward stays low, the
	# elbow well under the shoulder and the hand below it too.
	print("    the arm coming forward: elbow never higher than %+.2f m from the shoulder, hand %+.2f m (fast); hand %+.2f m (slow)" % [fast.elbow_high, fast.hand_high, slow.hand_high])
	check(fast.elbow_high < -0.14, "the upper arm hangs more than it reaches (elbow %+.2f m from the shoulder)" % fast.elbow_high)
	check(fast.hand_high < -0.05 and slow.hand_high < -0.05, "and the hand stays below the shoulder (%+.2f m, %+.2f m)" % [fast.hand_high, slow.hand_high])
	check(slow.behind < fast.behind - 0.2 and slow.lifted < fast.lifted - 0.08, "a slow push ends much smaller (%.2f m behind, %.2f m up)" % [slow.behind, slow.lifted])


## At speed the pushes are not one straight after another: the leg stays behind
## at the end of each, held there while the rider glides, before it swings
## forward for the next.
func test_the_leg_hangs_behind_between_pushes_at_speed() -> void:
	var rows := await _pushes()
	var slow := rows[0]
	var fast := rows[rows.size() - 1]
	print("    a push at %.1f m/s takes %d ticks with no glide (%d); at %.1f m/s %d ticks, %d of them gliding with the foot %.2f..%.2f m behind the hips, at least %.2f m off the ground" % [
		slow.speed, slow.ticks, slow.glide, fast.speed, fast.ticks, fast.glide, fast.glide_near, fast.glide_far, fast.glide_low])
	check(slow.glide == 0, "slow pushes run straight into each other (%d ticks gliding)" % slow.glide)
	check(fast.speed > 6.0 and fast.glide >= 10, "at speed the leg hangs behind a while (%d ticks at %.1f m/s)" % [fast.glide, fast.speed])
	check(fast.glide_near > 0.5, "well behind the hips the whole time (%.2f m at the nearest)" % fast.glide_near)
	check(fast.glide_far - fast.glide_near < 0.2, "and nearly still there (moves %.2f m)" % (fast.glide_far - fast.glide_near))
	check(fast.glide_low > 0.1, "off the ground (%.2f m)" % fast.glide_low)


## The hands in the deck's frame: how far apart they are, each one's height
## from the hips, and where each is from its own shoulder (`left`, `right`).
func _hands() -> Dictionary:
	var hips := _on_deck("Hips")
	var left := _on_deck("LeftHand")
	var right := _on_deck("RightHand")
	return {"span": left.distance_to(right), "front": left.y - hips.y, "back": right.y - hips.y,
		"left": left - _on_deck("LeftUpperArm"), "right": right - _on_deck("RightUpperArm")}


## How far the further-moved hand is from where it was in `rest`, each
## measured from its own shoulder.
static func _moved(hands: Dictionary, rest: Dictionary) -> float:
	return maxf((hands.left as Vector3).distance_to(rest.left), (hands.right as Vector3).distance_to(rest.right))


## Nobody balances on a board that is standing still: the back foot goes down
## beside it, a push starts straight from that foot, and it comes back up to
## ride and to crouch for a pop.
func test_standing_still_the_back_foot_goes_down() -> void:
	await _setup(Vector3.ZERO)
	for _i in 70:
		await tree.physics_frame
	var foot := _on_deck("RightFoot")
	var front := _on_deck("LeftFoot")
	var facing := (skater.deck_effective().basis.inverse() * _bone("Hips").basis.z).z
	print("    standing still: back foot %.3f m above the ground, %.2f m out from the middle of the board, %+.2f m along it; front foot %.3f m above the deck; hips face the nose %.2f" % [
		foot.y - GROUND_ANKLE, absf(foot.x), foot.z, front.y - RiderAnimator.ANKLE_HEIGHT, facing])
	check(absf(foot.y - GROUND_ANKLE) < 0.015, "the back foot is on the ground (%.3f m above it)" % (foot.y - GROUND_ANKLE))
	check(absf(foot.x) > BoardSpec.DECK_WIDTH * 0.5 + 0.04, "beside the board (%.2f m out)" % absf(foot.x))
	check(front.y > 0.06 and absf(front.x) < 0.1, "with the front foot still on it")
	check(facing > 0.75, "and the body turned toward the nose (%.2f)" % facing)
	# Pushing off: the drive starts from where the foot stands.
	skater.scripted_input = func(_tick: int) -> void:
		skater.pad.hold(Action.PUSH, true)
	var highest := 0.0
	var contact := false
	for _i in 40:
		await tree.physics_frame
		contact = contact or skater.rider.push_phase == RidingModel.PushPhase.DRIVE
		if not contact:
			highest = maxf(highest, _on_deck("RightFoot").y - GROUND_ANKLE)
	for _i in 40:
		await tree.physics_frame
	print("    pushing off: the foot rises at most %.3f m before the first drive; %.1f m/s after 1.3 s" % [highest, skater.board.speed()])
	check(contact and highest < 0.03, "the first push drives straight from the standing foot (lifted %.3f m)" % highest)
	check(skater.board.speed() > 1.5, "and gets the board going (%.1f m/s)" % skater.board.speed())
	# Rolling: both feet on the board.
	skater.scripted_input = func(_tick: int) -> void:
		skater.pad.hold(Action.PUSH, false)
	for _i in 70:
		await tree.physics_frame
	foot = _on_deck("RightFoot")
	check(skater.board.speed() > 0.8 and foot.y > 0.06 and absf(foot.x) < 0.1 and foot.z < -0.15,
		"rolling, the back foot is up on the tail (%s at %.1f m/s)" % [foot, skater.board.speed()])
	# Braked to a stop, it goes down again; held crouched for a pop, it comes back up.
	skater.scripted_input = func(_tick: int) -> void:
		skater.pad.hold(Action.BRAKE, true)
	for _i in 200:
		await tree.physics_frame
	foot = _on_deck("RightFoot")
	check(skater.board.speed() < 0.3 and absf(foot.y - GROUND_ANKLE) < 0.015, "stopped, the foot goes down again (%.3f m above the ground at %.2f m/s)" % [foot.y - GROUND_ANKLE, skater.board.speed()])
	skater.scripted_input = func(_tick: int) -> void:
		skater.pad.hold(Action.BRAKE, false)
		skater.pad.hold(Action.POP, true)
	for _i in 40:
		await tree.physics_frame
	foot = _on_deck("RightFoot")
	facing = (skater.deck_effective().basis.inverse() * _bone("Hips").basis.z).z
	print("    crouched for a pop on the spot: back foot %.3f m above the deck, %+.2f m along it; hips face the nose %.2f" % [foot.y - RiderAnimator.ANKLE_HEIGHT, foot.z, facing])
	check(foot.y > 0.06 and absf(foot.x) < 0.1 and foot.z < -0.15, "crouching for a pop brings the foot back onto the tail (%s)" % foot)
	check(facing < 0.6, "and the body side-on again (%.2f)" % facing)
	_teardown()


## How far the arms' blocks reach into the torso's (m), the worst of both arms
## against the chest, spine and hips blocks as the figure is drawn.
func _arms_in_torso() -> Array:
	var worst := 0.0
	var where := ""
	var torso := []
	for block in BlockFigure.BLOCKS:
		if block[0] in ["UpperChest", "Spine", "Hips"]:
			torso.append([block[0], _bone(block[0]).affine_inverse(), block[2], (block[1] as Vector3) * 0.5])
	for side in ["Left", "Right"]:
		var hand := _bone(side + "Hand")
		var joints := [_bone(side + "UpperArm").origin, _bone(side + "LowerArm").origin, hand.origin, hand.origin + hand.basis.y * 0.11]
		for segment in 3:
			for step in 9:
				var point: Vector3 = (joints[segment] as Vector3).lerp(joints[segment + 1], step / 8.0)
				for box in torso:
					var local: Vector3 = (box[1] as Transform3D) * point - (box[2] as Vector3)
					var half: Vector3 = box[3]
					# Half an arm's width (0.05 m) all round its centre line.
					var into := minf(minf(half.x + 0.05 - absf(local.x), half.y + 0.05 - absf(local.y)), half.z + 0.05 - absf(local.z))
					if into > worst:
						worst = into
						where = "%s %s in the %s" % [side, ["upper arm", "forearm", "hand"][segment], box[0]]
	return [worst, where]


## The arms lie beside the body and move around it; they never pass through it.
func test_arms_stay_outside_the_body() -> void:
	await _setup(Vector3.ZERO)
	# Standing, pushing, carving each way, an ollie, a manual, braking to a stop.
	skater.scripted_input = func(tick: int) -> void:
		var pad := skater.pad
		pad.hold(Action.PUSH, tick >= 60 and tick < 200)
		pad.steer = 1.0 if tick >= 210 and tick < 320 else (-1.0 if tick >= 320 and tick < 430 else 0.0)
		pad.hold(Action.POP, tick >= 440 and tick < 470)
		pad.hold(Action.BOARD, tick >= 570 and tick < 690)
		pad.hold(Action.BRAKE, tick >= 700 and tick < 860)
	for _i in 6:
		await tree.physics_frame
	var worst := 0.0
	var where := ""
	for i in 900:
		await tree.physics_frame
		var found := _arms_in_torso()
		if found[0] > worst:
			worst = found[0]
			where = "%s at tick %d" % [found[1], i]
	print("    arms against the body, through standing, pushing, carving, an ollie, a manual and a stop: at most %.3f m into it (%s)" % [worst, where])
	check(worst < 0.02, "the arms never go into the torso (%.3f m: %s)" % [worst, where])
	# (The measure does see the torso: the chest's own bone is deep inside it.)
	var chest := BlockFigure.BLOCKS.filter(func(block: Array) -> bool: return block[0] == "UpperChest")
	check(chest.size() == 1 and (chest[0][1] as Vector3).x < 2.0 * absf(skater.animator.solver.shoulder_joint(Transform3D.IDENTITY, Basis.IDENTITY, true).x),
		"the shoulders sit outside the chest block")
	_teardown()


## The step off the board is a movement with weight in it, not a pose change:
## the weight leaves the foot before it lifts, the hips turn with the leg, the
## foot is carried over the edge and set down softly, and the knee gives as
## the weight arrives.
func test_stepping_off_the_board_has_weight() -> void:
	await _setup(Vector3.ZERO)
	# (A few frames for the body to be posed at all, well before it steps.)
	for _i in 4:
		await tree.physics_frame
	var toes := skater.animator.facing().x
	var start := _on_deck("RightFoot")
	var hips_start := _on_deck("Hips").x * toes
	var before := start
	var speed_before := Vector3.ZERO
	var lifted := -1
	var landed := -1
	var highest := 0.0
	var jolt := 0.0
	var landing_speed := 0.0
	var away := 0.0
	var facing_at_lift := 0.0
	var facing_at_landing := 0.0
	var hips_at_landing := 0.0
	var dip := 0.0
	for i in 110:
		await tree.physics_frame
		var foot := _on_deck("RightFoot")
		var hips := _on_deck("Hips")
		var facing := (skater.deck_effective().basis.inverse() * _bone("Hips").basis.z).z
		var speed := (foot - before) * 60.0
		if i > 1:
			jolt = maxf(jolt, (speed - speed_before).length() * 60.0)
		if lifted < 0:
			away = maxf(away, hips_start - hips.x * toes)
			if foot.distance_to(start) > 0.005:
				lifted = i
				facing_at_lift = facing
		elif landed < 0:
			highest = maxf(highest, foot.y - start.y)
			if absf(foot.y - GROUND_ANKLE) < 0.004 and absf(foot.x) > 0.17:
				landed = i
				landing_speed = speed.length()
				facing_at_landing = facing
				hips_at_landing = hips.y
		else:
			dip = maxf(dip, hips_at_landing - hips.y)
		before = foot
		speed_before = speed
	var hips_end := _on_deck("Hips").x * toes
	print("    stepping off: the weight goes %.3f m the other way first; the foot lifts at tick %d and lands at %d (%.2f s), carried %.2f m up, arriving at %.2f m/s, its speed never changing faster than %.0f m/s2; hips face the nose %.2f as it lifts and %.2f as it lands; the hips end %.2f m toward that foot and dip %.3f m as the weight comes onto it" % [
		away, lifted, landed, (landed - lifted) / 60.0, highest, landing_speed, jolt, facing_at_lift, facing_at_landing, hips_end - hips_start, dip])
	check(lifted > 0 and landed > lifted, "the foot steps down")
	check(away > 0.008, "the weight moves off the foot before it lifts (%.3f m the other way)" % away)
	check((landed - lifted) / 60.0 > 0.25 and (landed - lifted) / 60.0 < 0.7, "the step takes a human moment (%.2f s)" % ((landed - lifted) / 60.0))
	check(highest > 0.04, "the foot is carried up over the edge of the deck (%.2f m)" % highest)
	check(landing_speed < 0.6, "and set down, not dropped (%.2f m/s)" % landing_speed)
	check(jolt < 40.0, "its speed never jumps (%.0f m/s2)" % jolt)
	check(facing_at_lift < 0.6 and facing_at_landing > 0.8, "the hips turn with the leg, not before it (%.2f, then %.2f)" % [facing_at_lift, facing_at_landing])
	check(hips_end - hips_start > 0.1, "the weight ends over the foot on the ground (%.2f m across)" % (hips_end - hips_start))
	check(dip > 0.008, "and the knee gives as it arrives (%.3f m)" % dip)
	_teardown()


## How far the further-out hand is from hanging straight under its shoulder (m,
## level distance in the world), and how far below it the higher hand is.
func _hang() -> Vector2:
	var out := 0.0
	var below := 9.0
	for side in ["Left", "Right"]:
		var arm := _bone(side + "Hand").origin - _bone(side + "UpperArm").origin
		out = maxf(out, Vector2(arm.x, arm.z).length())
		below = minf(below, -arm.y)
	return Vector2(out, below)


func test_arms_hang_when_the_board_is_standing_still() -> void:
	await _setup(Vector3.ZERO)
	for _i in 60:
		await tree.physics_frame
	var rest := _hang()
	print("    standing still: hands at least %.2f m below the shoulders, at most %.2f m out from under them" % [rest.y, rest.x])
	check(rest.y > 0.42, "the arms hang (hands %.2f m below the shoulders)" % rest.y)
	check(rest.x < 0.16, "at the sides, not held out (%.2f m from under the shoulders)" % rest.x)
	# Steering on the spot, then crouching on the spot: nothing for the arms to do.
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.steer = 1.0 if tick % 120 < 60 else -1.0
	var steered := 0.0
	for _i in 150:
		await tree.physics_frame
		steered = maxf(steered, _hang().x)
	skater.scripted_input = func(_tick: int) -> void:
		skater.pad.steer = 0.0
		skater.pad.hold(Action.POP, true)
	var crouched := 0.0
	for _i in 60:
		await tree.physics_frame
		crouched = maxf(crouched, _hang().x)
	print("    steered hard each way on the spot, the hands get at most %.2f m out from under the shoulders; crouched on the spot, %.2f m" % [steered, crouched])
	check(skater.board.speed() < 0.3, "still standing still (%.2f m/s)" % skater.board.speed())
	check(steered < 0.16, "steering on the spot does not bring the arms out (%.2f m)" % steered)
	check(crouched < 0.25, "nor does crouching (%.2f m)" % crouched)
	_teardown()


## A carve at `speed`: how far the hands move from where they were rolling
## straight, tick by tick from the turn-in; held one way for 2.5 s, then the other.
func _carve_arms(speed: float) -> Dictionary:
	await _setup(Vector3(0.0, 0.0, speed))
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.steer = 0.0 if tick < 60 else (1.0 if tick < 210 else -1.0)
	for _i in 58:
		await tree.physics_frame
	var rest := _hands()
	var moved: Array[float] = []
	var spans: Array[float] = []
	for _i in 300:
		await tree.physics_frame
		var hands := _hands()
		moved.append(_moved(hands, rest))
		spans.append(hands.span - rest.span)
	_teardown()
	var turn_in := 0.0
	var change := 0.0
	for i in range(0, 50):
		turn_in = maxf(turn_in, moved[i])
	for i in range(150, 200):
		change = maxf(change, moved[i])
	var held := 0.0
	var held_span := 0.0
	for i in range(120, 148):
		held = maxf(held, moved[i])
		held_span = maxf(held_span, spans[i])
	return {"turn_in": turn_in, "held": held, "held_span": held_span, "change": change}


func test_arms_move_into_a_carve_and_settle_while_it_is_held() -> void:
	var fast := await _carve_arms(5.0)
	var slow := await _carve_arms(2.0)
	print("    carving at 5 m/s: a hand moves %.2f m at the turn-in, is %.2f m from rest once the carve is held (hands %+.2f m wider), and moves %.2f m at the change of edge; at 2 m/s %.2f m at the turn-in" % [
		fast.turn_in, fast.held, fast.held_span, fast.change, slow.turn_in])
	check(fast.turn_in > 0.12, "the arms move as the carve starts (%.2f m)" % fast.turn_in)
	check(fast.held < fast.turn_in * 0.8, "and come back down while it is held (%.2f m from rest against %.2f m)" % [fast.held, fast.turn_in])
	check(fast.held_span < 0.2, "not held out wide (hands %+.2f m wider than rolling straight)" % fast.held_span)
	check(fast.change > fast.held + 0.05, "they move again at the change of edge (%.2f m)" % fast.change)
	check(slow.turn_in < fast.turn_in * 0.75, "and less when going slowly (%.2f m against %.2f m)" % [slow.turn_in, fast.turn_in])


## One pop at 5 m/s: how the hands rise and come back, from their height
## rolling along. `crouch` is how many ticks the pop is held first.
func _pop_arms(crouch: int, flip: bool, again := false) -> Dictionary:
	await _setup(Vector3(0.0, 0.0, 5.0))
	var start := 320 if again else 70
	skater.scripted_input = func(tick: int) -> void:
		var first := tick >= 70 and tick < 70 + crouch
		var second := again and tick >= 320 and tick < 320 + crouch
		skater.pad.hold(Action.POP, first or second)
		skater.pad.hold(Action.KICKFLIP, flip and tick >= 70 + crouch - 6 and tick < 70 + crouch - 2)
	for _i in 62:
		await tree.physics_frame
	var rest := _hands()
	for _i in start - 70:
		await tree.physics_frame
	var out := {"lift": 0.0, "front_at": -1, "back_at": -1, "span": 0.0, "above": -9.0, "trick": ""}
	var front_top := -9.0
	var back_top := -9.0
	var landed := -1
	for i in 240:
		await tree.physics_frame
		var hands := _hands()
		if skater.director.airborne:
			out.trick = skater.director.trick_key
			if hands.front > front_top:
				front_top = hands.front
				out.front_at = i
			if hands.back > back_top:
				back_top = hands.back
				out.back_at = i
			out.span = maxf(out.span, hands.span - rest.span)
			out.above = maxf(out.above, maxf(hands.left.y, hands.right.y))
		if landed < 0 and i > crouch and skater.rider.just_landed:
			landed = i
		if landed >= 0 and i == landed + 60:
			out.after = _moved(hands, rest)
	out.lift = maxf(front_top - rest.front, back_top - rest.back)
	out.landed = landed
	_teardown()
	return out


func test_a_pop_swings_the_arms_up_as_far_as_it_is_big() -> void:
	var deep := await _pop_arms(40, false)
	var tap := await _pop_arms(4, false)
	var flip := await _pop_arms(40, true)
	var second := await _pop_arms(40, false, true)
	print("    a deep ollie lifts a hand %.2f m (front at tick %d, back at %d; hands %+.2f m wider, %+.2f m from shoulder height), a quick tap %.2f m, a %s %.2f m; a second after landing a hand is %.2f m from rest; the same ollie again %.3f m" % [
		deep.lift, deep.front_at, deep.back_at, deep.span, deep.above, tap.lift, flip.trick, flip.lift, deep.after, second.lift])
	check(deep.lift > 0.2, "the arms swing up with a deep ollie (%.2f m)" % deep.lift)
	check(tap.lift < deep.lift * 0.75, "much less with a quick tap (%.2f m against %.2f m)" % [tap.lift, deep.lift])
	check(flip.trick.contains("flip") and flip.lift < deep.lift * 0.9, "and lower through a flip trick (%s: %.2f m)" % [flip.trick, flip.lift])
	check(absi(deep.front_at - deep.back_at) >= 2, "the two arms are not thrown together (tops at ticks %d and %d)" % [deep.front_at, deep.back_at])
	check(deep.above < 0.1, "the hands stay about at or below the shoulders (%+.2f m)" % deep.above)
	check(deep.span < 0.6, "and they are not held out in a T (hands %+.2f m wider)" % deep.span)
	check(deep.landed > 0 and deep.after < 0.1, "a second after landing they are back at the sides (%.2f m from rest)" % deep.after)
	check(absf(second.lift - deep.lift) > 0.004, "the same ollie twice does not throw the same arms (%.3f m against %.3f m)" % [second.lift, deep.lift])


## Holding a manual at `speed`: how wide the hands are over rolling along, how
## they move, and how the two go against each other.
func _manual_arms(speed: float) -> Dictionary:
	await _setup(Vector3(0.0, 0.0, speed))
	skater.scripted_input = func(tick: int) -> void:
		skater.pad.hold(Action.BOARD, tick >= 40)
	for _i in 38:
		await tree.physics_frame
	var rest := _hands()
	var fronts: Array[float] = []
	var backs: Array[float] = []
	var out := {"span": 0.0, "fastest": 0.0}
	var before := _hands()
	for i in 170:
		await tree.physics_frame
		var hands := _hands()
		if i >= 50:
			out.span += (hands.span - rest.span) / 120.0
			fronts.append(hands.front)
			backs.append(hands.back)
			out.fastest = maxf(out.fastest, maxf((hands.left - before.left).length(), (hands.right - before.right).length()) * 60.0)
		before = hands
	out.time = skater.rider.manual_time
	out.seesaw = _correlation(fronts, backs)
	out.travel = maxf(fronts.max() - fronts.min(), backs.max() - backs.min())
	_teardown()
	return out


func test_arms_balance_a_manual_and_more_so_at_speed() -> void:
	var fast := await _manual_arms(6.0)
	var slow := await _manual_arms(2.5)
	print("    manual at 6 m/s: hands %+.2f m wider than rolling, each moving up to %.2f m, one against the other %.2f, never faster than %.2f m/s; at 2.5 m/s %+.2f m wider" % [
		fast.span, fast.travel, fast.seesaw, fast.fastest, slow.span])
	check(fast.time > 1.5 and slow.time > 1.5, "holding the manual (%.1f s, %.1f s)" % [fast.time, slow.time])
	check(fast.span > 0.2, "the arms come out to balance it (hands %+.2f m wider)" % fast.span)
	check(slow.span < fast.span - 0.05, "less when going slowly (%+.2f m against %+.2f m)" % [slow.span, fast.span])
	check(fast.travel > 0.04, "and they keep working (%.2f m)" % fast.travel)
	check(fast.seesaw < -0.2, "one up as the other goes down (%.2f)" % fast.seesaw)
	check(fast.fastest < 1.2, "without flailing (%.2f m/s at the fastest)" % fast.fastest)


static func _correlation(a: Array[float], b: Array[float]) -> float:
	var mean_a := 0.0
	var mean_b := 0.0
	for i in a.size():
		mean_a += a[i] / a.size()
		mean_b += b[i] / b.size()
	var both := 0.0
	var spread_a := 0.0
	var spread_b := 0.0
	for i in a.size():
		both += (a[i] - mean_a) * (b[i] - mean_b)
		spread_a += (a[i] - mean_a) * (a[i] - mean_a)
		spread_b += (b[i] - mean_b) * (b[i] - mean_b)
	return both / maxf(sqrt(spread_a * spread_b), 1e-9)
