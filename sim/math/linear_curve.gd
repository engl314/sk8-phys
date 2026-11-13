class_name LinearCurve

## Build a Curve from [x, y] pairs with linear tangents.
static func make(points: Array) -> Curve:
	var curve := Curve.new()
	var min_x := INF
	var max_x := -INF
	var min_y := INF
	var max_y := -INF
	for p in points:
		min_x = minf(min_x, p[0])
		max_x = maxf(max_x, p[0])
		min_y = minf(min_y, p[1])
		max_y = maxf(max_y, p[1])
	if max_x <= min_x:
		max_x = min_x + 1.0
	if max_y <= min_y:
		max_y = min_y + 1.0
	curve.min_domain = min_x
	curve.max_domain = max_x
	curve.min_value = minf(min_y, 0.0)
	curve.max_value = maxf(max_y, 1.0)
	for p in points:
		curve.add_point(Vector2(p[0], p[1]), 0.0, 0.0, Curve.TANGENT_LINEAR, Curve.TANGENT_LINEAR)
	return curve


static func constant(value: float) -> Curve:
	return make([[0.0, value], [1.0, value]])


## The curve's value at `x`.
static func evaluate(curve: Curve, x: float) -> float:
	var count := curve.point_count
	if count == 0:
		return 0.0
	var first := curve.get_point_position(0)
	if x < first.x:
		return first.y
	var last := curve.get_point_position(count - 1)
	if not (x < last.x):
		return last.y
	var lower := first
	for i in range(1, count):
		var upper := curve.get_point_position(i)
		if x < upper.x:
			var width := upper.x - lower.x
			if width <= 0.0:
				return upper.y
			return lower.y + (upper.y - lower.y) / width * (x - lower.x)
		lower = upper
	return first.y
