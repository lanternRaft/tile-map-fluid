class_name WetGridStamp
extends RefCounted
## Union footprint contacts and visibility, independent of field ownership and saturation.


## Select intersecting patches before testing the exact footprint union and visibility.
static func contacts(field: WetFieldStorage, pose: Transform2D, footprint: WaterFootprint2D,
		source: Vector2, mask: int, exclusions: Array[RID]) -> Dictionary[int, bool]:
	var envelope: Rect2 = WetFieldPolygons.bounds(pose.affine_inverse() *
		WetSurfaceCoverage.rectangle(footprint.world_bounds()))
	var result: Dictionary[int, bool] = {}
	for cell: Vector2i in field.cells:
		for patch: WetFieldPatch in field.patches(cell):
			if patch.bounds.intersects(envelope, true):
				_collect(footprint, patch, pose, source, mask, exclusions, result)
	return result


static func _collect(footprint: WaterFootprint2D, patch: WetFieldPatch, pose: Transform2D,
		source: Vector2, mask: int, exclusions: Array[RID], result: Dictionary[int, bool]) -> void:
	if WetFootprintContacts.points(footprint, pose * patch.polygon).is_empty():
		return
	var covered: bool = false
	for point: Vector2 in patch.positions:
		covered = covered or footprint.contains_world_point(pose * point)
	for offset: int in range(patch.corners.size()):
		var point: Vector2 = pose * patch.positions[offset]
		if covered and not footprint.contains_world_point(point):
			continue
		var interior: Vector2 = pose * patch.interior(patch.positions[offset])
		if WaterVisibility2D.reaches(footprint.get_world_2d(), source, interior, mask, exclusions):
			result[patch.corners[offset]] = true
