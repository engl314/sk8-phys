extends OllieTest

const DT := 1.0 / 60.0

var rig: RiderAnimator
## A made-up board: it just goes where its velocity takes it.
var at := Vector3.ZERO
var moving := Vector3.ZERO


func _start(speed: float) -> void:
	rig = RiderAnimator.new()
	tree.root.add_child(rig)
	rig.feel = RiderFeel.new()
	at = Vector3(0.0, rig.inputs.deck_ride_height, 0.0)
	moving = Vector3(0.0, 0.0, speed)


func _stop() -> void:
	rig.queue_free()


## One tick: tell the rig where the board is, and step it.
func _tick() -> void:
	var game := rig.inputs
	at += moving * DT
	game.deck = Transform3D(Basis.IDENTITY, at)
	game.frame = game.deck
	game.velocity = moving
	game.forward_speed = moving.z
	rig.step(DT)
	game.just_landed = false


## A bone's place over the board (deck space).
func _over(bone: String) -> Vector3:
	var skeleton := rig.skeleton
	return (skeleton.global_transform * skeleton.get_bone_global_pose(skeleton.find_bone(bone))).origin - at


func _sound() -> bool:
	var skeleton := rig.skeleton
	for bone in skeleton.get_bone_count():
		var t := skeleton.get_bone_global_pose(bone)
		if not (t.origin.is_finite() and t.basis.x.is_finite() and t.basis.y.is_finite() and t.basis.z.is_finite()):
			return false
	return true


func test_the_rig_rides_pushes_pops_and_stands_from_inputs_alone() -> void:
	var on_deck := RiderAnimator.DECK_TOP + RiderAnimator.ANKLE_HEIGHT
	# Rolling along: both feet on the board, hips over it.
	_start(5.0)
	for _i in 90:
		_tick()
	var front := _over("LeftFoot")
	var back := _over("RightFoot")
	var hips := _over("Hips")
	var hands := maxf(_over("LeftHand").y, _over("RightHand").y)
	print("    rolling at 5 m/s from inputs alone: feet %.3f and %.3f m above the deck, hips %.2f m" % [front.y, back.y, hips.y])
	check(_sound(), "every bone is somewhere sensible")
	check(absf(front.y - on_deck) < 0.02 and absf(back.y - on_deck) < 0.03, "both feet are on the board (%.3f, %.3f m)" % [front.y, back.y])
	check(absf(front.x) < 0.1 and absf(back.x) < 0.1 and front.z > 0.05 and back.z < -0.1, "one ahead of the other along it")
	check(hips.y > 0.7 and hips.y < 0.95, "with the hips over them (%.2f m up)" % hips.y)

	# A push: the back foot goes down to the ground beside the board and comes back.
	var game := rig.inputs
	var ground := RiderAnimator.ANKLE_HEIGHT - game.deck_ride_height
	var lowest := 9.0
	var out := 0.0
	for phase: Array in [[RiderInputs.Push.REACH, 10], [RiderInputs.Push.DRIVE, 16], [RiderInputs.Push.SWING, 14], [RiderInputs.Push.NONE, 40]]:
		game.push_phase = phase[0]
		for i in phase[1]:
			game.push_progress = float(i) / phase[1] if phase[0] != RiderInputs.Push.NONE else 0.0
			_tick()
			var foot := _over("RightFoot")
			if foot.y < lowest:
				lowest = foot.y
				out = absf(foot.x)
	back = _over("RightFoot")
	print("    a push: the back foot gets down to %.3f m from the ground, %.2f m out from the middle of the board, and ends %.3f m above the deck" % [lowest - ground, out, back.y])
	check(absf(lowest - ground) < 0.02 and out > game.deck_width * 0.5, "the pushing foot reaches the ground beside the board (%.3f m off it)" % (lowest - ground))
	check(absf(back.y - on_deck) < 0.03 and back.z < -0.1, "and comes back onto the tail")

	# A pop: crouch, leave the ground, come down.
	game.crouch = 1.0
	game.crouch_held = true
	for _i in 30:
		_tick()
	var crouched := _over("Hips").y
	game.crouch = 0.0
	game.crouch_held = false
	rig.pop(1.0)
	game.state = RiderInputs.State.AIR
	game.airborne = true
	game.trick_active = true
	moving.y = 3.0
	var highest_hand := -9.0
	var air := 0.0
	while moving.y > -3.0:
		air += DT
		game.air_time = air
		game.time_to_land = (moving.y + 3.0) / game.gravity
		moving.y -= game.gravity * DT
		_tick()
		highest_hand = maxf(highest_hand, maxf(_over("LeftHand").y, _over("RightHand").y))
	moving.y = 0.0
	at.y = game.deck_ride_height
	game.state = RiderInputs.State.GROUND
	game.airborne = false
	game.trick_active = false
	game.just_landed = true
	game.time_to_land = INF
	var dipped := 9.0
	for _i in 90:
		_tick()
		dipped = minf(dipped, _over("Hips").y)
	var settled := _over("Hips").y
	print("    a pop: hips %.2f m crouched; in the air the hands get %.2f m higher than rolling; landing takes the hips to %.2f m before they settle at %.2f m" % [
		crouched, highest_hand - hands, dipped, settled])
	check(crouched < hips.y - 0.15, "the rider crouches (%.2f m against %.2f m)" % [crouched, hips.y])
	check(highest_hand > hands + 0.1, "the arms come up with the pop (%.2f m)" % (highest_hand - hands))
	check(dipped < settled - 0.03, "and the legs give on landing (%.2f m, then %.2f m)" % [dipped, settled])
	check(_sound(), "every bone is still somewhere sensible")
	_stop()

	# Standing still: the back foot goes down.
	_start(0.0)
	for _i in 90:
		_tick()
	back = _over("RightFoot")
	check(absf(back.y - ground) < 0.02 and absf(back.x) > rig.inputs.deck_width * 0.5, "standing still, the back foot is on the ground (%.3f m off it)" % (back.y - ground))
	_stop()


## Every class the project defines outside rig/ (by its `class_name`).
func _game_classes(folder: String, found: Dictionary) -> void:
	for sub in DirAccess.get_directories_at(folder):
		if not sub.begins_with(".") and not (folder == "res://" and sub in ["rig", "tests"]):
			_game_classes(folder.path_join(sub), found)
	for file in DirAccess.get_files_at(folder):
		if file.ends_with(".gd"):
			for line in FileAccess.get_file_as_string(folder.path_join(file)).split("\n"):
				if line.begins_with("class_name "):
					found[line.get_slice(" ", 1).strip_edges()] = folder.path_join(file)


func test_the_rig_names_nothing_from_the_game() -> void:
	var classes := {}
	_game_classes("res://", classes)
	var named: Array[String] = []
	var word := RegEx.new()
	for file in DirAccess.get_files_at("res://rig"):
		if not file.ends_with(".gd"):
			continue
		for line in FileAccess.get_file_as_string("res://rig".path_join(file)).split("\n"):
			# Code only: what a comment mentions ties nothing together.
			var code := line.get_slice("#", 0)
			for name: String in classes:
				word.compile("\\b%s\\b" % name)
				if word.search(code) and not ("%s in %s" % [name, file]) in named:
					named.append("%s in %s" % [name, file])
	print("    rig/ against the %d classes defined elsewhere in the project: names %d of them" % [classes.size(), named.size()])
	check(classes.size() > 10, "the rest of the project's classes were found (%d)" % classes.size())
	check(named.is_empty(), "nothing in rig/ names a class from the game or the simulation (%s)" % ", ".join(named))
