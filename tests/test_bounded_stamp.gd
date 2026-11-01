extends "res://tests/test_case.gd"
## Compare indexed stamping with exhaustive patch selection, including lattice boundaries.


class CountingField extends TileFluidFieldStorage:
	var visits: int = 0

	func patches(cell: Vector2i) -> Array[TileFluidFieldPatch]:
		visits += 1
		return super.patches(cell)


## A tiny union visits nearby cells at either density, with negative cells and transformed floors.
func test_bounded_contacts_match_exhaustive_selection() -> void:
	for spacing: float in [16.0, 32.0]:
		var origin: Vector2 = Vector2(7, -11)
		var field: CountingField = CountingField.new()
		for y: int in range(-12, 12):
			for x: int in range(-12, 12):
				var cell: Vector2i = Vector2i(x, y)
				field.add_cell(cell, [TileFluidFieldPolygons.rectangle(
					Rect2(origin + Vector2(cell) * spacing, Vector2.ONE * spacing))])
		field.end_rebuild()
		for pose: Transform2D in [Transform2D.IDENTITY,
				Transform2D(0.3, Vector2(2, 1.5), 0.0, Vector2(-200, 90))]:
			var root: Node2D = track(Node2D.new()) as Node2D
			root.transform = pose
			add_child(root)
			var footprint: TileFluidFootprint2D = _footprint(root)
			for offset: Vector2 in [Vector2.ZERO, Vector2(-1, -1), Vector2(0.5, 0.5)]:
				footprint.position = origin + offset * spacing
				field.visits = 0
				var contacts: Dictionary[int, bool] = TileFluidGridStamp.contacts(field, pose,
					footprint, footprint.global_position, 0, [], spacing, origin)
				check(field.visits <= 25, "Small stamps must not scan the entire floor")
				var expected: Dictionary[int, bool] = {}
				for cell: Vector2i in field.cells:
					for patch: TileFluidFieldPatch in field.patches(cell):
						_reference_collect(footprint, patch, pose, expected)
				check(not expected.is_empty())
				check(contacts.size() == expected.size())
				for corner: int in expected:
					check(contacts.has(corner), "Indexed selection dropped a boundary contact")


## A huge footprint must scan sparse occupied cells instead of its enormous empty envelope.
func test_large_footprint_over_distant_islands() -> void:
	var field: CountingField = CountingField.new()
	for x: int in [-10000, 10000]:
		field.add_cell(Vector2i(x, 0), [TileFluidFieldPolygons.rectangle(Rect2(x * 32, 0, 32, 32))])
	field.end_rebuild()
	var root: Node2D = track(Node2D.new()) as Node2D
	add_child(root)
	var footprint: TileFluidFootprint2D = _footprint(root)
	var shape: CollisionShape2D = footprint.get_child(0) as CollisionShape2D
	var circle: CircleShape2D = shape.shape as CircleShape2D
	circle.radius = 400000.0
	field.visits = 0
	var contacts: Dictionary[int, bool] = TileFluidGridStamp.contacts(field, Transform2D.IDENTITY,
		footprint, Vector2.ZERO, 0, [], 32.0, Vector2.ZERO)
	check(field.visits == 2)
	check(contacts.size() == 8)


func _footprint(parent: Node2D) -> TileFluidFootprint2D:
	var footprint: TileFluidFootprint2D = TileFluidFootprint2D.new()
	var circle: CollisionShape2D = CollisionShape2D.new()
	var circle_shape: CircleShape2D = CircleShape2D.new()
	circle_shape.radius = 2.0
	circle.shape = circle_shape
	footprint.add_child(circle)
	var rectangle: CollisionShape2D = CollisionShape2D.new()
	var rectangle_shape: RectangleShape2D = RectangleShape2D.new()
	rectangle_shape.size = Vector2(4, 4)
	rectangle.shape = rectangle_shape
	footprint.add_child(rectangle)
	parent.add_child(footprint)
	return footprint


func _reference_collect(footprint: TileFluidFootprint2D, patch: TileFluidFieldPatch,
		pose: Transform2D, result: Dictionary[int, bool]) -> void:
	if TileFluidFootprintContacts.points(footprint, pose * patch.polygon).is_empty():
		return
	var covered: bool = false
	for point: Vector2 in patch.positions:
		covered = covered or footprint.contains_world_point(pose * point)
	for offset: int in range(patch.corners.size()):
		if not covered or footprint.contains_world_point(pose * patch.positions[offset]):
			result[patch.corners[offset]] = true
