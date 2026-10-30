class_name WetSurfaceCoverage
extends RefCounted
## A surface-owned snapshot. Never writes TileSet, TileData, or settings resources.

## Filled polygons and envelope in the referenced TileMapLayer's coordinates.
var polygons: Array[PackedVector2Array] = []
## Includes potential provider openings even while their coverage is closed.
var bounds: Rect2
## Nonempty when coverage could not be built. Invalid configurations fail closed.
var error: String = ""


## Reads vanilla rectangular atlas tiles, or delegates composed geometry to a typed provider.
func rebuild(layer: TileMapLayer, settings: WetSurfaceSettings,
		provider: WetCoverageProvider2D = null) -> bool:
	polygons.clear()
	bounds = Rect2()
	error = _configuration_error(layer, settings, provider)
	if not error.is_empty():
		return false
	var inverse: Transform2D = layer.global_transform.affine_inverse()
	if provider != null:
		for polygon: PackedVector2Array in provider.world_polygons():
			if not _append_polygon(inverse * polygon):
				return false
		var envelope: Rect2 = provider.world_envelope()
		if not envelope.position.is_finite() or not envelope.size.is_finite():
			return _fail("Coverage provider envelope must be finite.")
		if envelope.has_area():
			_expand_bounds(inverse * rectangle(envelope))
		return true
	if not layer.enabled:
		return true
	var key: int = layer.tile_set.get_custom_data_layer_by_name(settings.receives_water_key) \
		if not settings.receives_water_key.is_empty() else -1
	for cell: Vector2i in layer.get_used_cells():
		var data: TileData = layer.get_cell_tile_data(cell)
		if data == null:
			return _fail("WetSurface2D supports atlas tiles; scene tiles need a coverage provider.")
		var receives: bool = bool(data.get_custom_data_by_layer_id(key)) if key >= 0 \
			else settings.receives_water_by_default
		if receives:
			var size: Vector2 = layer.tile_set.tile_size
			_append_polygon(rectangle(Rect2(layer.map_to_local(cell) - size * 0.5, size)))
	return true


## The same local coverage gate applies to queries and point deposits, including holes.
func contains(point: Vector2) -> bool:
	if not error.is_empty() or not point.is_finite():
		return false
	for polygon: PackedVector2Array in polygons:
		if Geometry2D.is_point_in_polygon(point, polygon):
			return true
	return false


## Shared rectangle conversion also transforms all four corners of provider envelopes.
static func rectangle(area: Rect2) -> PackedVector2Array:
	return PackedVector2Array([area.position, Vector2(area.end.x, area.position.y),
		area.end, Vector2(area.position.x, area.end.y)])


static func _configuration_error(layer: TileMapLayer, settings: WetSurfaceSettings,
		provider: WetCoverageProvider2D) -> String:
	if not is_instance_valid(layer) or settings == null:
		return "WetSurface2D requires a TileMapLayer reference and settings."
	if provider != null and not is_instance_valid(provider):
		return "WetSurface2D coverage provider was freed."
	if provider != null and layer.is_inside_tree() and provider.is_inside_tree() \
			and layer.get_world_2d() != provider.get_world_2d():
		return "WetSurface2D coverage provider must share the layer's World2D."
	var pose: Transform2D = layer.global_transform
	if not pose.is_finite() or is_zero_approx(pose.determinant()):
		return "WetSurface2D requires a finite, invertible layer transform."
	var issue: String = settings.validation_error()
	if not issue.is_empty() or provider != null:
		return issue
	if layer.tile_set == null:
		return "WetSurface2D requires a TileSet or a coverage provider."
	if layer.tile_set.tile_shape != TileSet.TILE_SHAPE_SQUARE \
			or layer.tile_set.tile_layout != TileSet.TILE_LAYOUT_STACKED:
		return "WetSurface2D supports rectangular stacked tiles; use a coverage provider otherwise."
	var key: int = layer.tile_set.get_custom_data_layer_by_name(settings.receives_water_key) \
		if not settings.receives_water_key.is_empty() else -1
	if key >= 0 and layer.tile_set.get_custom_data_layer_type(key) != TYPE_BOOL:
		return "WetSurface2D water custom data must be boolean."
	return ""


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
	var area: Rect2 = Rect2(polygon[0], Vector2.ZERO)
	for point: Vector2 in polygon:
		area = area.expand(point)
	bounds = bounds.merge(area) if bounds.has_area() else area


func _fail(message: String) -> bool:
	error = message
	polygons.clear()
	bounds = Rect2()
	return false
