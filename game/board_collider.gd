class_name BoardCollider
extends RefCounted

## Contacts are kept while a wheel is within this gap.
var padding := 0.05
var wheel_material := ContactMaterial.make(0.9, 0.7, 0.0)
var deck_material := ContactMaterial.make(0.5, 0.35, 0.0)
var default_floor_material := ContactMaterial.make(0.0, 0.0, 1.0)
var collision_mask := 1
## While grinding, board-to-rail contacts carry no friction: the grind's own
## friction model slows the board.
var grinding := false

var _sphere := SphereShape3D.new()
var _truck := CapsuleShape3D.new()
var _truck_query := PhysicsShapeQueryParameters3D.new()
var _deck_box := BoxShape3D.new()
var _sphere_query := PhysicsShapeQueryParameters3D.new()
var _deck_query := PhysicsShapeQueryParameters3D.new()
var _ray := PhysicsRayQueryParameters3D.new()


func _init() -> void:
	_sphere.radius = BoardSpec.WHEEL_RADIUS + padding
	_sphere_query.shape = _sphere
	_deck_box.size = Vector3(BoardSpec.DECK_WIDTH, BoardSpec.DECK_THICKNESS, BoardSpec.DECK_FLAT_LENGTH)
	_deck_query.shape = _deck_box
	# Truck capsules, 0.064 m half-length along the axle, made thicker than the
	# truck so thin rails register reliably.
	_truck.radius = 0.014
	_truck.height = 0.064 * 2.0 + 0.028
	_truck_query.shape = _truck


func gather(board: BoardPhysics, space: PhysicsDirectSpaceState3D) -> Array[BoardContact]:
	var out: Array[BoardContact] = []
	_sphere_query.collision_mask = collision_mask
	_deck_query.collision_mask = collision_mask
	var down := -board.deck().basis.y
	_ray.collision_mask = collision_mask
	for wheel in BoardSpec.WHEELS:
		_wheel_contacts(wheel, board.bodies[wheel].position, space, out, down)
	_deck_contacts(board.deck(), space, out)
	_truck_query.collision_mask = collision_mask
	for truck in [BoardSpec.Body.FRONT_TRUCK, BoardSpec.Body.BACK_TRUCK]:
		_truck_contacts(truck, board.bodies[truck], space, out)
	return out


## Truck capsule: penetrating points only, like the deck. The capsule's axis
## (Godot +Y) is turned onto the truck's axle (its local +Z).
##
## collide_shape also reports pairs that are only within the query margin. For
## those the world point lies beyond the shape's own point, so the direction
## between them points into the world; `_overlaps` drops them.
func _truck_contacts(index: int, truck: SimBody, space: PhysicsDirectSpaceState3D, out: Array[BoardContact]) -> void:
	_truck_query.transform = Transform3D(truck.basis * Basis(Vector3.RIGHT, PI * 0.5), truck.position)
	var points := space.collide_shape(_truck_query, 4)
	for k in range(0, points.size(), 2):
		var on_truck: Vector3 = points[k]
		var on_world: Vector3 = points[k + 1]
		var offset := on_world - on_truck
		if offset.length_squared() < 1e-10 or not _overlaps(offset, on_truck, truck.position):
			continue
		out.append(BoardContact.make(index, on_truck, on_world, offset.normalized(), _board_material(deck_material)))
		break


## The shape's point is inside the world (penetration) rather than short of it:
## pushing it out to the world point moves it back toward the shape's centre.
static func _overlaps(offset: Vector3, on_shape: Vector3, center: Vector3) -> bool:
	return offset.dot(on_shape - center) <= 0.0


func _material_for(_collider: Object) -> ContactMaterial:
	return default_floor_material


const _GRIND_MATERIAL_VALUES := [0.0, 0.0, 0.0]


func _board_material(base: ContactMaterial) -> ContactMaterial:
	if grinding:
		return ContactMaterial.make(_GRIND_MATERIAL_VALUES[0], _GRIND_MATERIAL_VALUES[1], _GRIND_MATERIAL_VALUES[2])
	return ContactMaterial.combine(base, _material_for(null))


## Wheel contacts. The riding surface comes from a short ray along the deck's
## down axis: it returns the face normal, so segmented curves (ramp and half-pipe
## transitions) give smooth normals.
## The sphere query then adds only genuine walls and curbs: contacts steeper
## than 45 degrees from the riding surface that stand clear of its plane.
func _wheel_contacts(wheel: int, center: Vector3, space: PhysicsDirectSpaceState3D, out: Array[BoardContact], down: Vector3) -> void:
	var radius := BoardSpec.WHEEL_RADIUS
	var material := _board_material(wheel_material)
	_ray.from = center - down * 0.06
	_ray.to = center + down * (radius + padding)
	var hit := space.intersect_ray(_ray)
	var ground_normal := Vector3.ZERO
	var ground_point := Vector3.ZERO
	if not hit.is_empty():
		ground_normal = hit.normal
		var distance: float = (center - hit.position).dot(ground_normal)
		if distance - radius <= padding and distance > -radius:
			ground_point = center - ground_normal * distance
			out.append(BoardContact.make(wheel, center - ground_normal * radius, ground_point, ground_normal, material))
	_sphere_query.transform = Transform3D(Basis.IDENTITY, center)
	var points := space.collide_shape(_sphere_query, 8)
	var kept_points: Array[Vector3] = []
	var kept_normals: Array[Vector3] = []
	if ground_normal != Vector3.ZERO:
		kept_points.append(ground_point)
		kept_normals.append(ground_normal)
	for k in range(0, points.size(), 2):
		var on_world: Vector3 = points[k + 1]
		var distance := center.distance_to(on_world)
		if distance < 1e-6 or distance - radius > padding:
			continue
		var normal := (center - on_world) / distance
		if ground_normal != Vector3.ZERO and normal.dot(ground_normal) > 0.7:
			continue
		var internal := false
		for j in kept_points.size():
			if kept_normals[j].dot(on_world - kept_points[j]) < 0.004:
				internal = true
				break
		if internal:
			continue
		kept_points.append(on_world)
		kept_normals.append(normal)
		out.append(BoardContact.make(wheel, center - normal * radius, on_world, normal, material))


## Deck box: only penetrating points. The normal points from the deck's
## deepest point to the surface, which pushes the deck out.
func _deck_contacts(deck: SimBody, space: PhysicsDirectSpaceState3D, out: Array[BoardContact]) -> void:
	_deck_query.transform = deck.transform()
	var points := space.collide_shape(_deck_query, 8)
	var kept: Array[Vector3] = []
	for k in range(0, points.size(), 2):
		var on_deck: Vector3 = points[k]
		var on_world: Vector3 = points[k + 1]
		var offset := on_world - on_deck
		if offset.length_squared() < 1e-10 or not _overlaps(offset, on_deck, deck.position):
			continue
		var normal := offset.normalized()
		var duplicate := false
		for existing in kept:
			if existing.distance_squared_to(on_deck) < 1e-4:
				duplicate = true
				break
		if duplicate:
			continue
		kept.append(on_deck)
		out.append(BoardContact.make(BoardSpec.Body.DECK, on_deck, on_world, normal, _board_material(deck_material)))


## Four short rays down the deck's up vector, one per wheel:
## used for surface normal / ground checks, not for forces.
func ground_rays(board: BoardPhysics, space: PhysicsDirectSpaceState3D, length := 0.2) -> Array[Dictionary]:
	var up := board.deck().basis.y
	var hits: Array[Dictionary] = []
	_ray.collision_mask = collision_mask
	for wheel in BoardSpec.WHEELS:
		var from := board.bodies[wheel].position
		_ray.from = from
		_ray.to = from - up * length
		hits.append(space.intersect_ray(_ray))
	return hits
