class_name WetGridSimulation
extends WetSurfaceSimulation
## Reusable clipped bilinear field. All field coordinates belong to the referenced TileMapLayer.

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
var _layout: WetFieldLayout = WetFieldLayout.new()
var _pose: Transform2D = Transform2D.IDENTITY
var _spacing: float = 32.0
var _origin: Vector2 = Vector2.ZERO


## Actionable configuration failures propagate through WetSurface2D.validation_error().
func validation_error() -> String:
	return _layout.error


## Reclip coverage and physics barriers, preserving unchanged patches on a stable local lattice.
func configure(coverage: WetSurfaceCoverage, pose: Transform2D,
		settings: WetSurfaceSettings) -> void:
	var preserve: bool = settings != null and _spacing == settings.sample_spacing \
		and _origin == settings.sample_origin
	_field.begin_rebuild(preserve)
	_pose = pose
	if settings == null or not settings.validation_error().is_empty():
		_layout.cells.clear()
		_layout.error = "WetGridSimulation requires valid WetSurfaceSettings."
	else:
		_spacing = settings.sample_spacing
		_origin = settings.sample_origin
		_layout.build(coverage, _spacing, settings.maximum_cells, _origin)
		var world: World2D = _world()
		for cell: Vector2i in _layout.cells:
			var rect: Rect2 = Rect2(_origin + Vector2(cell) * _spacing, Vector2.ONE * _spacing)
			_field.add_cell(cell, WetFieldObstacles.clip(world, _pose, rect,
				settings.obstacle_mask, _layout.cells[cell]))
	_field.end_rebuild()
	_layout.cells.clear()
	geometry_revision += 1
	changed.emit()


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
	changed.emit()


## Clear geometry and water when a host deliberately rebuilds rather than edits live coverage.
func reset() -> void:
	_field.begin_rebuild(false)
	_layout.error = ""
	geometry_revision += 1
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
	var envelope: Rect2 = WetFieldPolygons.bounds(_pose.affine_inverse() *
		WetSurfaceCoverage.rectangle(footprint.world_bounds()))
	var additions: Dictionary[int, bool] = {}
	for cell: Vector2i in _field.cells:
		var rect: Rect2 = Rect2(_origin + Vector2(cell) * _spacing, Vector2.ONE * _spacing)
		if not rect.intersects(envelope, true):
			continue
		for patch: WetFieldPatch in _field.patches(cell):
			_stamp_patch(footprint, patch, source, obstacle_mask, exclusions, additions)
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


## Clip the exact union first, then deduplicate projected contacts and test their visibility.
func _stamp_patch(footprint: WaterFootprint2D, patch: WetFieldPatch, source: Vector2,
		mask: int, exclusions: Array[RID], additions: Dictionary[int, bool]) -> void:
	var contacts: PackedVector2Array = WetFootprintContacts.points(footprint, _pose * patch.polygon)
	if contacts.is_empty():
		return
	var covered: bool = false
	for point: Vector2 in patch.positions:
		covered = covered or footprint.contains_world_point(_pose * point)
	for offset: int in range(patch.corners.size()):
		var point: Vector2 = _pose * patch.positions[offset]
		if covered and not footprint.contains_world_point(point):
			continue
		# Match the original subcell stamp behavior, without letting virtual rectangle
		# corners reach through a wall. Test visibility just inside the actual floor.
		var interior: Vector2 = _pose * patch.interior(patch.positions[offset])
		if WaterVisibility2D.reaches(footprint.get_world_2d(), source, interior, mask, exclusions):
			additions[patch.corners[offset]] = true


func _apply(additions: Dictionary[int, bool], dose: float) -> bool:
	for corner: int in additions:
		_field.set_water(corner, _field.water[corner] + dose)
	if not additions.is_empty():
		changed.emit()
	return not additions.is_empty()


func _valid_dose(point: Vector2, dose: float) -> bool:
	return point.is_finite() and is_finite(dose) and dose > 0.0 and _layout.error.is_empty()


func _cell(point: Vector2) -> Vector2i:
	return Vector2i(((point - _origin) / _spacing).floor())


func _world() -> World2D:
	var surface: WetSurface2D = get_parent() as WetSurface2D
	return surface.get_world_2d() if surface != null and surface.is_inside_tree() else null
