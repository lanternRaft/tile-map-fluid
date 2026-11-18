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


## A newly exposed dry side can share XY with a wet side. After both dry, preserve
## the historical highest-slot tie break.
func test_coincident_slots_reconnect_after_passive_drying() -> void:
	var field := TileFluidFieldStorage.new()
	field.begin_rebuild(false)
	field.add_cell(Vector2i.ZERO, [_rect(0)])
	field.end_rebuild()
	var left_slot: int = field.patches(Vector2i.ZERO)[0].corners[1]
	field.set_water(left_slot, 0.5)
	field.begin_replace([Vector2i.RIGHT])
	field.add_cell(Vector2i.RIGHT, [_rect(32)])
	field.end_rebuild()
	var right_slot: int = field.patches(Vector2i.RIGHT)[0].corners[0]
	check(right_slot != left_slot, "Newly exposed seam starts independently dry")
	field.wetness.clock += 1.0
	var above := Vector2i(1, -1)
	field.begin_replace([above])
	field.add_cell(above, [TileFluidFieldPolygons.rectangle(Rect2(32, -32, 32, 32))])
	field.end_rebuild()
	check(field.patches(above)[0].corners[2] == maxi(left_slot, right_slot),
		"Coincident, now dry contacts retain the reference slot ordering")
