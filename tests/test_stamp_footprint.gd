extends "res://tests/test_case.gd"
## Prepared shape tests must agree with the original world-space geometry on mutable scenes.

class CountingFootprint extends TileFluidFootprint2D:
	var validations: int = 0

	func validation_error() -> String:
		validations += 1
		return super.validation_error()


## Circles, rectangles and concave polygons retain overlap/containment under affine transforms.
func test_prepared_geometry_matches_world_space_reference() -> void:
	for pose: Transform2D in [Transform2D.IDENTITY,
			Transform2D(0.3, Vector2(2, 1.5), 0.0, Vector2(-200, 90))]:
		var root: Node2D = track(Node2D.new()) as Node2D
		root.transform = pose
		add_child(root)
		var footprint: TileFluidFootprint2D = TileFluidFootprint2D.new()
		footprint.position = Vector2(7, -5)
		root.add_child(footprint)
		var circle: CollisionShape2D = CollisionShape2D.new()
		var circle_shape: CircleShape2D = CircleShape2D.new()
		circle_shape.radius = 5.0
		circle.shape = circle_shape
		circle.transform = Transform2D(0.4, Vector2(-1.25, 0.8), 0.0, Vector2(-3, 2))
		footprint.add_child(circle)
		var rectangle: CollisionShape2D = CollisionShape2D.new()
		var rectangle_shape: RectangleShape2D = RectangleShape2D.new()
		rectangle_shape.size = Vector2(8, 6)
		rectangle.shape = rectangle_shape
		rectangle.rotation = 0.2
		footprint.add_child(rectangle)
		var polygon: CollisionPolygon2D = CollisionPolygon2D.new()
		polygon.polygon = PackedVector2Array([Vector2(-5, -4), Vector2(5, -4),
			Vector2(5, 0), Vector2.ZERO, Vector2(0, 6), Vector2(-5, 6)])
		polygon.rotation = -0.3
		footprint.add_child(polygon)
		for selected: int in range(4):
			circle.disabled = selected != 0 and selected != 3
			rectangle.disabled = selected != 1 and selected != 3
			polygon.disabled = selected != 2 and selected != 3
			var query: TileFluidStampFootprint = TileFluidStampFootprint.new()
			check(query.configure(footprint, pose))
			for y: int in range(-16, 17, 3):
				for x: int in range(-16, 17, 3):
					var point: Vector2 = Vector2(x + 0.37, y + 0.41)
					check(query.contains(point) == footprint.contains_world_point(pose * point))
					var patch: PackedVector2Array = TileFluidFieldPolygons.rectangle(
						Rect2(point, Vector2(4, 3)))
					var expected: bool = not TileFluidFootprintContacts.points(footprint, pose * patch).is_empty()
					check(query.overlaps(patch) == expected)


## Per-patch reads do not validate again; a new stamp sees moved/disabled/edited shapes.
func test_preparation_validates_once_and_observes_resource_edits() -> void:
	var footprint: CountingFootprint = track(CountingFootprint.new()) as CountingFootprint
	add_child(footprint)
	var child: CollisionShape2D = CollisionShape2D.new()
	var circle: CircleShape2D = CircleShape2D.new()
	circle.radius = 2.0
	child.shape = circle
	footprint.add_child(child)
	var query: TileFluidStampFootprint = TileFluidStampFootprint.new()
	check(query.configure(footprint, Transform2D.IDENTITY))
	var patch: PackedVector2Array = TileFluidFieldPolygons.rectangle(Rect2(2, -1, 3, 2))
	check(query.overlaps(patch), "Circle tangency remains inclusive")
	for tick: int in range(100):
		check(not query.contains(Vector2(5, 0)))
		check(query.overlaps(patch))
	check(footprint.validations == 1)
	circle.radius = 6.0
	check(query.configure(footprint, Transform2D.IDENTITY))
	check(query.contains(Vector2(5, 0)))
	child.position = Vector2(30, 0)
	check(query.configure(footprint, Transform2D.IDENTITY))
	check(not query.overlaps(patch))
	child.disabled = true
	check(not query.configure(footprint, Transform2D.IDENTITY))
	check(not query.contains(Vector2(30, 0)))
