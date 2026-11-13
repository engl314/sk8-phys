class_name GrindPhysics

## Physical grind families.
enum Family { FIFTY_FIFTY, BOARDSLIDE, END_SLIDE, FIVE_O, STEEP_END_SLIDE, DARKSLIDE }
const FAMILY_NAMES := ["50-50", "Boardslide", "End slide", "5-0", "Steep end slide", "Darkslide"]

## Truck half-track and deck-centre-to-truck distance.
const HALF_TRACK_WIDTH := 0.095
const HALF_WHEELBASE := 0.243
## Deck slide probe: above and below the deck centre.
const SLIDE_PROBE_ABOVE := 0.03
const SLIDE_PROBE_BELOW := 0.13


class Rail:
	var start := Vector3.ZERO
	var end := Vector3.ZERO
	var name := ""


class Hit:
	var position := Vector3.ZERO
	var rail := -1


class Candidate:
	var family := 0
	var rail := -1
	var direction := Vector3.ZERO
	var point := Vector3.ZERO
	## Front truck / nose for single-truck and tip grinds.
	var front := false


## Where the segment crosses the triangle.
static func intersect_segment_triangle(start: Vector3, end: Vector3, a: Vector3, b: Vector3, c: Vector3) -> Variant:
	var ac := c - a
	var ab := b - a
	var direction := end - start
	var normal := ab.cross(ac)
	var denominator := -direction.dot(normal)
	if denominator == 0.0:
		return null
	var from := start - a
	var inverse := 1.0 / denominator
	var t := inverse * from.dot(normal)
	if t < 0.0 or t > 1.0:
		return null
	var side := from.cross(direction)
	var u := inverse * ac.dot(side)
	var v := (1.0 / -denominator) * ab.dot(side)
	if u + v > 1.0 or u < 0.0 or v < 0.0:
		return null
	return start + direction * t


## Closest rail crossing of the quad a-b-c-d (two triangles), measured from `reference`.
static func _closest_crossing(a: Vector3, b: Vector3, c: Vector3, d: Vector3, reference: Vector3, rails: Array) -> Hit:
	var best: Hit = null
	var distance := 1e6
	for i in rails.size():
		var rail: Rail = rails[i]
		var position: Variant = intersect_segment_triangle(rail.start, rail.end, a, b, c)
		if position == null:
			position = intersect_segment_triangle(rail.start, rail.end, a, d, c)
		if position == null:
			continue
		var squared := (position as Vector3).distance_squared_to(reference)
		if squared < distance:
			distance = squared
			best = Hit.new()
			best.position = position
			best.rail = i
	return best


## A 0.2 m deep box under each truck. [front, back]
static func truck_probes(board: Transform3D, rails: Array) -> Array:
	var right := board.basis.x
	var up := board.basis.y
	var forward := board.basis.z
	var centre := board.origin - up * 0.02
	var side := right * HALF_TRACK_WIDTH
	var down := up * -0.2
	var out := []
	for sign in [1.0, -1.0]:
		var c: Vector3 = centre + forward * (HALF_WHEELBASE * sign)
		var a: Vector3 = c + side
		var b: Vector3 = c - side
		out.append(_closest_crossing(a, b, b + down, a + down, c, rails))
	return out


## The slide box along the deck between the trucks.
static func deck_probe(board: Transform3D, rails: Array, inverted := false) -> Hit:
	var up := -board.basis.y if inverted else board.basis.y
	var forward := board.basis.z
	var centre := board.origin + up * SLIDE_PROBE_ABOVE
	var along := forward * HALF_WHEELBASE
	var down := up * -(SLIDE_PROBE_ABOVE + SLIDE_PROBE_BELOW)
	var a := centre + along
	var b := centre - along
	return _closest_crossing(a, b, b + down, a + down, board.origin, rails)


## From each truck out past the tip. [nose, tail]
static func tip_probes(board: Transform3D, rails: Array) -> Array:
	var up := board.basis.y
	var forward := board.basis.z
	var centre := board.origin + up * 0.02
	var out := []
	for sign in [1.0, -1.0]:
		var a: Vector3 = centre + forward * (sign * HALF_WHEELBASE)
		var b: Vector3 = centre + forward * (sign * (HALF_WHEELBASE + 0.215)) + up * 0.03
		out.append(_closest_crossing(a, b, b - up * 0.2, a - up * 0.2, (a + b) * 0.5, rails))
	return out


## Perpendicular to the rail, leaning up.
static func rail_normal(direction: Vector3) -> Vector3:
	var normal := Vector3.UP.cross(direction).cross(direction)
	var length := normal.length()
	if length <= 0.0:
		return Vector3.RIGHT
	if normal.y < 0.0:
		length = -length
	return normal / length


static func rail_direction(rail: Rail) -> Vector3:
	return (rail.end - rail.start).normalized()


## Moving within `degrees` of the rail's direction, seen along the rail's normal.
static func moving_along_rail(direction: Vector3, velocity: Vector3, degrees: float) -> bool:
	var normal := rail_normal(direction)
	var projected := velocity - normal * velocity.dot(normal)
	var length := projected.length()
	if length <= 0.001:
		return true
	return absf((projected / length).dot(direction)) > cos(deg_to_rad(degrees))


## Whether a grind may start: from the air always; riding onto it, only
## within 17 degrees of its line.
static func can_start_grind(direction: Vector3, velocity: Vector3, airborne: bool) -> bool:
	return airborne or moving_along_rail(direction, velocity, 17.0)


## Choose a grind from the probe hits.
static func find(board: Transform3D, rails: Array, velocity: Vector3, airborne: bool) -> Candidate:
	if rails.is_empty():
		return null
	var up := board.basis.y
	var upside_down := up.y < 0.0
	if upside_down:
		var dark := deck_probe(board, rails, true)
		if dark:
			var direction := rail_direction(rails[dark.rail])
			if rail_normal(direction).dot(-up) > 0.45 and absf((board.origin - dark.position).dot(up)) < 0.075 and can_start_grind(direction, velocity, airborne):
				return _candidate(Family.DARKSLIDE, dark, direction, false)
		return null
	var trucks := truck_probes(board, rails)
	var front: Hit = trucks[0]
	var back: Hit = trucks[1]
	if front and back:
		var depth := maxf((board.origin - front.position).dot(up), (board.origin - back.position).dot(up))
		var direction := (front.position - back.position).normalized()
		if depth < 0.13 and absf(up.dot(direction)) <= 0.5 and can_start_grind(direction, velocity, airborne):
			var c := _candidate(Family.FIFTY_FIFTY, front, direction, true)
			c.point = (front.position + back.position) * 0.5
			return c
	for i in 2:
		var hit: Hit = trucks[i]
		if hit == null:
			continue
		var direction := rail_direction(rails[hit.rail])
		var depth := (board.origin - hit.position).dot(up)
		if depth < 0.13 and absf(board.basis.x.dot(direction)) < 0.906 and absf(up.dot(direction)) < 0.46 and can_start_grind(direction, velocity, airborne):
			return _candidate(Family.FIVE_O, hit, direction, i == 0)
	var deck := deck_probe(board, rails)
	if deck:
		var direction := rail_direction(rails[deck.rail])
		var depth := absf((board.origin - deck.position).dot(up))
		var flat := direction - up * direction.dot(up)
		var alignment := absf(flat.normalized().dot(board.basis.z)) if flat.length() > 0.0 else 1.0
		var across := (deck.position - board.origin) - up * (deck.position - board.origin).dot(up)
		var remaining := HALF_WHEELBASE - across.length()
		var clearance := remaining / alignment * sqrt(1.0 - alignment * alignment) if alignment > 0.0 else 999.0
		if rail_normal(direction).dot(up) > 0.65 and depth < 0.06 and clearance > HALF_TRACK_WIDTH and can_start_grind(direction, velocity, airborne):
			return _candidate(Family.BOARDSLIDE, deck, direction, false)
	var tips := tip_probes(board, rails)
	for i in 2:
		var hit: Hit = tips[i]
		if hit == null:
			continue
		var direction := rail_direction(rails[hit.rail])
		if absf(up.dot(direction)) < 0.5 and can_start_grind(direction, velocity, airborne):
			return _candidate(Family.END_SLIDE, hit, direction, i == 0)
	return null


static func _candidate(family: int, hit: Hit, direction: Vector3, front: bool) -> Candidate:
	var c := Candidate.new()
	c.family = family
	c.rail = hit.rail
	c.direction = direction
	c.point = hit.position
	c.front = front
	return c


## Coming onto a rail from the air: remove part of the cross-rail speed on contact.
static func landing_on_rail_velocity(family: int, direction: Vector3, normal: Vector3, velocity: Vector3) -> Vector3:
	var across := normal.cross(direction)
	var removed := across * velocity.dot(across)
	var amount := 0.0
	match family:
		Family.FIFTY_FIFTY, Family.FIVE_O:
			amount = 0.4
		Family.BOARDSLIDE, Family.DARKSLIDE:
			amount = 0.2
		Family.END_SLIDE, Family.STEEP_END_SLIDE:
			amount = 0.8
	return (velocity - removed) * amount + velocity * (1.0 - amount)


## Riding onto a rail: blend toward the rail direction.
static func riding_onto_rail_velocity(family: int, direction: Vector3, velocity: Vector3) -> Vector3:
	var amount := 0.2
	match family:
		Family.BOARDSLIDE:
			amount = 0.1
		Family.END_SLIDE:
			amount = 0.4
	var along := velocity.dot(direction)
	return direction * along * amount + velocity * (1.0 - amount)


## The deck frame each family settles into.
## `yaw` and `pitch` are the player's one-truck adjustments.
static func grind_deck_basis(family: int, board: Basis, direction: Vector3, normal: Vector3, to_point: Vector3, yaw: float, pitch: float) -> Basis:
	match family:
		Family.FIFTY_FIFTY, Family.FIVE_O:
			var forward := direction if direction.dot(board.z) > 0.0 else -direction
			if yaw != 0.0:
				forward = forward.rotated(normal, yaw * -0.68)
			var right := normal.cross(forward).normalized()
			var up := forward.cross(right)
			if pitch != 0.0:
				forward = forward.rotated(right, pitch * 0.68)
				up = forward.cross(right)
			return Basis(right, up, forward).orthonormalized()
		Family.BOARDSLIDE, Family.DARKSLIDE:
			var right := direction if direction.dot(board.x) > 0.0 else -direction
			var up := -normal if family == Family.DARKSLIDE else normal
			return Basis(right, up, right.cross(up)).orthonormalized()
		_:
			var across := direction.cross(normal)
			var axis := direction if not (across.dot(to_point) > 0.0) else -direction
			var angle := 0.733 if family == Family.STEEP_END_SLIDE else 0.349
			var up := normal.rotated(axis, angle)
			var right := direction if direction.dot(board.x) > 0.0 else -direction
			return Basis(right, up, right.cross(up)).orthonormalized()


## Spring the board's contact point onto the rail
## line, with damping along the spring axis.
static func rail_spring_force(point: Vector3, reference: Vector3, across: Vector3, velocity: Vector3, strength: float) -> Vector3:
	var force := across * ((point - reference).dot(across) * strength)
	var length := force.length()
	if not (length > 0.0):
		return Vector3.ZERO
	var axis := force / length
	return force - axis * (strength * 0.1330 * velocity.dot(axis))


## Friction (simplified load): slows the board along the rail.
static func rail_friction(velocity: Vector3, normal: Vector3, load: float, strength: float) -> Vector3:
	var tangent := velocity - normal * velocity.dot(normal)
	var speed := tangent.length()
	if speed <= 0.001:
		return Vector3.ZERO
	return tangent * (-strength * maxf(load, 0.0) / speed)


## Pop out along a normal tipped toward the rail's top,
## sideways by the balance (capped at 1.8 m/s).
static func pop_out_velocity(family: int, rail: Rail, point: Vector3, position: Vector3, velocity: Vector3, balance: float, vertical: float) -> Vector3:
	var direction := rail_direction(rail)
	var normal := rail_normal(direction)
	var candidate: Vector3
	if family == Family.END_SLIDE or family == Family.STEEP_END_SLIDE:
		var across := normal.cross(direction)
		var outward := across if across.dot(position - point) > 0.0 else -across
		candidate = normal + outward * (-0.1093 if family == Family.STEEP_END_SLIDE else 0.291)
	else:
		candidate = Vector3.UP * 0.5 + normal * 0.5
	if candidate.length() > 0.1:
		normal = candidate.normalized()
	var planar := velocity - normal * velocity.dot(normal)
	var lateral := direction.cross(normal) * (balance * 1.8)
	return planar + normal * (vertical * 1.03) + lateral.limit_length(1.8)
