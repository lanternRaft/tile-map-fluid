class_name WetSurfaceCoverage
extends RefCounted
## Surface-owned coverage, indexed once per edit on the simulation's local lattice.

## Filled source polygons; backends consume the cached cell pieces instead of rescanning them.
var polygons: Array[PackedVector2Array] = []
## Includes potential provider openings even while their coverage is closed.
var bounds: Rect2
## Invalid configurations fail closed, including the spatial-index allocation limit.
var error: String = ""
var _index: WetFieldLayout = WetFieldLayout.new()
var _spacing: float = 32.0
var _origin: Vector2 = Vector2.ZERO
var _empty: Array[PackedVector2Array] = []


## Compose occupied floor tiles directly; optional providers support non-tile custom geometry.
func rebuild(layer: TileMapLayer, settings: WetSurfaceSettings,
		provider: WetCoverageProvider2D = null, sources: Array[TileMapLayer] = []) -> bool:
	polygons.clear()
	bounds = Rect2()
	_index.cells.clear()
	error = ""
	if not is_instance_valid(layer) or settings == null:
		return _fail("WetSurface2D requires a TileMapLayer reference and settings.")
	if (not layer.global_transform.is_finite()
			or is_zero_approx(layer.global_transform.determinant())):
		return _fail("WetSurface2D requires a finite, invertible layer transform.")
	error = settings.validation_error()
	if not error.is_empty():
		return false
	var inverse: Transform2D = layer.global_transform.affine_inverse()
	if provider != null:
		if not is_instance_valid(provider) or not _same_world(layer, provider):
			return _fail("WetSurface2D coverage provider must share the layer's World2D.")
		for polygon: PackedVector2Array in provider.world_polygons():
			if not _append_polygon(inverse * polygon):
				return false
		var envelope: Rect2 = provider.world_envelope()
		if not envelope.position.is_finite() or not envelope.size.is_finite():
			return _fail("Coverage provider envelope must be finite.")
		if envelope.has_area():
			_expand_bounds(inverse * rectangle(envelope))
	else:
		var layers: Array[TileMapLayer] = sources.duplicate()
		if layers.is_empty():
			layers.append(layer)
		for source: TileMapLayer in layers:
			if not _append_layer(source, layer, inverse, settings):
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


## Shared rectangle conversion transforms all four corners of tile/provider envelopes.
static func rectangle(area: Rect2) -> PackedVector2Array:
	return PackedVector2Array([area.position, Vector2(area.end.x, area.position.y),
		area.end, Vector2(area.position.x, area.end.y)])


func _append_layer(source: TileMapLayer, layer: TileMapLayer, inverse: Transform2D,
		settings: WetSurfaceSettings) -> bool:
	if not is_instance_valid(source) or not _same_world(layer, source):
		return _fail("WetSurface2D coverage layers must share the coordinate layer's World2D.")
	if not source.enabled:
		return true
	if source.tile_set == null:
		return _fail("WetSurface2D requires a TileSet or a coverage provider.")
	if source.tile_set.tile_shape != TileSet.TILE_SHAPE_SQUARE \
			or source.tile_set.tile_layout != TileSet.TILE_LAYOUT_STACKED:
		return _fail("WetSurface2D supports rectangular stacked tiles; use a coverage provider.")
	if (not source.global_transform.is_finite()
			or is_zero_approx(source.global_transform.determinant())):
		return _fail("WetSurface2D requires finite, invertible coverage layer transforms.")
	var key: int = source.tile_set.get_custom_data_layer_by_name(settings.receives_water_key) \
		if not settings.receives_water_key.is_empty() else -1
	if key >= 0 and source.tile_set.get_custom_data_layer_type(key) != TYPE_BOOL:
		return _fail("WetSurface2D water custom data must be boolean.")
	var pose: Transform2D = Transform2D.IDENTITY if source == layer \
		else inverse * source.global_transform
	for cell: Vector2i in source.get_used_cells():
		var data: TileData = source.get_cell_tile_data(cell)
		if data == null:
			return _fail("WetSurface2D supports atlas tiles; scene tiles need a coverage provider.")
		var receives: bool = bool(data.get_custom_data_by_layer_id(key)) if key >= 0 \
			else settings.receives_water_by_default
		if receives:
			var size: Vector2 = source.tile_set.tile_size
			var rect: Rect2 = Rect2(source.map_to_local(cell) - size * 0.5, size)
			if not _append_polygon(pose * rectangle(rect)):
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
	var area: Rect2 = WetFieldPolygons.bounds(polygon)
	bounds = bounds.merge(area) if bounds.has_area() else area


func _fail(message: String) -> bool:
	error = message
	polygons.clear()
	_index.cells.clear()
	bounds = Rect2()
	return false


func _same_world(layer: TileMapLayer, source: Node2D) -> bool:
	return not layer.is_inside_tree() or not source.is_inside_tree() \
		or layer.get_world_2d() == source.get_world_2d()
