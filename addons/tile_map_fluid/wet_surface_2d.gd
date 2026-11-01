@icon("res://addons/tile_map_fluid/assets/icons/presentation.svg")
class_name TileFluidSurface2D
extends Node2D
## Public world-space water operations over cached tile coverage and a dedicated backend.

## Saturation changed; optional visuals and movement adapters consume the same field.
signal changed
## Coverage changed in WORLD coordinates; empty bounds mean a full refresh.
signal coverage_changed(world_bounds: Rect2)

## Vanilla layer defining field coordinates; the component's own offset does not move the field.
@export var tile_layer: TileMapLayer:
	set(value):
		if tile_layer != value:
			tile_layer = value
			_sampling_valid = false
			_dirty = true
			_contact_revision += 1
## Dedicated child backend; use TileFluidGridSimulation for the reusable clipped field.
@export var simulation: TileFluidSurfaceSimulation:
	set(value):
		if simulation != value:
			simulation = value
			_sampling_valid = false
			_dirty = true
			_contact_revision += 1
## Read-only shared tuning; each surface owns its coverage and simulation snapshot.
@export var settings: TileFluidSurfaceSettings = TileFluidSurfaceSettings.new():
	set(value):
		if settings != value:
			settings = value
			_sampling_valid = false
			_dirty = true
			_contact_revision += 1
## Optional ancestor owning receivers that automatically discover this surface.
@export var contact_scope: Node
## Optional preparation/batching node; omit for the basic immediate surface lifecycle.
@export var lifecycle: TileFluidSurfaceLifecycle
## Floor artwork and upload cadence for the automatically owned renderer.
@export var appearance: TileFluidSurfaceAppearance = TileFluidSurfaceAppearance.new()
## Internal renderer; explicit assignments remain supported for existing scenes.
@export_storage var presentation: TileFluidSurfacePresentation
## Enable this surface's floor-drag response for contacting rigid bodies.
@export var traction_enabled: bool = false
## Fraction of normal floor damping at full saturation.
@export_range(0.0, 1.0, 0.01) var wet_drag_multiplier: float = 0.25
## Apply the same response to angular damping as well as linear damping.
@export var traction_affects_rotation: bool = false
## Dry-floor splash radius in layer-local pixels.
@export_range(1.0, 128.0, 1.0) var splash_initial_radius: float = 22.0
## Saturated-floor splash radius in layer-local pixels.
@export_range(1.0, 128.0, 1.0) var splash_maximum_radius: float = 32.0

var _coverage: TileFluidSurfaceCoverage = TileFluidSurfaceCoverage.new()
var _binding: TileFluidSurfaceBinding = TileFluidSurfaceBinding.new()
var _sampling_valid: bool = false
var _sampling_grid: TileFluidGridSimulation
var _sampling_geometry_revision: int = -1
var _contact_revision: int = 0
var _dirty: bool = true
var _pose: Transform2D


func _enter_tree() -> void:
	_sampling_valid = false
	add_to_group(&"wet_surfaces")
	_dirty = true
	_bind()


func _ready() -> void:
	if not is_instance_valid(simulation):
		simulation = TileFluidGridSimulation.new()
		simulation.name = "Simulation"
		add_child(simulation)
	_ensure_presentation.call_deferred()
	if lifecycle != null:
		lifecycle.initialize()
	else:
		refresh_coverage()


func _exit_tree() -> void:
	_sampling_valid = false
	_binding.disconnect_from(self)


func _physics_process(delta: float) -> void:
	if lifecycle != null and lifecycle.staged:
		return
	if is_finite(delta) and delta > 0.0 and validation_error().is_empty():
		simulation.advance(delta, settings.dry_seconds)


## Blend a body's dry floor damping using this surface's Inspector-authored response.
func traction_multiplier(saturation: float) -> float:
	return lerpf(1.0, clampf(wet_drag_multiplier, 0.0, 1.0), clampf(saturation, 0.0, 1.0)) \
		if traction_enabled and is_finite(saturation) and is_finite(wet_drag_multiplier) else 1.0


## Soft splash in world coordinates, with radius growing with local saturation.
func splash(point: Vector2, dose: float) -> bool:
	return TileFluidSurfaceWater.splash(self, point, dose,
		splash_initial_radius, splash_maximum_radius)


## Returns an actionable configuration problem; invalid surfaces cannot accept deposits.
func validation_error() -> String:
	if settings == null:
		return "TileFluidSurface2D requires settings."
	var issue: String = settings.validation_error()
	if not issue.is_empty():
		return issue
	if not _ensure_coverage(true):
		if not _coverage.error.is_empty():
			return _coverage.error
		# A synchronous geometry callback may have edited settings during preparation.
		return settings.validation_error() if settings != null else "TileFluidSurface2D requires settings."
	if not is_instance_valid(simulation) or simulation.get_parent() != self:
		return "TileFluidSurface2D requires its own TileFluidSurfaceSimulation child."
	return simulation.validation_error()


## Reindex after batched tile edits. Ordinary saturation queries never scan the whole floor.
## Hosts staging initialization may prepare coverage once before requesting individual regions.
func refresh_coverage(world_bounds: Rect2 = Rect2(), configure_backend: bool = true) -> bool:
	_sampling_valid = false
	_bind()
	_contact_revision += 1
	_dirty = false
	var layer: TileMapLayer = tile_layer if is_instance_valid(tile_layer) else null
	var valid: bool = _coverage.rebuild(layer, settings)
	if is_instance_valid(tile_layer):
		_pose = tile_layer.global_transform
	if configure_backend and is_instance_valid(simulation) and simulation.get_parent() == self:
		if valid and world_bounds.has_area():
			simulation.update_region(
				_coverage,
				_pose,
				settings,
				TileFluidSurfaceMetrics.local_bounds(_pose, world_bounds),
			)
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
		TileFluidSurfaceMetrics.local_bounds(_pose, world_bounds),
		seam_neighbors,
	)
	coverage_changed.emit(world_bounds)
	return simulation.validation_error().is_empty()


## Read-only local floor envelope, independent of the amount of water or collision clipping.
func coverage_bounds() -> Rect2:
	return _coverage.bounds if _ensure_coverage() else Rect2()


## WORLD point and normalized saturation dose. Invalid/negative/zero input is ignored.
func deposit(world_point: Vector2, dose: float) -> bool:
	return TileFluidSurfaceWater.deposit(self, world_point, dose)


## One union stamp, with one dose per field sample, regardless of overlapping shapes.
func stamp(footprint: TileFluidFootprint2D, dose: float, source: Vector2,
		obstacle_mask: int, exclusions: Array[RID] = []) -> bool:
	return TileFluidSurfaceWater.stamp(self, footprint, dose, source, obstacle_mask, exclusions)


## Indexed world-space saturation for traction and absorption, including dry contacts.
func saturation_at(world_point: Vector2) -> float:
	return TileFluidSurfaceWater.sample(self, world_point)


## Coverage queries use the same cached cell lookup, including custom backend surfaces.
func contains_world_point(world_point: Vector2) -> bool:
	return world_point.is_finite() and _ensure_coverage() \
		and _coverage.contains(tile_layer.to_local(world_point))


## Coalesce source change notifications until the next explicit refresh or query.
func invalidate(world_bounds: Rect2 = Rect2()) -> void:
	_sampling_valid = false
	_contact_revision += 1
	_dirty = true
	coverage_changed.emit(world_bounds)


## Forward backend changes without imposing gameplay reactions.
func notify_changed() -> void:
	changed.emit()


func _ensure_coverage(settings_validated: bool = false) -> bool:
	_bind()
	if is_inside_tree() and is_instance_valid(tile_layer) and tile_layer.is_inside_tree() \
			and tile_layer.get_world_2d() != get_world_2d():
		_dirty = true
		_coverage.error = "TileFluidSurface2D must share the referenced layer's World2D."
		return false
	if not is_instance_valid(tile_layer):
		_dirty = true
	if is_instance_valid(tile_layer) and _pose != tile_layer.global_transform:
		_dirty = true
	if _dirty:
		refresh_coverage(Rect2(), lifecycle == null or not lifecycle.staged)
		# Preparation emits signals: callbacks may invalidate the earlier settings check.
		settings_validated = false
	return _coverage.error.is_empty() and settings != null \
		and (settings_validated or settings.validation_error().is_empty())


func _settings_changed() -> void:
	_sampling_valid = false
	_binding.settings_changed(self)


func _invalidate_sampling() -> void:
	_sampling_valid = false


func _bind() -> void:
	if _binding.synchronize(self):
		_sampling_valid = false
		_dirty = true


func _ensure_presentation() -> void:
	if not is_inside_tree():
		return
	# Honor existing composed scenes without creating a second renderer.
	if not is_instance_valid(presentation):
		for node: Node in get_tree().root.find_children("*", "TileFluidSurfacePresentation", true, false):
			if node.surface == self:
				presentation = node
				break
	if not is_instance_valid(presentation):
		presentation = TileFluidSurfacePresentation.new()
		presentation.name = "Presentation"
		presentation.surface = self
		presentation.appearance = appearance
		# Mesh anchors must share the objects' sorting band, outside the dry floor's Z band.
		var ancestor: Node = get_parent()
		while ancestor is Node2D:
			if ancestor.y_sort_enabled:
				presentation.render_parent = ancestor
				break
			ancestor = ancestor.get_parent()
		add_child(presentation)
	if lifecycle != null:
		lifecycle.presentation = presentation


## Internal receiver query. Public saturation_at remains the fully validated reference.
## Validation runs once before preparing/reusing geometry; no final wetness is retained.
func _sample_contact(world_point: Vector2, contact: TileFluidPreparedContact) -> float:
	if not world_point.is_finite():
		contact.clear()
		return 0.0
	if _sampling_valid and (_sampling_grid.geometry_revision != _sampling_geometry_revision \
			or tile_layer.global_transform != _pose \
			or tile_layer.get_world_2d() != get_world_2d()):
		_sampling_valid = false
	if not _sampling_valid:
		var revision_before: int = _contact_revision
		if not validation_error().is_empty():
			contact.clear()
			return 0.0
		if revision_before != _contact_revision:
			# Preparation emits callbacks. Complete the reference's post-validation
			# coverage/read sequence, observing replacements without another validation.
			contact.clear()
			if not contains_world_point(world_point):
				return 0.0
			var value: float = simulation.sample(tile_layer.to_local(world_point))
			return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0
		var candidate: TileFluidGridSimulation = simulation as TileFluidGridSimulation
		if candidate == null or candidate.get_script() != TileFluidGridSimulation:
			contact.clear()
			return saturation_at(world_point)
		_sampling_grid = candidate
		_sampling_geometry_revision = candidate.geometry_revision
		_sampling_valid = is_inside_tree() and tile_layer.is_inside_tree()
	var grid: TileFluidGridSimulation = _sampling_grid
	var pose: Transform2D = _pose
	if contact.surface != self or contact.grid != grid \
			or contact.revision != _contact_revision or contact.geometry_revision != grid.geometry_revision \
			or contact.pose != pose:
		contact.clear()
		contact.surface = self
		contact.grid = grid
		contact.point = Vector2(INF, INF)
		contact.pose = pose
		contact.revision = _contact_revision
		contact.geometry_revision = grid.geometry_revision
		contact.supported = grid.get_script() == TileFluidGridSimulation
	if not contact.supported:
		return saturation_at(world_point)
	if contact.point != world_point:
		contact.point = world_point
		contact.patch_id = 0
		contact.corners = PackedInt32Array()
		var local: Vector2 = tile_layer.to_local(world_point)
		if _coverage.contains(local):
			grid.prepare_contact(local, contact)
	return grid._sample_contact_validated(contact)
