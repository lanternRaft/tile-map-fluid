class_name WaterSpray2D
extends Node2D
## Continuous, additive soft splashes and shape-aware direct hits in floor space.

## One validated emission, even if barriers or saturation prevent a field change.
signal emitted(dose: float)


## Explicit room-local destination; no overlapping-surface discovery.
@export var surface: WetSurface2D
## Ancestor containing eligible receivers, including shape-free or carried receivers.
@export var receiver_scope: Node
## Optional receivers when no scope is required; duplicates receive only one dose.
@export var receivers: Array[Wettable2D] = []
## Scene-local spray configuration; shared resources contain no runtime water.
@export var settings: WaterSpraySettings = WaterSpraySettings.new()
## Positive local X defines the spray direction; position is the floor-space outlet.
@export var active: bool = false


func _physics_process(delta: float) -> void:
	advance(delta)


## Advance explicitly for controlled clocks/tests; disable physics processing in that case.
func advance(delta: float) -> void:
	if active and is_finite(delta) and delta > 0.0 and settings != null and settings.is_valid():
		emit_dose(settings.rate * delta)


## Each splash accumulates independently; receiver direct hits receive one dose per call.
func emit_dose(dose: float) -> void:
	if not is_inside_tree() or not is_finite(dose) or dose <= 0.0 \
			or settings == null or not settings.is_valid() or not global_position.is_finite() \
			or not global_transform.is_finite() or global_transform.x.is_zero_approx() \
			or not is_instance_valid(surface) or not surface.is_inside_tree() \
			or surface.get_world_2d() != get_world_2d() \
			or not surface.validation_error().is_empty():
		return
	var direction: Vector2 = global_transform.x.normalized()
	_wet_receivers(direction, dose)
	_wet_floor(direction, dose)
temitted.emit(dose)



func _wet_receivers(direction: Vector2, dose: float) -> void:
	var candidates: Array[Wettable2D] = receivers.duplicate()
	if is_instance_valid(receiver_scope):
		for node: Node in receiver_scope.find_children("*", "Wettable2D", true, false):
			candidates.append(node as Wettable2D)
	var visited: Dictionary[Wettable2D, bool] = {}
	for receiver: Wettable2D in candidates:
		if not is_instance_valid(receiver) or visited.has(receiver) \
				or not receiver.is_inside_tree() or not receiver.is_visible_in_tree() \
				or receiver.get_world_2d() != get_world_2d():
			continue
		visited[receiver] = true
		receiver.refresh_contact()
		if receiver.surface != surface:
			continue
		var reached: bool
		if is_instance_valid(receiver.footprint) and receiver.contact_enabled:
			reached = WaterSprayGeometry.reaches_shape(get_world_2d(), receiver.footprint,
				global_position, direction, settings.reach, settings.spread,
				settings.obstacle_mask, receiver.obstacle_body)
		else:
			reached = WaterSprayGeometry.reaches(get_world_2d(), receiver.water_position(),
				global_position, direction, settings.reach, settings.spread,
				settings.obstacle_mask, receiver.obstacle_body)
		if reached:
			receiver.add_water(dose)


func _wet_floor(direction: Vector2, dose: float) -> void:
	var simulation: WetGridSimulation = surface.simulation as WetGridSimulation
	if simulation == null:
		return
	var steps: int = maxi(1, ceili(settings.reach / settings.sample_spacing))
	for step: int in range(1, steps + 1):
		var distance: float = minf(step * settings.sample_spacing, settings.reach)
		var width: float = distance * tan(deg_to_rad(settings.spread))
		var sides: int = ceili(width / settings.sample_spacing)
		for side: int in range(-sides, sides + 1):
			var point: Vector2 = global_position + direction * distance \
				+ direction.orthogonal() * side * settings.sample_spacing
			if WaterSprayGeometry.reaches(get_world_2d(), point, global_position, direction,
					settings.reach, settings.spread, settings.obstacle_mask):
				var saturation: float = clampf(surface.saturation_at(point) + dose, 0.0, 1.0)
				var radius: float = lerpf(settings.initial_radius, settings.maximum_radius, saturation)
				simulation.splash(surface.tile_layer.to_local(point), dose, radius, settings.obstacle_mask)
