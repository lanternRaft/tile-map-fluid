class_name WetFieldPolygons
extends RefCounted


## Splits around a solid into convex pieces, avoiding polygon holes that CanvasItem cannot fill.
static func subtract(pieces: Array[PackedVector2Array], solid: PackedVector2Array) \
		-> Array[PackedVector2Array]:
	for convex: PackedVector2Array in Geometry2D.decompose_polygon_in_convex(solid):
		var next: Array[PackedVector2Array] = []
		for piece: PackedVector2Array in pieces:
			var remaining: PackedVector2Array = piece
			var winding: float = 0.0
			for index: int in range(convex.size()):
				winding += convex[index].cross(convex[(index + 1) % convex.size()])
			for index: int in range(convex.size()):
				var a: Vector2 = convex[index]
				var b: Vector2 = convex[(index + 1) % convex.size()]
				var outside: PackedVector2Array = _half_plane(remaining, a, b, -signf(winding))
				if outside.size() >= 3:
					next.append(outside)
				remaining = _half_plane(remaining, a, b, signf(winding))
				if remaining.size() < 3:
					break
		pieces = next
	return pieces


## Projects a sample onto a clipped cell without leaving the actual floor polygon.
static func nearest(point: Vector2, polygon: PackedVector2Array) -> Vector2:
	if Geometry2D.is_point_in_polygon(point, polygon):
		return point
	var result: Vector2 = polygon[0]
	for index: int in range(polygon.size()):
		var candidate: Vector2 = Geometry2D.get_closest_point_to_segment(
			point, polygon[index], polygon[(index + 1) % polygon.size()])
		if candidate.distance_squared_to(point) < result.distance_squared_to(point):
			result = candidate
	return result


## Uses the authored vertices rather than the field envelope for partial cells.
static func bounds(polygon: PackedVector2Array) -> Rect2:
	var result: Rect2 = Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		result = result.expand(point)
	return result


## Axis-aligned grid cells and rectangle physics shapes share this winding.
static func rectangle(rect: Rect2) -> PackedVector2Array:
	return PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y),
		rect.end, Vector2(rect.position.x, rect.end.y)])


## Split each crossed edge at the clipping line and retain vertices on the requested side.
static func _half_plane(polygon: PackedVector2Array, a: Vector2, b: Vector2,
		side: float) -> PackedVector2Array:
	var result: PackedVector2Array = []
	if polygon.is_empty():
		return result
	var previous: Vector2 = polygon[-1]
	var previous_distance: float = (b - a).cross(previous - a) * side
	for point: Vector2 in polygon:
		var distance: float = (b - a).cross(point - a) * side
		if (distance > 0.0) != (previous_distance > 0.0):
			result.append(previous.lerp(point, previous_distance / (previous_distance - distance)))
		if distance >= 0.0:
			result.append(point)
		previous = point
		previous_distance = distance
	var clean: PackedVector2Array = []
	for point: Vector2 in result:
		if clean.is_empty() or not clean[-1].is_equal_approx(point):
			clean.append(point)
	if clean.size() > 1 and clean[0].is_equal_approx(clean[-1]):
		clean.resize(clean.size() - 1)
	return clean
