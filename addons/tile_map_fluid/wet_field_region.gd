class_name WetFieldRegion
extends RefCounted
## Bounded regional replacement over cached coverage, including removed cells and shared seams.


## Empty bounds refresh the full sparse field. Local bounds visit only nearby lattice cells.
static func pieces(coverage: WetSurfaceCoverage, previous: Dictionary[Vector2i, Array],
		area: Rect2, spacing: float, origin: Vector2,
		seam_neighbors: bool = true) -> Dictionary[Vector2i, Array]:
	var result: Dictionary[Vector2i, Array] = {}
	if not area.has_area():
		for cell: Vector2i in previous:
			result[cell] = coverage.pieces(cell)
		for cell: Vector2i in coverage.cells():
			result[cell] = coverage.pieces(cell)
		return result
	if not coverage.bounds.intersects(area, true):
		# Removed edge tiles can lie outside the new coverage envelope.
		for cell: Vector2i in previous:
			var rect: Rect2 = Rect2(origin + Vector2(cell) * spacing, Vector2.ONE * spacing)
			if rect.intersects(area, true):
				result[cell] = coverage.pieces(cell)
		return result
	var first: Vector2i = Vector2i(((area.position - origin) / spacing).floor())
	var end: Vector2i = Vector2i(((area.end - origin) / spacing).ceil())
	if seam_neighbors:
		first -= Vector2i.ONE
		end += Vector2i.ONE * 2
	for y: int in range(first.y, end.y):
		for x: int in range(first.x, end.x):
			var cell: Vector2i = Vector2i(x, y)
			if previous.has(cell) or not coverage.pieces(cell).is_empty():
				result[cell] = coverage.pieces(cell)
	return result
