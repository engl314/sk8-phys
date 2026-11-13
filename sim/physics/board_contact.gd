class_name BoardContact
extends RefCounted

## Board body index for A (0..6). B is the static world unless body_b >= 0.
var body_a := 0
var body_b := -1
var position_on_a := Vector3.ZERO
var position_on_b := Vector3.ZERO
var normal := Vector3.UP
var restitution := 0.0
var static_friction := 0.0
var dynamic_friction := 0.0
## Collider the contact came from, for surface lookups (null for tests).
var collider: Object


static func make(body: int, on_a: Vector3, on_b: Vector3, contact_normal: Vector3, material: ContactMaterial) -> BoardContact:
	var c := BoardContact.new()
	c.body_a = body
	c.position_on_a = on_a
	c.position_on_b = on_b
	c.normal = contact_normal
	c.restitution = material.restitution
	c.static_friction = material.static_friction
	c.dynamic_friction = material.dynamic_friction
	return c
