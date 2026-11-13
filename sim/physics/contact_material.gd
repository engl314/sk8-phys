class_name ContactMaterial
extends Resource

@export var static_friction := 0.0
@export var dynamic_friction := 0.0
@export var restitution := 0.0


static func make(static_value: float, dynamic_value: float, restitution_value: float) -> ContactMaterial:
	var m := ContactMaterial.new()
	m.static_friction = static_value
	m.dynamic_friction = dynamic_value
	m.restitution = restitution_value
	return m


## Combine two materials: greater frictions, lesser restitution.
## Equal or unordered comparisons select B.
static func combine(a: ContactMaterial, b: ContactMaterial) -> ContactMaterial:
	return make(
		a.static_friction if a.static_friction > b.static_friction else b.static_friction,
		a.dynamic_friction if a.dynamic_friction > b.dynamic_friction else b.dynamic_friction,
		a.restitution if a.restitution < b.restitution else b.restitution)
