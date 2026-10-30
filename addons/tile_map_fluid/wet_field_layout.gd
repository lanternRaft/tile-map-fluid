class_name WetFieldLayout
extends RefCounted
## Sparse coverage buckets on a fixed layer-local lattice; envelopes do not allocate empty cells.

## Clipped, nonoverlapping filled polygons per covered cell.
var cells: Dictionary[Vector2i, Array] = {}
## Oversized layouts fail closed instead of allocating unbounded fields.
var error: String = ""
var _empty: Array[PackedVector2Array] = []


## Index only authored polygons, merging overlapping supporting layers before obstacle clipping.
func build(coverage: WetSurfaceCoverage, spacing: float, maximum: int,
		origin: Vector2 = Vector2.ZERO) -> void:
	cells.clear()
	error = coverage.error
	if not error.is_empty():
		return
	for polygon: PackedVector2Array in coverage.polygons:
		var bounds: Rect2 = WetFieldPolygons.bounds(polygon)
		var first: Vector2i = Vector2i(((bounds.position - origin) / spacing).floor())
		var end: Vector2i = Vector2i(((bounds.end - origin) / spacing).ceil())
		var size: Vector2i = end - first
		if float(size.x) * float(size.y) > maximum:
			_fail()
			return
		for y: int in range(first.y, end.y):
			for x: int in range(first.x, end.x):
				var cell: Vector2i = Vector2i(x, y)
				var rect: Rect2 = Rect2(origin + Vector2(cell) * spacing, Vector2.ONE * spacing)
				var pieces: Array[PackedVector2Array] = cells.get(cell, _empty).duplicate()
				for clipped: PackedVector2Array in Geometry2D.intersect_polygons(
						WetSurfaceCoverage.rectangle(rect), polygon):
					var additions: Array[PackedVector2Array] = [clipped]
					for existing: PackedVector2Array in pieces:
						additions = WetFieldPolygons.subtract(additions, existing)
					pieces.append_array(additions)
				if not pieces.is_empty():
					cells[cell] = pieces
				if cells.size() > maximum:
					_fail()
					return


func _fail() -> void:
	cells.clear()
	error = "WetSurfaceSimulation coverage exceeds WetSurfaceSettings.maximum_cells."
