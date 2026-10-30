class_name WetPatchSnapshot
extends RefCounted
## Short-lived geometry-edit history; never seeds newly exposed floor from a wet neighbor.

## Previous connected floor patch, treated as immutable while rebuilding.
var patch: WetFieldPatch
## Four captured values survive released/reused field slots.
var water: Color


## Retain a patch only when all its coverage already existed in this connected old patch.
func contains(polygon: PackedVector2Array) -> bool:
	return Geometry2D.clip_polygons(polygon, patch.polygon).is_empty()


## Resample surviving floor when clipping shrinks its interpolation domain.
func sample(points: PackedVector2Array) -> Color:
	var result: Color = Color(0, 0, 0, 0)
	for index: int in range(points.size()):
		var fraction: Vector2 = (points[index] - patch.bounds.position) / patch.bounds.size
		result[index] = lerpf(lerpf(water.r, water.g, fraction.x),
			lerpf(water.b, water.a, fraction.x), fraction.y)
	return result
