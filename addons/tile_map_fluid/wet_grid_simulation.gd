class_name WetGridSimulation
extends WetSurfaceSimulation
## Reusable clipped bilinear field. All field coordinates belong to the referenced TileMapLayer.

## Cells actually replaced; presenters and diagnostics can retain all distant geometry.
signal geometry_changed(cells: Array[Vector2i])
## Full replacement, including removed cells absent from the new coverage list.
signal geometry_replaced

## Allocated saturation contacts; fixed between coverage refreshes, independent of emission count.
var sample_count: int:
	get:
		return _field.water.size()
## Covered lattice cells; holes and disconnected empty regions allocate no storage.
var cell_count: int:
	get:
		return _field.cells.size()
## Changes only when coverage is rebuilt; presentation uploads never rebuild floor physics.
var geometry_revision: int = 0
var _field: WetFieldStorage = WetFieldStorage.new()
var _error: String = ""
var _pose: Transform2D = Transform2D.IDENTITY
var _spacing: float = 32.0
var _origin: Vector2 = Vector2.ZERO


## Actionable configuration failures propagate through WetSurface2D.validation_error().
func validation_error() -> String:
	return _error


## Reclip coverage and physics barriers, preserving unchanged patches on a stable local lattice.
func configure(coverage: WetSurfaceCoverage, pose: Transform2D,
		settings: WetSurfaceSettings) -> void:
	var preserve: bool = settings != null and _spacing == settings.sample_spacing \
		and _origin == settings.sample_origin
	_field.begin_rebuild(preserve)
	_pose = pose
	if settings == null or not settings.validation_error().is_empty():
		_error = "WetGridSimulation requires valid WetSurfaceSettings."
	else:
		_error = coverage.error
		_spacing = settings.sample_spacing
		_origin = settings.sample_origin
		var world: World2D = _world()
		for cell: Vector2i in coverage.cells() if _error.is_empty() else []:
			var rect: Rect2 = Rect2(_origin + Vector2(cell) * _spacing, Vector2.ONE * _spacing)
			_field.add_cell(cell, WetFieldObstacles.clip(world, _pose, rect,
				settings.obstacle_mask, coverage.pieces(cell)))
	_field.end_rebuild()
	geometry_revision += 1
	geometry_replaced.emit()
	geometry_changed.emit(coverage.cells())
	changed.emit()


## Reuse indexed coverage and preserve distant patch identities across collider/tile changes.
func update_region(coverage: WetSurfaceCoverage, pose: Transform2D,
		settings: WetSurfaceSettings, area: Rect2, seam_neighbors: bool = true) -> void:
	if not coverage.error.is_empty() or _spacing != settings.sample_spacing \
			or _origin != settings.sample_origin or _pose != pose:
		configure(coverage, pose, settings)
		return
	var pieces: Dictionary[Vector2i, Array] = WetFieldRegion.pieces(
		coverage, _field.cells, area, _spacing, _origin, seam_neighbors)
	if not pieces.is_empty():
		_error = ""
		replace_cells(pieces, pose, settings)


## Host-batched local geometry replacement; untouched patches and renderer references survive.
## Pieces and rectangles use layer coordinates. Call after updating the surface coverage snapshot.
func replace_cells(pieces: Dictionary[Vector2i, Array], pose: Transform2D,
		settings: WetSurfaceSettings) -> void:
	_pose = pose
	_spacing = settings.sample_spacing
	_origin = settings.sample_origin
	_field.begin_replace(pieces.keys())
	for cell: Vector2i in pieces:
		var rect: Rect2 = Rect2(_origin + Vector2(cell) * _spacing, Vector2.ONE * _spacing)
		var polygons: Array[PackedVector2Array] = []
		polygons.assign(pieces[cell])
		_field.add_cell(cell, WetFieldObstacles.clip(_world(), pose, rect,
			settings.obstacle_mask, polygons))
	_field.end_rebuild()
	geometry_revision += 1
	geometry_changed.emit(pieces.keys())
	changed.emit()


## Clear water/geometry; optional settings prime an empty lattice for staged regional preparation.
func reset(settings: WetSurfaceSettings = null, pose: Transform2D = Transform2D.IDENTITY) -> void:
	_field.begin_rebuild(false)
	if settings != null:
		_spacing = settings.sample_spacing
		_origin = settings.sample_origin
		_pose = pose
	_error = ""
	geometry_revision += 1
	geometry_replaced.emit()
	changed.emit()


## Read-only occupancy diagnostic, independent of presentation and dry field queries.
func has_water() -> bool:
	return _field.has_water()


## Radius deposits retain the original game's soft-edged splash without allocating contacts.
func splash(point: Vector2, dose: float, radius: float, obstacle_mask: int) -> bool:
	if not _valid_dose(point, dose) or not is_finite(radius) or radius <= 0.0:
		return false
	var applied: bool = WetGridSplash.apply(_field, _pose, _world(), point, dose, radius,
		obstacle_mask, Rect2i(_cell(point - Vector2.ONE * radius),
		_cell(point + Vector2.ONE * radius) - _cell(point - Vector2.ONE * radius) + Vector2i.ONE))
	if applied:
		changed.emit()
	return applied


## Sparse layer-local cells for optional batched presentation. Treat returned patches as read-only.
func covered_cells() -> Array[Vector2i]:
	return _field.cells.keys()


## Connected clipped geometry, stable until geometry_revision changes.
func cell_patches(cell: Vector2i) -> Array[WetFieldPatch]:
	return _field.patches(cell)


## Four bilinear corner values shared by rendering and gameplay interpolation.
func patch_water(patch: WetFieldPatch) -> Color:
	return patch.water(_field.water)


## Independent float32 snapshot; callers cannot mutate gameplay or retain its live storage.
func saturation_buffer() -> PackedFloat32Array:
	return _field.water.duplicate()


## A point wets its containing interpolation patch, so tiny deposits cannot miss lattice corners.
func deposit(point: Vector2, dose: float) -> bool:
	if not _valid_dose(point, dose):
		return false
	var additions: Dictionary[int, bool] = {}
	for patch: WetFieldPatch in _field.patches(_cell(point)):
		if Geometry2D.is_point_in_polygon(point, patch.polygon):
			for corner: int in patch.corners:
				additions[corner] = true
	return _apply(additions, minf(dose, 1.0))


## Union stamping visits each covered contact once; tiny footprints wet intersected patches.
func stamp(footprint: WaterFootprint2D, dose: float, source: Vector2,
		obstacle_mask: int, exclusions: Array[RID]) -> bool:
	if footprint == null or not _valid_dose(source, dose) \
			or not footprint.validation_error().is_empty():
		return false
	var additions: Dictionary[int, bool] = WetGridStamp.contacts(
		_field, _pose, footprint, source, obstacle_mask, exclusions)
	return _apply(additions, minf(dose, 1.0))


## Same projected-corner bilinear interpolation as the original simulation.
func sample(point: Vector2) -> float:
	if not point.is_finite() or not _field.has_water():
		return 0.0
	for patch: WetFieldPatch in _field.patches(_cell(point)):
		if Geometry2D.is_point_in_polygon(point, patch.polygon):
			return patch.sample(point, _field.water)
	return 0.0


## Scaled seconds, with zero disabling evaporation; dry fields take the constant-time path.
func advance(delta: float, dry_seconds: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or not is_finite(dry_seconds) \
			or dry_seconds <= 0.0 or not _field.has_water():
		return
	_field.evaporate(delta / dry_seconds)
	changed.emit()


func _apply(additions: Dictionary[int, bool], dose: float) -> bool:
	for corner: int in additions:
		_field.set_water(corner, _field.water[corner] + dose)
	if not additions.is_empty():
		changed.emit()
	return not additions.is_empty()


func _valid_dose(point: Vector2, dose: float) -> bool:
	return point.is_finite() and is_finite(dose) and dose > 0.0 and _error.is_empty()


func _cell(point: Vector2) -> Vector2i:
	return Vector2i(((point - _origin) / _spacing).floor())
