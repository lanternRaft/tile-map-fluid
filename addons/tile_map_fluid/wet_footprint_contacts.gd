class_name TileFluidFootprintContacts
extends RefCounted
## Geometry-only overlap for footprints smaller than the lattice spacing.


## A contact within each intersecting authored shape; polygons are WORLD-space floor patches.
static func points(footprint: TileFluidFootprint2D, polygon: PackedVector2Array) \
		-> PackedVector2Array:
	var result: Array[Vector2] = []
	for child: Node in footprint.get_children():
		if child is CollisionShape2D:
			var contact: CollisionShape2D = child as CollisionShape2D
			if contact.disabled:
				continue
			var local: PackedVector2Array = contact.global_transform.affine_inverse() * polygon
			if contact.shape is CircleShape2D:
				var circle: CircleShape2D = contact.shape as CircleShape2D
				var nearest: Vector2 = TileFluidFieldPolygons.nearest(Vector2.ZERO, local)
				if nearest.length_squared() <= circle.radius * circle.radius:
					result.append(contact.to_global(nearest))
			elif contact.shape is RectangleShape2D:
				var rectangle: RectangleShape2D = contact.shape as RectangleShape2D
				_append_overlap(result, contact.global_transform, local,
					TileFluidSurfaceCoverage.rectangle(Rect2(-rectangle.size * 0.5, rectangle.size)))
		elif child is CollisionPolygon2D:
			var contact: CollisionPolygon2D = child as CollisionPolygon2D
			if not contact.disabled:
				_append_overlap(result, contact.global_transform,
					contact.global_transform.affine_inverse() * polygon, contact.polygon)
	return PackedVector2Array(result)


static func _append_overlap(result: Array[Vector2], pose: Transform2D,
		patch: PackedVector2Array, shape: PackedVector2Array) -> void:
	for overlap: PackedVector2Array in Geometry2D.intersect_polygons(patch, shape):
		if not overlap.is_empty():
			result.append(pose * overlap[0])
