class_name TileFluidSurfaceCoverage
extends RefCounted
## Surface-owned coverage, indexed once per edit on the simulation's local lattice.

## Filled source polygons; backends consume the cached cell pieces instead of rescanning them.
var polygons: Array[PackedVector2Array] = []
## Envelope of occupied wettable tiles.
var bounds: Rect2
## Invalid configurations fail closed, including the spatial-index allocation limit.
var error: String = ""
var _index: TileFluidFieldLayout = TileFluidFieldLayout.new()
var _spacing: float = 32.0
var _origin: Vector2 = Vector2.ZERO
var _empty: Array[PackedVector2Array] = []


## Read occupied floor tiles from the surface's assigned TileMapLayer.
func rebuild(layer: TileMapLayer, settings: TileFluidSurfaceSettings) -> bool:
	polygons.clear()
	bounds = Rect2()
	_index.cells.clear()
	error = ""
	if not is_instance_valid(layer) or settings == null:
		return _fail("TileFluidSurface2D requires a TileMapLayer reference and settings.")
	if (not layer.global_transform.is_finite()
			or is_zero_approx(layer.global_transform.determinant())):
		return _fail("TileFluidSurface2D requires a finite, invertible layer transform.")
	error = settings.validation_error()
	if not error.is_empty():
		return false
	if not _append_layer(layer, settings):
		return false
	_spacing = settings.sample_spacing
	_origin = settings.sample_origin
	_index.build(self, _spacing, settings.maximum_cells, _origin)
	error = _index.error
	return error.is_empty()


## Point queries inspect only containing-cell pieces, independent of total floor area.
func contains(point: Vector2) -> bool:
	if not error.is_empty() or not point.is_finite():
		return false
	var coordinate: Vector2 = (point - _origin) / _spacing
	var cell: Vector2i = Vector2i(coordinate.floor())
	# Filled polygons include their edges, including an outer edge on a lattice seam.
	# At a seam, consult the adjacent bucket too; the candidate count remains local.
	var first: Vector2i = cell
	if is_equal_approx(coordinate.x, float(cell.x)):
		first.x -= 1
	if is_equal_approx(coordinate.y, float(cell.y)):
		first.y -= 1
	for y: int in range(first.y, cell.y + 1):
		for x: int in range(first.x, cell.x + 1):
			for polygon: PackedVector2Array in pieces(Vector2i(x, y)):
				if Geometry2D.is_point_in_polygon(point, polygon):
					return true
	return false


## Read-only cached geometry shared by coverage checks, simulation, and regional refreshes.
func pieces(cell: Vector2i) -> Array[PackedVector2Array]:
	return _index.cells.get(cell, _empty)


## Sparse occupied cells; disconnected empty space allocates nothing.
func cells() -> Array[Vector2i]:
	return _index.cells.keys()


## Shared rectangle conversion transforms all four corners of tile envelopes.
static func rectangle(area: Rect2) -> PackedVector2Array:
	return PackedVector2Array([area.position, Vector2(area.end.x, area.position.y),
		area.end, Vector2(area.position.x, area.end.y)])


func _append_layer(source: TileMapLayer, settings: TileFluidSurfaceSettings) -> bool:
	if not source.enabled:
		return true
	if source.tile_set == null:
		return _fail("TileFluidSurface2D requires a TileSet.")
	if source.tile_set.tile_shape != TileSet.TILE_SHAPE_SQUARE \
			or source.tile_set.tile_layout != TileSet.TILE_LAYOUT_STACKED:
		return _fail("TileFluidSurface2D supports rectangular stacked tiles.")
	var key: int = source.tile_set.get_custom_data_layer_by_name(settings.receives_water_key) \
		if not settings.receives_water_key.is_empty() else -1
	if key >= 0 and source.tile_set.get_custom_data_layer_type(key) != TYPE_BOOL:
		return _fail("TileFluidSurface2D water custom data must be boolean.")
	for cell: Vector2i in source.get_used_cells():
		var data: TileData = source.get_cell_tile_data(cell)
		if data == null:
			return _fail("TileFluidSurface2D supports atlas tiles; scene tiles are unsupported.")
		var receives: bool = bool(data.get_custom_data_by_layer_id(key)) if key >= 0 \
			else settings.receives_water_by_default
		if receives:
			var size: Vector2 = source.tile_set.tile_size
			var rect: Rect2 = Rect2(source.map_to_local(cell) - size * 0.5, size)
			if not _append_polygon(rectangle(rect)):
				return false
	return true


func _append_polygon(polygon: PackedVector2Array) -> bool:
	if polygon.size() < 3:
		return _fail("Coverage polygons must have at least three finite vertices.")
	for point: Vector2 in polygon:
		if not point.is_finite():
			return _fail("Coverage polygons must have at least three finite vertices.")
	if Geometry2D.triangulate_polygon(Transform2D(0.0, -polygon[0]) * polygon).is_empty():
		return _fail("Coverage polygons must be simple filled regions.")
	polygons.append(polygon)
	_expand_bounds(polygon)
	return true


func _expand_bounds(polygon: PackedVector2Array) -> void:
	var area: Rect2 = TileFluidFieldPolygons.bounds(polygon)
	bounds = bounds.merge(area) if bounds.has_area() else area


func _fail(message: String) -> bool:
	error = message
	polygons.clear()
	_index.cells.clear()
	bounds = Rect2()
	return false
