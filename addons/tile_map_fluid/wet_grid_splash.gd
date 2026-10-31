class_name TileFluidGridSplash
extends RefCounted
## Compatibility splash policy: independent doses, soft radius, and exact barrier visibility.


## Add once per shared contact, taking the strongest overlapping patch contribution.
static func apply(field: TileFluidFieldStorage, pose: Transform2D, world: World2D,
		point: Vector2, dose: float, radius: float, mask: int, region: Rect2i) -> bool:
	if not point.is_finite() or not is_finite(dose) or dose <= 0.0 \
			or not is_finite(radius) or radius <= 0.0:
		return false
	var additions: Dictionary[int, float] = {}
	var cells: Array[Vector2i] = []
	for y: int in range(region.position.y, region.end.y):
		for x: int in range(region.position.x, region.end.x):
			cells.append(Vector2i(x, y))
	for cell: Vector2i in cells:
		for patch: TileFluidFieldPatch in field.patches(cell):
			if point.distance_to(TileFluidFieldPolygons.nearest(point, patch.polygon)) >= radius:
				continue
			var contact: bool = Geometry2D.is_point_in_polygon(point, patch.polygon)
			for offset: int in range(patch.corners.size()):
				var position: Vector2 = patch.positions[offset]
				var weight: float = 1.0 if contact else 1.0 - smoothstep(
					radius * 0.65, radius, point.distance_to(position))
				if weight <= 0.0 or not TileFluidVisibility2D.reaches(world, pose * point,
						pose * patch.interior(position), mask):
					continue
				var corner: int = patch.corners[offset]
				additions[corner] = maxf(additions.get(corner, 0.0), minf(dose, 1.0) * weight)
	for corner: int in additions:
		field.set_water(corner, field.water[corner] + additions[corner])
	return not additions.is_empty()
