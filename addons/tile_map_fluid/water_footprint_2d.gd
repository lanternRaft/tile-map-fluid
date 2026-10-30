class_name WaterFootprint2D
extends Area2D
## Author direct CollisionShape2D/CollisionPolygon2D children as a UNION, including hose cones.
## This Area discovers receivers only; floor samples use geometry directly, without tile Areas.


## Unsupported shapes fail clearly instead of silently depositing a different footprint.
func validation_error() -> String:
	var count: int = 0
	for child: Node in get_children():
		if child is CollisionShape2D:
			var contact: CollisionShape2D = child as CollisionShape2D
			if contact.disabled:
				continue
			if not contact.shape is CircleShape2D and not contact.shape is RectangleShape2D:
				return "WaterFootprint2D supports circles, rectangles, and solid polygons."
			if contact.shape is CircleShape2D:
				var circle: CircleShape2D = contact.shape as CircleShape2D
				if not is_finite(circle.radius) or circle.radius <= 0.0:
					return "WaterFootprint2D circle radius must be finite and positive."
			if contact.shape is RectangleShape2D:
				var rectangle: RectangleShape2D = contact.shape as RectangleShape2D
				if not rectangle.size.is_finite() or rectangle.size.x <= 0.0 \
						or rectangle.size.y <= 0.0:
					return "WaterFootprint2D rectangle size must be finite and positive."
			if not _valid_pose(contact.global_transform):
				return "WaterFootprint2D shapes need finite, invertible transforms."
			count += 1
		elif child is CollisionPolygon2D:
			var contact: CollisionPolygon2D = child as CollisionPolygon2D
			if contact.disabled:
				continue
			if contact.build_mode != CollisionPolygon2D.BUILD_SOLIDS or contact.polygon.size() < 3:
				return "WaterFootprint2D polygons must be filled with at least three vertices."
			for point: Vector2 in contact.polygon:
				if not point.is_finite():
					return "WaterFootprint2D polygon vertices must be finite."
			if Geometry2D.triangulate_polygon(contact.polygon).is_empty():
				return "WaterFootprint2D polygons must be simple filled regions."
			if not _valid_pose(contact.global_transform):
				return "WaterFootprint2D shapes need finite, invertible transforms."
			count += 1
	return "WaterFootprint2D needs at least one enabled shape." if count == 0 else ""


## Exact analytic circle/rectangle tests in each shape's local space, including scaled parents.
func contains_world_point(point: Vector2) -> bool:
	if not point.is_finite() or not validation_error().is_empty():
		return false
	for child: Node in get_children():
		if child is CollisionShape2D:
			var contact: CollisionShape2D = child as CollisionShape2D
			if contact.disabled:
				continue
			var local: Vector2 = contact.to_local(point)
			if contact.shape is CircleShape2D:
				var circle: CircleShape2D = contact.shape as CircleShape2D
				if local.length_squared() <= circle.radius * circle.radius:
					return true
			if contact.shape is RectangleShape2D:
				var rectangle: RectangleShape2D = contact.shape as RectangleShape2D
				if Rect2(-rectangle.size * 0.5, rectangle.size).has_point(local):
					return true
		if child is CollisionPolygon2D:
			var contact: CollisionPolygon2D = child as CollisionPolygon2D
			if not contact.disabled \
					and Geometry2D.is_point_in_polygon(contact.to_local(point), contact.polygon):
				return true
	return false


## Broad phase supplied by the same authored Area; emitter deduplicates with explicit receivers.
func receivers() -> Array[Wettable2D]:
	var result: Array[Wettable2D] = []
	if not is_inside_tree() or not monitoring:
		return result
	for area: Area2D in get_overlapping_areas():
		if area is Wettable2D:
			result.append(area as Wettable2D)
	return result


## Conservative WORLD envelope lets a backend visit nearby samples, then test the exact union.
func world_bounds() -> Rect2:
	if not validation_error().is_empty():
		return Rect2()
	var result: Rect2
	for child: Node in get_children():
		var polygon: PackedVector2Array = []
		if child is CollisionShape2D:
			var contact: CollisionShape2D = child as CollisionShape2D
			if contact.disabled:
				continue
			var size: Vector2
			if contact.shape is CircleShape2D:
				var circle: CircleShape2D = contact.shape as CircleShape2D
				size = Vector2.ONE * circle.radius * 2.0
			else:
				var rectangle: RectangleShape2D = contact.shape as RectangleShape2D
				size = rectangle.size
			polygon = contact.global_transform * WetSurfaceCoverage.rectangle(
				Rect2(-size * 0.5, size))
		if child is CollisionPolygon2D:
			var contact: CollisionPolygon2D = child as CollisionPolygon2D
			if not contact.disabled:
				polygon = contact.global_transform * contact.polygon
		if polygon.is_empty():
			continue
		var area: Rect2 = Rect2(polygon[0], Vector2.ZERO)
		for point: Vector2 in polygon:
			area = area.expand(point)
		result = result.merge(area) if result.has_area() else area
	return result


static func _valid_pose(pose: Transform2D) -> bool:
	return pose.is_finite() and not is_zero_approx(pose.determinant())
