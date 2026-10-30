class_name WetSurface2D
extends Node2D
## Public world-space water operations over cached tile coverage and a dedicated backend.

## Saturation changed; optional visuals and movement adapters consume the same field.
signal changed
## Coverage changed in WORLD coordinates; empty bounds mean a full refresh.
signal coverage_changed(world_bounds: Rect2)

## Vanilla layer defining field coordinates; the component's own offset does not move the field.
@export var tile_layer: TileMapLayer
## Optional composed floor sources; empty uses tile_layer. No host-generated polygons required.
@export var coverage_layers: Array[TileMapLayer] = []
## Optional custom non-tile geometry; overrides coverage_layers.
@export var coverage_provider: WetCoverageProvider2D
## Dedicated child backend; use WetGridSimulation for the reusable clipped field.
@export var simulation: WetSurfaceSimulation
## Read-only shared tuning; each surface owns its coverage and simulation snapshot.
@export var settings: WetSurfaceSettings = WetSurfaceSettings.new()

var _coverage: WetSurfaceCoverage = WetSurfaceCoverage.new()
var _binding: WetSurfaceBinding = WetSurfaceBinding.new()
var _dirty: bool = true
var _pose: Transform2D


func _enter_tree() -> void:
	_dirty = true
	_bind()


func _ready() -> void:
	refresh_coverage()


func _exit_tree() -> void:
	_binding.disconnect_from(self)


func _physics_process(delta: float) -> void:
	if is_finite(delta) and delta > 0.0 and validation_error().is_empty():
		simulation.advance(delta, settings.dry_seconds)


## Returns an actionable configuration problem; invalid surfaces cannot accept deposits.
func validation_error() -> String:
	if settings == null:
		return "WetSurface2D requires settings."
	var issue: String = settings.validation_error()
	if not issue.is_empty():
		return issue
	if not _ensure_coverage():
		return _coverage.error
	if not is_instance_valid(simulation) or simulation.get_parent() != self:
		return "WetSurface2D requires its own WetSurfaceSimulation child."
	return simulation.validation_error()


## Reindex after batched tile edits. Ordinary saturation queries never scan the whole floor.
## Hosts staging initialization may prepare coverage once before requesting individual regions.
func refresh_coverage(world_bounds: Rect2 = Rect2(), configure_backend: bool = true) -> bool:
	_bind()
	_dirty = false
	var layer: TileMapLayer = tile_layer if is_instance_valid(tile_layer) else null
	var provider: WetCoverageProvider2D = coverage_provider \
		if is_instance_valid(coverage_provider) else null
	if coverage_provider != null and provider == null:
		layer = null
	var valid: bool = _coverage.rebuild(layer, settings, provider, coverage_layers)
	if is_instance_valid(tile_layer):
		_pose = tile_layer.global_transform
	_binding.poses_changed()
	if configure_backend and is_instance_valid(simulation) and simulation.get_parent() == self:
		if valid and world_bounds.has_area():
			simulation.update_region(_coverage, _pose, settings, _local_bounds(world_bounds))
		else:
			simulation.configure(_coverage, _pose, settings)
	coverage_changed.emit(world_bounds)
	return valid and (not is_instance_valid(simulation) or simulation.validation_error().is_empty())


## Reclip only changed colliders and seam-sharing cells, reusing indexed tile coverage.
func refresh_obstacles(world_bounds: Rect2 = Rect2(), seam_neighbors: bool = true) -> bool:
	if (not _ensure_coverage()
			or not is_instance_valid(simulation)
			or simulation.get_parent() != self):
		return false
	simulation.update_region(
		_coverage,
		_pose,
		settings,
		_local_bounds(world_bounds),
		seam_neighbors,
	)
	coverage_changed.emit(world_bounds)
	return simulation.validation_error().is_empty()


## Read-only local floor envelope, independent of the amount of water or collision clipping.
func coverage_bounds() -> Rect2:
	return _coverage.bounds if _ensure_coverage() else Rect2()


## WORLD point and normalized saturation dose. Invalid/negative/zero input is ignored.
func deposit(world_point: Vector2, dose: float) -> bool:
	if not world_point.is_finite() or not is_finite(dose) or dose <= 0.0:
		return false
	if not validation_error().is_empty():
		return false
	var local: Vector2 = tile_layer.to_local(world_point)
	return simulation.deposit(local, minf(dose, 1.0)) if _coverage.contains(local) else false


## One union stamp, with one dose per field sample, regardless of overlapping shapes.
func stamp(footprint: WaterFootprint2D, dose: float, source: Vector2,
		obstacle_mask: int, exclusions: Array[RID] = []) -> bool:
	if footprint == null or not source.is_finite() or not is_finite(dose) or dose <= 0.0:
		return false
	if not validation_error().is_empty() or not footprint.validation_error().is_empty():
		return false
	if not is_inside_tree() or not footprint.is_inside_tree() \
			or get_world_2d() != footprint.get_world_2d():
		return false
	return simulation.stamp(footprint, minf(dose, 1.0), source, obstacle_mask, exclusions)


## Indexed world-space saturation for traction and absorption, including dry contacts.
func saturation_at(world_point: Vector2) -> float:
	if not world_point.is_finite() or not validation_error().is_empty():
		return 0.0
	var local: Vector2 = tile_layer.to_local(world_point)
	var value: float = simulation.sample(local) if _coverage.contains(local) else 0.0
	return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0


## Coverage queries use the same cached cell lookup, including custom backend surfaces.
func contains_world_point(world_point: Vector2) -> bool:
	return world_point.is_finite() and _ensure_coverage() \
		and _coverage.contains(tile_layer.to_local(world_point))


## Coalesce source change notifications until the next explicit refresh or query.
func invalidate(world_bounds: Rect2 = Rect2()) -> void:
	_dirty = true
	coverage_changed.emit(world_bounds)


## Forward backend changes without imposing gameplay reactions.
func notify_changed() -> void:
	changed.emit()


func _ensure_coverage() -> bool:
	_bind()
	if is_inside_tree() and is_instance_valid(tile_layer) and tile_layer.is_inside_tree() \
			and tile_layer.get_world_2d() != get_world_2d():
		_dirty = true
		_coverage.error = "WetSurface2D must share the referenced layer's World2D."
		return false
	if not is_instance_valid(tile_layer) or (coverage_provider != null \
			and not is_instance_valid(coverage_provider)):
		_dirty = true
	if is_instance_valid(tile_layer) and _pose != tile_layer.global_transform:
		_dirty = true
	if _dirty:
		refresh_coverage()
	return _coverage.error.is_empty() and settings != null \
		and settings.validation_error().is_empty()


func _bind() -> void:
	_dirty = _binding.synchronize(self) or _dirty
	_dirty = _binding.poses_changed() or _dirty


func _local_bounds(world_bounds: Rect2) -> Rect2:
	return WetFieldPolygons.bounds(_pose.affine_inverse() *
		WetSurfaceCoverage.rectangle(world_bounds)) if world_bounds.has_area() else Rect2()
