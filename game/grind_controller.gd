class_name GrindController
extends RefCounted

signal grind_started(name: String)
signal grind_ended(name: String, seconds: float)

const RAIL_SPRING_STRENGTH := 800.0
## How hard each grind family drags along the rail.
const RAIL_FRICTION := {
	GrindPhysics.Family.FIFTY_FIFTY: 0.1, GrindPhysics.Family.FIVE_O: 0.15, GrindPhysics.Family.BOARDSLIDE: 0.2,
	GrindPhysics.Family.END_SLIDE: 0.24, GrindPhysics.Family.STEEP_END_SLIDE: 0.26, GrindPhysics.Family.DARKSLIDE: 0.3,
}
## Lean-off delay, then the lean grows; past 28 degrees the grind ends.
const LEAN_DELAY := 2.4
const LEAN_GROWTH := 1.1
const LEAN_LIMIT := deg_to_rad(28.0)

var skater: SkaterController
var rails: Array = []

var active := false
var family := 0
var rail := -1
var direction := Vector3.ZERO
var normal := Vector3.UP
var front := false
var time := 0.0
var lean := 0.0
var lean_sign := 1.0
var name := ""
var lost_ticks := 0
var reference_local := Vector3.ZERO
var cooldown := 0.0


func _init(owner: SkaterController) -> void:
	skater = owner


## Collect GrindRail nodes from the scene tree.
func gather_rails() -> void:
	rails.clear()
	for node in skater.get_tree().get_nodes_in_group("grind_rails"):
		var r := GrindPhysics.Rail.new()
		r.start = node.global_transform * node.start if node.is_inside_tree() else node.start
		r.end = node.global_transform * node.end if node.is_inside_tree() else node.end
		r.name = node.name
		rails.append(r)


func reset() -> void:
	active = false
	cooldown = 0.0


## Before the riding update: look for a grind while airborne, run the one we're on.
func pre_physics(dt: float) -> void:
	cooldown = maxf(cooldown - dt, 0.0)
	if rails.is_empty():
		gather_rails()
	var director := skater.director
	if not active:
		if director.airborne and cooldown <= 0.0 and director.air_time > 0.08 and director.bail_timer < 0.0:
			var deck := skater.board.deck()
			var c := GrindPhysics.find(deck.transform(), rails, deck.linear_velocity, true)
			if c and deck.linear_velocity.y < 1.0:
				_enter(c)
		return
	_hold(dt)


## Landing on a rail re-enters the grind instead of being judged as a landing.
func try_enter() -> bool:
	if active:
		return true
	var deck := skater.board.deck()
	var c := GrindPhysics.find(deck.transform(), rails, deck.linear_velocity, true)
	if c == null:
		return false
	_enter(c)
	return active


func _enter(c: GrindPhysics.Candidate) -> void:
	var director := skater.director
	if director.trick_key != "" and director.trick_progress < 0.86:
		return
	active = true
	family = c.family
	rail = c.rail
	var deck := skater.board.deck()
	direction = c.direction if c.direction.dot(deck.linear_velocity) >= 0.0 else -c.direction
	normal = GrindPhysics.rail_normal(direction)
	front = c.front
	time = 0.0
	lean = 0.0
	lost_ticks = 0
	lean_sign = 1.0 if randf() < 0.5 else -1.0
	reference_local = _reference_local()
	var entry := GrindPhysics.landing_on_rail_velocity(family, direction, normal, deck.linear_velocity)
	for body in skater.board.bodies:
		body.linear_velocity = entry
	name = _name(c)
	director.enter_grind()
	skater.rider.enter_grind()
	grind_started.emit(name)


## Body-local point that should sit on the rail for this family.
func _reference_local() -> Vector3:
	var t := GrindPhysics.HALF_WHEELBASE
	match family:
		GrindPhysics.Family.FIFTY_FIFTY:
			return Vector3(0.0, -0.06, 0.0)
		GrindPhysics.Family.FIVE_O:
			return Vector3(0.0, -0.06, t if front else -t)
		GrindPhysics.Family.END_SLIDE, GrindPhysics.Family.STEEP_END_SLIDE:
			return Vector3(0.0, -0.005, (t + 0.12) * (1.0 if front else -1.0))
		GrindPhysics.Family.DARKSLIDE:
			return Vector3(0.0, 0.009, 0.0)
	return Vector3(0.0, -0.009, 0.0)


func _name(c: GrindPhysics.Candidate) -> String:
	var face := skater.rider_frame.basis * skater.animator.facing()
	var to_rail := c.point - skater.board.deck().position
	to_rail.y = 0.0
	var side := "FS" if to_rail.dot(face) > 0.0 else "BS"
	var base: String = GrindPhysics.FAMILY_NAMES[family]
	match family:
		GrindPhysics.Family.FIVE_O:
			base = "Nosegrind" if front else "5-0"
		GrindPhysics.Family.END_SLIDE:
			base = "Noseslide" if front else "Tailslide"
		GrindPhysics.Family.DARKSLIDE:
			return "Darkslide"
	return side + " " + base


func _hold(dt: float) -> void:
	time += dt
	var board := skater.board
	var deck := board.deck()
	# A one-truck grind becomes a 50-50 once both trucks are on.
	if family == GrindPhysics.Family.FIVE_O:
		var c := GrindPhysics.find(deck.transform(), rails, deck.linear_velocity, true)
		if c and c.family == GrindPhysics.Family.FIFTY_FIFTY and c.rail == rail and GrindPhysics.moving_along_rail(c.direction, deck.linear_velocity, 24.0):
			family = c.family
			reference_local = _reference_local()
			name = name.get_slice(" ", 0) + " 50-50"
			grind_started.emit(name)
	var r: GrindPhysics.Rail = rails[rail]
	var reference := deck.transform() * reference_local
	var rail_point := Geometry3D.get_closest_point_to_segment(reference, r.start, r.end)
	var along := (rail_point - r.start).dot(GrindPhysics.rail_direction(r))
	var length := r.start.distance_to(r.end)
	if along <= 0.01 or along >= length - 0.01 or reference.distance_to(rail_point) > 0.25:
		lost_ticks += 1
	else:
		lost_ticks = 0
	var speed := deck.linear_velocity.dot(direction)
	if lost_ticks > 2:
		_exit(0.0, 0.0)
		return
	if absf(speed) < 0.35 and time > 0.25:
		_exit(0.0, 0.0)
		return
	# Lean-off: after the delay the lean grows; A/D hold it back.
	var stick := skater.pad.steer
	if time > LEAN_DELAY:
		lean += lean_sign * LEAN_GROWTH * (time - LEAN_DELAY) * dt
	lean = move_toward(lean, lean - stick * 0.6, dt * 0.5)
	if absf(lean) > LEAN_LIMIT:
		_exit(signf(lean) * 0.6, 0.8)
		return
	# Pin the contact point onto the rail line; the rail's collision holds it up.
	var across := normal.cross(direction).normalized()
	var pin := GrindPhysics.rail_spring_force(rail_point, reference, across, deck.linear_velocity, RAIL_SPRING_STRENGTH)
	board.queue_force(pin, reference_local)
	var load := 1.0 / deck.inverse_mass * skater.tuning.gravity * maxf(normal.y, 0.0) * 1.9
	board.queue_force(GrindPhysics.rail_friction(deck.linear_velocity, normal, load, RAIL_FRICTION.get(family, 0.15)), Vector3.ZERO)
	# Steer the deck toward its family's frame, leaning with the balance.
	var to_point := deck.position - rail_point
	var target := GrindPhysics.grind_deck_basis(family, deck.basis, direction, normal, to_point, 0.0, 0.0)
	target = Basis(direction, lean * 0.6) * target
	board.guide_dynamics = skater.director.air_guide_dynamics()
	board.set_guide_transform(Transform3D(target, deck.position))


## Pop out with `key` (an ollie, or a flip trick): the grind launch, then the
## director takes over the air. `strength` 0..1 comes from the crouch. A/D pick
## the side to hop off.
func pop_out(key: String, strength: float) -> void:
	var vertical := sqrt(2.0 * skater.tuning.gravity * lerpf(0.18, 0.36, strength))
	_exit(skater.pad.steer * 0.5, vertical, key)


func _exit(balance: float, vertical: float, key := "") -> void:
	if not active:
		return
	active = false
	cooldown = 0.3
	var deck := skater.board.deck()
	var r: GrindPhysics.Rail = rails[rail]
	if vertical > 0.0:
		var velocity := GrindPhysics.pop_out_velocity(family, r, Geometry3D.get_closest_point_to_segment(deck.position, r.start, r.end),
			deck.position, deck.linear_velocity, balance, vertical)
		for body in skater.board.bodies:
			body.linear_velocity = velocity
	skater.rider.force_air()
	skater.director.leave_grind(key)
	grind_ended.emit(name, time)
