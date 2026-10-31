class_name TileFluidGridStamp
extends RefCounted
## Union footprint contacts and visibility, independent of field ownership and saturation.


## Select intersecting patches before testing the exact footprint union and visibility.
static func contacts(field: TileFluidFieldStorage, pose: Transform2D, footprint: TileFluidFootprint2D,
		source: Vector2, mask: int, exclusions: Array[RID]) -> Dictionary[int, bool]:
	var envelope: Rect2 = TileFluidFieldPolygons.bounds(pose.affine_inverse() *
		TileFluidSurfaceCoverage.rectangle(footprint.world_bounds()))
	var result: Dictionary[int, bool] = {}
	for cell: Vector2i in field.cells:
		for patch: TileFluidFieldPatch in field.patches(cell):
			if patch.bounds.intersects(envelope, true):
				_collect(footprint, patch, pose, source, mask, exclusions, result)
	return result


static func _collect(footprint: TileFluidFootprint2D, patch: TileFluidFieldPatch, pose: Transform2D,
		source: Vector2, mask: int, exclusions: Array[RID], result: Dictionary[int, bool]) -> void:
	if TileFluidFootprintContacts.points(footprint, pose * patch.polygon).is_empty():
		return
	var covered: bool = false
	for point: Vector2 in patch.positions:
		covered = covered or footprint.contains_world_point(pose * point)
	for offset: int in range(patch.corners.size()):
		var point: Vector2 = pose * patch.positions[offset]
		if covered and not footprint.contains_world_point(point):
			continue
		var interior: Vector2 = pose * patch.interior(patch.positions[offset])
		if TileFluidVisibility2D.reaches(footprint.get_world_2d(), source, interior, mask, exclusions):
			result[patch.corners[offset]] = true
