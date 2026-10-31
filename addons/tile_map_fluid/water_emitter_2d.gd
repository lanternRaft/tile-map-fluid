@icon("res://addons/tile_map_fluid/assets/icons/emitter.svg")
class_name TileFluidEmitter2D
extends Node2D
## Supply consumption and controls belong to the host; this node only delivers normalized water.

## Active state changed. Explicit emit_dose remains available while continuous emission is off.
signal active_changed(active: bool)
## One validated emission, even if saturation or obstruction prevents any field change.
signal emitted(dose: float)

## Exactly ONE destination per emitter. The composition root chooses routing explicitly.
@export var surface: TileFluidSurface2D
## Editor-authored Area union used both for floor geometry and receiver discovery.
@export var footprint: TileFluidFootprint2D
## Explicit receivers supplement Area discovery, including receivers with no physics shapes.
@export var receivers: Array[TileFluidWettable2D] = []
## Ignore source bodies explicitly, rather than guessing ownership from parents or groups.
@export var source_bodies: Array[CollisionObject2D] = []
## Per-covered-sample rate and obstruction mask; no conserved-volume interpretation.
@export var settings: TileFluidEmitterSettings = TileFluidEmitterSettings.new()
## Continuous emission uses scaled physics delta; stopping takes effect immediately.
@export var active: bool = false:
	set(value):
		if value != active:
			active = value
			active_changed.emit(value)


func _physics_process(delta: float) -> void:
	advance(delta)


## Explicit activation API for host input/tool adapters.
func set_active(enabled: bool) -> void:
	active = enabled


## Rate is saturation/second at each contact, independent of Area shape count or sample density.
func advance(delta: float) -> void:
	if active and is_finite(delta) and delta > 0.0 and settings != null \
			and settings.validation_error().is_empty():
		emit_dose(settings.rate * delta)


## Instant saturation dose; floor and objects receive independent, non-intercepting deposits.
## Explicit and Area-discovered receivers are deduplicated BEFORE direct wetting.
func emit_dose(dose: float) -> bool:
	if not is_finite(dose) or dose <= 0.0 or not is_inside_tree() \
			or not global_position.is_finite() or settings == null \
			or not settings.validation_error().is_empty() or not is_instance_valid(footprint) \
			or not footprint.is_inside_tree() or not footprint.validation_error().is_empty() \
			or footprint.get_world_2d() != get_world_2d():
		return false
	var amount: float = minf(dose, 1.0)
	var exclusions: Array[RID] = []
	for body: CollisionObject2D in source_bodies:
		if is_instance_valid(body):
			exclusions.append(body.get_rid())
	if is_instance_valid(surface) and surface.is_inside_tree() \
			and surface.get_world_2d() == get_world_2d():
		surface.stamp(footprint, amount, global_position, settings.obstacle_mask, exclusions)
	var candidates: Array[TileFluidWettable2D] = receivers.duplicate()
	candidates.append_array(footprint.receivers())
	var visited: Dictionary[TileFluidWettable2D, bool] = {}
	for receiver: TileFluidWettable2D in candidates:
		if not is_instance_valid(receiver) or visited.has(receiver):
			continue
		visited[receiver] = true
		if _reaches(receiver, exclusions):
			receiver.add_water(amount)
	emitted.emit(amount)
	return true


func _reaches(receiver: TileFluidWettable2D, exclusions: Array[RID]) -> bool:
	if not receiver.is_inside_tree() or receiver.get_world_2d() != get_world_2d():
		return false
	if surface != null and not is_instance_valid(surface):
		return false
	# A null-surface receiver opts in only through the explicit list, never broad Area overlap.
	if receiver.surface != surface or (surface == null and not receivers.has(receiver)):
		return false
	var point: Vector2 = receiver.water_position()
	var body: CollisionObject2D = receiver.obstacle_body \
		if is_instance_valid(receiver.obstacle_body) else null
	return footprint.contains_world_point(point) and TileFluidVisibility2D.reaches(
		get_world_2d(), global_position, point, settings.obstacle_mask, exclusions,
		body)
