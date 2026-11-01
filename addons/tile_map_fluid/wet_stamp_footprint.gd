class_name TileFluidStampFootprint
extends RefCounted
## One emission's validated shape union in field space; never caches across scene edits.

class Shape:
	var inverse: Transform2D
	var center: Vector2
	var radius_squared: float = -1.0
	var rectangle: Rect2
	var polygon: PackedVector2Array = []

	func contains(point: Vector2) -> bool:
		var local: Vector2 = inverse * point
		if radius_squared >= 0.0:
			return local.length_squared() <= radius_squared
		if rectangle.has_area():
			return rectangle.has_point(local)
		return Geometry2D.is_point_in_polygon(local, polygon)

	func overlaps(outline: PackedVector2Array) -> bool:
		if radius_squared < 0.0:
			return not Geometry2D.intersect_polygons(inverse * outline, polygon).is_empty()
		if Geometry2D.is_point_in_polygon(center, outline):
			return true
		var previous: Vector2 = inverse * outline[-1]
		for vertex: Vector2 in outline:
			var current: Vector2 = inverse * vertex
			if Geometry2D.get_closest_point_to_segment(Vector2.ZERO, previous, current) \
					.length_squared() <= radius_squared:
				return true
			previous = current
		return false

## Conservative envelope of enabled shapes, expressed directly in the field's coordinates.
var bounds: Rect2
var _shapes: Array[Shape] = []


## Resolve children, inverses and shape data once; mutable Resources are read again next stamp.
func configure(footprint: TileFluidFootprint2D, field_pose: Transform2D) -> bool:
	_shapes.clear()
	bounds = Rect2()
	if not footprint.validation_error().is_empty():
		return false
	var inverse: Transform2D = field_pose.affine_inverse()
	for child: Node in footprint.get_children():
		var shape: Shape = Shape.new()
		var pose: Transform2D
		var outline: PackedVector2Array
		if child is CollisionShape2D:
			var contact: CollisionShape2D = child as CollisionShape2D
			if contact.disabled:
				continue
			pose = inverse * contact.global_transform
			if contact.shape is CircleShape2D:
				var circle: CircleShape2D = contact.shape as CircleShape2D
				shape.radius_squared = circle.radius * circle.radius
				outline = TileFluidFieldPolygons.rectangle(Rect2(
					Vector2.ONE * -circle.radius, Vector2.ONE * circle.radius * 2.0))
			else:
				var rectangle: RectangleShape2D = contact.shape as RectangleShape2D
				shape.rectangle = Rect2(-rectangle.size * 0.5, rectangle.size)
				shape.polygon = TileFluidFieldPolygons.rectangle(shape.rectangle)
				outline = shape.polygon
		elif child is CollisionPolygon2D:
			var contact: CollisionPolygon2D = child as CollisionPolygon2D
			if contact.disabled:
				continue
			pose = inverse * contact.global_transform
			shape.polygon = contact.polygon
			outline = shape.polygon
		else:
			continue
		shape.inverse = pose.affine_inverse()
		shape.center = pose.origin
		var envelope: Rect2 = TileFluidFieldPolygons.bounds(pose * outline)
		bounds = envelope if _shapes.is_empty() else bounds.merge(envelope)
		_shapes.append(shape)
	# Clipping uses a 1/1000 pixel lattice; retain boundary candidates after affine roundoff.
	bounds = bounds.grow(0.001)
	return true


## Exact union containment without revalidating Resources or reading scene children per corner.
func contains(point: Vector2) -> bool:
	for shape: Shape in _shapes:
		if shape.contains(point):
			return true
	return false


## Boolean overlap stops at the first shape; circles need neither clipping nor contact arrays.
func overlaps(polygon: PackedVector2Array) -> bool:
	for shape: Shape in _shapes:
		if shape.overlaps(polygon):
			return true
	return false
