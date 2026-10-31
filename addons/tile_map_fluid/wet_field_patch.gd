class_name TileFluidFieldPatch
extends RefCounted

## Connected floor within one grid cell; a wall can split a cell into independent patches.
var polygon: PackedVector2Array
## Interpolation domain, trimmed to this patch rather than discarding a boundary cell.
var bounds: Rect2
## Shared field indices for the four projected interpolation samples.
var corners: PackedInt32Array = []
## Actual floor contacts used for radius and visibility checks.
var positions: PackedVector2Array = []


## Clips interpolation contacts to floor; virtual corners cannot reach across a solid wall.
func configure(outline: PackedVector2Array) -> void:
	polygon = outline
	bounds = TileFluidFieldPolygons.bounds(polygon)
	for point: Vector2 in TileFluidFieldPolygons.rectangle(bounds):
		positions.append(TileFluidFieldPolygons.nearest(point, polygon))
	# The shader and gameplay use top-left, top-right, bottom-left, bottom-right.
	var bottom_right: Vector2 = positions[2]
	positions[2] = positions[3]
	positions[3] = bottom_right


## Reads exactly the same four shared values sent to the patch artwork.
func water(values: PackedFloat32Array) -> Color:
	return Color(values[corners[0]], values[corners[1]], values[corners[2]], values[corners[3]])


## Bilinear saturation applies only inside this connected floor polygon.
func sample(point: Vector2, values: PackedFloat32Array) -> float:
	if not Geometry2D.is_point_in_polygon(point, polygon):
		return 0.0
	var fraction: Vector2 = (point - bounds.position) / bounds.size
	var saturation: Color = water(values)
	return lerpf(lerpf(saturation.r, saturation.g, fraction.x),
		lerpf(saturation.b, saturation.a, fraction.x), fraction.y)


## Physics rays end just inside the patch so touching the wall never rejects exposed floor.
func interior(point: Vector2) -> Vector2:
	var center: Vector2 = Vector2.ZERO
	for vertex: Vector2 in polygon:
		center += vertex
	center /= float(polygon.size())
	return point.move_toward(center, 0.02)
