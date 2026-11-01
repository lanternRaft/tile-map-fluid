class_name TileFluidGridStamp
extends RefCounted
## Union footprint contacts and visibility, independent of field ownership and saturation.


## Select intersecting patches before testing the exact footprint union and visibility.
static func contacts(field: TileFluidFieldStorage, pose: Transform2D, footprint: TileFluidFootprint2D,
		source: Vector2, mask: int, exclusions: Array[RID], spacing: float,
		origin: Vector2) -> Dictionary[int, bool]:
	var query: TileFluidStampFootprint = TileFluidStampFootprint.new()
	if not query.configure(footprint, pose):
		return {}
	var envelope: Rect2 = query.bounds
	var world: World2D = footprint.get_world_2d()
	var result: Dictionary[int, bool] = {}
	# Include the preceding cell when the envelope touches an exact lattice boundary.
	var first: Vector2i = Vector2i(((envelope.position - origin) / spacing).ceil()) - Vector2i.ONE
	var last: Vector2i = Vector2i(((envelope.end - origin) / spacing).floor())
	var size: Vector2i = last - first + Vector2i.ONE
	if float(size.x) * float(size.y) > field.cells.size():
		# Huge footprints over sparse islands must not enumerate the empty space between them.
		for cell: Vector2i in field.cells:
			if cell.x >= first.x and cell.x <= last.x and cell.y >= first.y and cell.y <= last.y:
				_collect_cell(field, cell, query, pose, world, source, mask, exclusions, result)
	else:
		for y: int in range(first.y, last.y + 1):
			for x: int in range(first.x, last.x + 1):
				_collect_cell(field, Vector2i(x, y), query, pose, world,
					source, mask, exclusions, result)
	return result


static func _collect_cell(field: TileFluidFieldStorage, cell: Vector2i,
		query: TileFluidStampFootprint, pose: Transform2D, world: World2D, source: Vector2, mask: int,
		exclusions: Array[RID], result: Dictionary[int, bool]) -> void:
	for patch: TileFluidFieldPatch in field.patches(cell):
		if patch.bounds.intersects(query.bounds, true):
			_collect(query, patch, pose, world, source, mask, exclusions, result)


static func _collect(query: TileFluidStampFootprint, patch: TileFluidFieldPatch, pose: Transform2D,
		world: World2D, source: Vector2, mask: int, exclusions: Array[RID], result: Dictionary[int, bool]) -> void:
	if not query.overlaps(patch.polygon):
		return
	var covered: int = 0
	for offset: int in range(patch.corners.size()):
		if query.contains(patch.positions[offset]):
			covered |= 1 << offset
	for offset: int in range(patch.corners.size()):
		var corner: int = patch.corners[offset]
		if result.has(corner) or (covered != 0 and (covered & (1 << offset)) == 0):
			continue
		if mask == 0:
			result[corner] = true
			continue
		var interior: Vector2 = pose * patch.interior(patch.positions[offset])
		if TileFluidVisibility2D.reaches(world, source, interior, mask, exclusions):
			result[corner] = true
