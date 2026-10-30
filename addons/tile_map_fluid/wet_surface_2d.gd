class_name WetSurface2D
extends Node2D
## TileMapLayer child contract. Its node transform never changes the layer-local field space.

## Saturation changed; optional visuals and movement adapters may consume the same field.
signal changed
## Coverage changed in WORLD coordinates; empty bounds mean a full refresh.
signal coverage_changed(world_bounds: Rect2)

## Vanilla layer supplying coordinates and default tile coverage; no subclass is required.
@export var tile_layer: TileMapLayer
## Optional composed/clipped coverage supplied by the host game.
@export var coverage_provider: WetCoverageProvider2D
## Dedicated child backend; use WetGridSimulation for the reusable clipped field.
@export var simulation: WetSurfaceSimulation
## Read-only shared tuning; each surface owns its own runtime simulation and coverage snapshot.
@export var settings: WetSurfaceSettings = WetSurfaceSettings.new()

var _coverage: WetSurfaceCoverage = WetSurfaceCoverage.new()
var _dirty: bool = true
var _pose: Transform2D
var _bound_layer: TileMapLayer
var _bound_provider: WetCoverageProvider2D
var _bound_simulation: WetSurfaceSimulation


func _enter_tree() -> void:
	_dirty = true
	_bind()


func _ready() -> void:
	_bind()
	refresh_coverage()


func _exit_tree() -> void:
	_disconnect()


func _physics_process(delta: float) -> void:
	if is_finite(delta) and delta > 0.0 and validation_error().is_empty():
		simulation.advance(delta, settings.dry_seconds)


## Returns an actionable configuration problem; an unbound backend cannot accept deposits.
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


## Refresh after a batch of cell edits. TileMapLayer.changed is not a per-cell notification.
## Coverage-only use is supported before a simulation backend has been attached.
func refresh_coverage(world_bounds: Rect2 = Rect2(), configure_backend: bool = true) -> bool:
	_bind()
	_dirty = false
	var layer: TileMapLayer = tile_layer if is_instance_valid(tile_layer) else null
	var provider: WetCoverageProvider2D = coverage_provider \
		if is_instance_valid(coverage_provider) else null
	# A freed typed Node cannot even be passed to another typed API in GDScript.
	if coverage_provider != null and provider == null:
		layer = null
	var valid: bool = _coverage.rebuild(layer, settings, provider)
	if is_instance_valid(tile_layer):
		_pose = tile_layer.global_transform
	if configure_backend and is_instance_valid(simulation) and simulation.get_parent() == self:
		simulation.configure(_coverage, _pose, settings)
	coverage_changed.emit(world_bounds)
	return valid and (not is_instance_valid(simulation) or simulation.validation_error().is_empty())


## WORLD point and normalized saturation dose. Invalid/negative/zero input is ignored.
func deposit(world_point: Vector2, dose: float) -> bool:
	if not world_point.is_finite() or not is_finite(dose) or dose <= 0.0:
		return false
	if not _ensure_coverage() or not validation_error().is_empty():
		return false
	var local: Vector2 = tile_layer.to_local(world_point)
	return simulation.deposit(local, minf(dose, 1.0)) if _coverage.contains(local) else false


## One union stamp, with one dose per field sample, regardless of overlapping shapes.
func stamp(footprint: WaterFootprint2D, dose: float, source: Vector2,
		obstacle_mask: int, exclusions: Array[RID] = []) -> bool:
	if footprint == null or not source.is_finite() or not is_finite(dose) or dose <= 0.0:
		return false
	if not _ensure_coverage() or not validation_error().is_empty() \
			or not footprint.validation_error().is_empty():
		return false
	if not is_inside_tree() or not footprint.is_inside_tree() \
			or get_world_2d() != footprint.get_world_2d():
		return false
	return simulation.stamp(footprint, minf(dose, 1.0), source, obstacle_mask, exclusions)


## WORLD-space saturation for traction. No traction policy or object tint is imposed.
func saturation_at(world_point: Vector2) -> float:
	if not world_point.is_finite() or not _ensure_coverage() \
			or not validation_error().is_empty():
		return 0.0
	var local: Vector2 = tile_layer.to_local(world_point)
	var value: float = simulation.sample(local) if _coverage.contains(local) else 0.0
	return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0


## Coverage query remains useful without a simulation backend.
func contains_world_point(world_point: Vector2) -> bool:
	return world_point.is_finite() and _ensure_coverage() \
		and _coverage.contains(tile_layer.to_local(world_point))


func _ensure_coverage() -> bool:
	if is_inside_tree() and is_instance_valid(tile_layer) and tile_layer.is_inside_tree() \
			and tile_layer.get_world_2d() != get_world_2d():
		_dirty = true
		_coverage.error = "WetSurface2D must share the referenced layer's World2D."
		return false
	if tile_layer != _bound_layer or coverage_provider != _bound_provider \
			or simulation != _bound_simulation:
		_dirty = true
	if not is_instance_valid(tile_layer) or (coverage_provider != null \
			and not is_instance_valid(coverage_provider)):
		_dirty = true
	if is_instance_valid(tile_layer) and _pose != tile_layer.global_transform:
		_dirty = true
	if _dirty:
		refresh_coverage()
	return _coverage.error.is_empty() and settings != null \
		and settings.validation_error().is_empty()


func _invalidate(world_bounds: Rect2 = Rect2()) -> void:
	_dirty = true
	coverage_changed.emit(world_bounds)


func _on_changed() -> void:
	changed.emit()


func _bind() -> void:
	if tile_layer == _bound_layer and coverage_provider == _bound_provider \
			and simulation == _bound_simulation:
		return
	_disconnect()
	_bound_layer = tile_layer
	_bound_provider = coverage_provider
	_bound_simulation = simulation
	if is_instance_valid(_bound_layer):
		_bound_layer.changed.connect(_invalidate)
	if is_instance_valid(_bound_provider):
		_bound_provider.coverage_changed.connect(_invalidate)
	if is_instance_valid(_bound_simulation):
		_bound_simulation.changed.connect(_on_changed)


func _disconnect() -> void:
	if is_instance_valid(_bound_layer) and _bound_layer.changed.is_connected(_invalidate):
		_bound_layer.changed.disconnect(_invalidate)
	if is_instance_valid(_bound_provider) \
			and _bound_provider.coverage_changed.is_connected(_invalidate):
		_bound_provider.coverage_changed.disconnect(_invalidate)
	if is_instance_valid(_bound_simulation) and _bound_simulation.changed.is_connected(_on_changed):
		_bound_simulation.changed.disconnect(_on_changed)
	_bound_layer = null
	_bound_provider = null
	_bound_simulation = null
