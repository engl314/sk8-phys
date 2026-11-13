class_name TwoBoneIK

## Returns [middle, end]. `pole` points where the middle joint should bend toward.
## Interior-angle limits are in degrees.
static func solve(root: Vector3, upper_length: float, lower_length: float, target: Vector3, pole: Vector3,
		minimum_degrees := 0.0, maximum_degrees := 180.0) -> Array:
	var delta := target - root
	var distance := delta.length()
	if distance < 1e-6:
		return [root + pole.normalized() * upper_length, root]
	var direction := delta / distance
	var sum_squared := upper_length * upper_length + lower_length * lower_length
	var twice_product := 2.0 * upper_length * lower_length
	var minimum_distance := sqrt(maxf(sum_squared - twice_product * cos(deg_to_rad(minimum_degrees)), 0.0))
	var maximum_distance := sqrt(maxf(sum_squared - twice_product * cos(deg_to_rad(maximum_degrees)), 0.0))
	if distance >= upper_length + lower_length and maximum_degrees >= 180.0:
		# Extended: straight limb pointing at the target.
		var middle := root + direction * upper_length
		return [middle, middle + direction * lower_length]
	distance = clampf(distance, minimum_distance + 1e-4, maximum_distance - 1e-4)
	# Bend plane normal from the pole, kept perpendicular to the limb axis.
	var bend := pole - direction * direction.dot(pole)
	if bend.length_squared() < 1e-10:
		bend = Vector3.UP - direction * direction.y
		if bend.length_squared() < 1e-10:
			bend = Vector3.FORWARD
	bend = bend.normalized()
	var cosine := clampf((upper_length * upper_length + distance * distance - lower_length * lower_length) / (2.0 * upper_length * distance), -1.0, 1.0)
	var root_angle := acos(cosine)
	var middle := root + (direction * cos(root_angle) + bend * sin(root_angle)) * upper_length
	var end := root + direction * distance
	return [middle, end]
