@icon("res://addons/tile_map_fluid/assets/icons/presentation.svg")
class_name WetSurface2D
extends Node2D
## Public world-space water operations over cached tile coverage and a dedicated backend.

## Saturation changed; optional visuals and movement adapters consume the same field.
signal changed
## Coverage changed in WORLD coordinates; empty bounds mean a full refresh.
signal coverage_changed(world_bounds: Rect2)

## Vanilla layer defining field coordinates; the component's own offset does not move the field.
@export var tile_layer: TileMapLayer
## Dedicated child backend; use WetGridSimulation for the reusable clipped field.
@export var simulation: WetSurfaceSimulation
## Read-only shared tuning; each surface owns its coverage and simulation snapshot.
@export var settings: WetSurfaceSettings = WetSurfaceSettings.new()
## Optional ancestor owning receivers that automatically discover this surface.
@export var contact_scope: Node
## Optional preparation/batching node; omit for the basic immediate surface lifecycle.
@export var lifecycle: WetSurfaceLifecycle
## Floor artwork and upload cadence for the automatically owned renderer.
@export var appearance: WetSurfaceAppearance = WetSurfaceAppearance.new()
## Internal renderer; explicit assignments remain supported for existing scenes.
@export_storage var presentation: WetSurfacePresentation
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

var _coverage: WetSurfaceCoverage = WetSurfaceCoverage.new()
var _binding: WetSurfaceBinding = WetSurfaceBinding.new()
var _dirty: bool = true
var _pose: Transform2D


func _enter_tree() -> void:
	add_to_group(&"wet_surfaces")
	_dirty = true
	_bind()


func _ready() -> void:
	if not is_instance_valid(simulation):
		simulation = WetGridSimulation.new()
		simulation.name = "Simulation"
		add_child(simulation)
	_ensure_presentation.call_deferred()
	if lifecycle != null:
		lifecycle.initialize()
	else:
		refresh_coverage()


func _exit_tree() -> void:
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
	return WetSurfaceWater.splash(self, point, dose,
		splash_initial_radius, splash_maximum_radius)


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
	var valid: bool = _coverage.rebuild(layer, settings)
	if is_instance_valid(tile_layer):
		_pose = tile_layer.global_transform
	if configure_backend and is_instance_valid(simulation) and simulation.get_parent() == self:
		if valid and world_bounds.has_area():
			simulation.update_region(
				_coverage,
				_pose,
				settings,
				WetSurfaceMetrics.local_bounds(_pose, world_bounds),
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
		WetSurfaceMetrics.local_bounds(_pose, world_bounds),
		seam_neighbors,
	)
	coverage_changed.emit(world_bounds)
	return simulation.validation_error().is_empty()


## Read-only local floor envelope, independent of the amount of water or collision clipping.
func coverage_bounds() -> Rect2:
	return _coverage.bounds if _ensure_coverage() else Rect2()


## WORLD point and normalized saturation dose. Invalid/negative/zero input is ignored.
func deposit(world_point: Vector2, dose: float) -> bool:
	return WetSurfaceWater.deposit(self, world_point, dose)


## One union stamp, with one dose per field sample, regardless of overlapping shapes.
func stamp(footprint: WaterFootprint2D, dose: float, source: Vector2,
		obstacle_mask: int, exclusions: Array[RID] = []) -> bool:
	return WetSurfaceWater.stamp(self, footprint, dose, source, obstacle_mask, exclusions)


## Indexed world-space saturation for traction and absorption, including dry contacts.
func saturation_at(world_point: Vector2) -> float:
	return WetSurfaceWater.sample(self, world_point)


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
	if not is_instance_valid(tile_layer):
		_dirty = true
	if is_instance_valid(tile_layer) and _pose != tile_layer.global_transform:
		_dirty = true
	if _dirty:
		refresh_coverage(Rect2(), lifecycle == null or not lifecycle.staged)
	return _coverage.error.is_empty() and settings != null \
		and settings.validation_error().is_empty()


func _bind() -> void:
	_dirty = _binding.synchronize(self) or _dirty


func _ensure_presentation() -> void:
	if not is_inside_tree():
		return
	# Honor existing composed scenes without creating a second renderer.
	if not is_instance_valid(presentation):
		for node: Node in get_tree().root.find_children("*", "WetSurfacePresentation", true, false):
			if node.surface == self:
				presentation = node
				break
	if not is_instance_valid(presentation):
		presentation = WetSurfacePresentation.new()
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
