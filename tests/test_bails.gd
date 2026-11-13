extends OllieTest

var park: TestPark
var skater: SkaterController
var bails: Array[String] = []


func test_crosswise_landing_bails_ragdolls_and_respawns() -> void:
	park = TestPark.new()
	tree.root.add_child(park)
	skater = SkaterController.new()
	tree.root.add_child(skater)
	skater.respawn(Transform3D(Basis.IDENTITY, Vector3(25.0, TestPark.FLOOR_HEIGHT, -40.0)))
	skater.board.set_velocity(Vector3(0.0, 0.0, 6.0))
	skater.director.bailed.connect(func(r: String) -> void: bails.append(r))
	skater.scripted_input = func(tick: int) -> void:
		var pad := skater.pad
		pad.hold(VirtualPad.Action.POP, tick >= 10 and tick < 40)
		pad.steer = 0.3 if tick >= 46 and tick < 120 else 0.0
	var saw_ragdoll := false
	var lowest_head := 99.0
	var respawned_at := -1
	for i in 420:
		await tree.physics_frame
		if skater.animator.is_ragdoll():
			saw_ragdoll = true
			var head := skater.animator.skeleton.global_transform * skater.animator.skeleton.get_bone_global_pose(skater.animator.skeleton.find_bone("Head")).origin
			lowest_head = minf(lowest_head, head.y)
		elif saw_ragdoll and respawned_at < 0:
			respawned_at = i
	print("    bails %s, ragdoll %s, lowest head %.2f m above floor, respawned after tick %d, state %s" % [bails, saw_ragdoll, lowest_head - TestPark.FLOOR_HEIGHT, respawned_at, skater.rider.state_name()])
	check(bails.size() == 1, "bailed once (%s)" % [bails])
	check(saw_ragdoll, "the body went to the ragdoll")
	check(lowest_head - TestPark.FLOOR_HEIGHT < 0.5, "the body fell to the ground")
	check(lowest_head - TestPark.FLOOR_HEIGHT > -0.05, "and did not fall through it")
	check(respawned_at > 0, "respawned")
	check(skater.rider.state == RidingModel.State.GROUND, "riding again (%s)" % skater.rider.state_name())
	skater.queue_free()
	park.queue_free()
