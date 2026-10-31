extends "res://tests/test_case.gd"
## Repeated geometry changes must reuse released contact slots and preserve distant puddles.


func test_regional_replacements_bound_storage_and_preserve_water() -> void:
	var field: TileFluidFieldStorage = TileFluidFieldStorage.new()
	field.begin_rebuild(false)
	field.add_cell(Vector2i.ZERO, [_rect(0)])
	field.add_cell(Vector2i.RIGHT, [_rect(32)])
	field.end_rebuild()
	var untouched: TileFluidFieldPatch = field.patches(Vector2i.ZERO)[0]
	var corners: PackedInt32Array = untouched.corners.duplicate()
	for corner: int in untouched.corners:
		field.set_water(corner, 0.75)
	var capacity: int = 0
	for cycle: int in range(100):
		field.begin_replace([Vector2i.RIGHT])
		var polygons: Array[PackedVector2Array] = []
		if cycle % 2 == 1:
			polygons.append(_rect(32))
		field.add_cell(Vector2i.RIGHT, polygons)
		field.end_rebuild()
		check(field.has_water())
		if cycle < 2:
			capacity = maxi(capacity, field.water.size())
		else:
			check(field.water.size() == capacity)
		check(untouched.corners == corners)
		check(untouched.water(field.water) == Color(0.75, 0.75, 0.75, 0.75))
		if cycle % 2 == 1:
			var neighbor: TileFluidFieldPatch = field.patches(Vector2i.RIGHT)[0]
			check(neighbor.water(field.water) == Color(0, 0, 0, 0))


func _rect(x: float) -> PackedVector2Array:
	return TileFluidFieldPolygons.rectangle(Rect2(x, 0, 32, 32))
