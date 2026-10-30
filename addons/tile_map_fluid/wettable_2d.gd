class_name Wettable2D
extends Area2D
## Signal-only receiver. Author optional Area shapes for footprint discovery; no artwork required.

## Current normalized saturation changed, including direct wetting, drying, and absorption.
signal changed(saturation: float)
## Valid direct dose, clamped to one; emitted even when already saturated.
signal water_added(dose: float)
## Ground contact toggled independently of direct water eligibility.
signal contact_changed(enabled: bool)

## Explicit supporting surface also scopes Area-discovered emission to one room/layer.
@export var surface: WetSurface2D
## Optional floor marker; otherwise this Area's origin is the contact point.
@export var contact_point: Node2D
## Optional direct-water marker, independent of ground contact and lifted artwork.
@export var direct_point: Node2D
## Optional body allowed to be the final obstruction hit when directly spraying this object.
@export var obstacle_body: CollisionObject2D
## Independent drying/absorption; shared settings never store mutable saturation.
@export var settings: WettableSettings = WettableSettings.new()
## Host adapters disable this while lifting, carrying, or resting above the floor.
@export var contact_enabled: bool = true:
	set(value):
		if value != contact_enabled:
			contact_enabled = value
			if not value:
				surface_saturation = 0.0
			contact_changed.emit(value)

## Retained object saturation, independent of the floor and other placements.
var saturation: float = 0.0:
	get:
		return _saturation
## Last sampled floor saturation for optional movement consumers.
var surface_saturation: float = 0.0
var _saturation: float = 0.0


func _physics_process(delta: float) -> void:
	advance(delta)


## Direct hits remain possible while contact is disabled. Invalid doses have no side effects.
func add_water(dose: float) -> bool:
	if not is_finite(dose) or dose <= 0.0:
		return false
	var amount: float = minf(dose, 1.0)
	_set_saturation(_saturation + amount)
	water_added.emit(amount)
	return true


## Explicit contact API for host adapters; avoids importing cargo or player types.
func set_contact_enabled(enabled: bool) -> void:
	contact_enabled = enabled


## WORLD contact used for direct hits, with no inferred parent or carrier paths.
func water_position() -> Vector2:
	return direct_point.global_position if is_instance_valid(direct_point) else global_position


## Advance by scaled physics seconds. Absorption never consumes the supporting surface.
func advance(delta: float) -> void:
	if not is_finite(delta) or delta <= 0.0 or settings == null \
			or not settings.validation_error().is_empty():
		return
	surface_saturation = 0.0
	if contact_enabled and is_instance_valid(surface) and is_inside_tree() \
			and surface.is_inside_tree() \
			and surface.get_world_2d() == get_world_2d():
		var point: Vector2 = contact_point.global_position \
			if is_instance_valid(contact_point) else global_position
		surface_saturation = surface.saturation_at(point)
	var amount: float = _saturation
	if settings.dry_seconds > 0.0:
		amount = maxf(0.0, amount - delta / settings.dry_seconds)
	if surface_saturation > amount:
		amount = move_toward(amount, surface_saturation, settings.ground_absorption * delta)
	_set_saturation(amount)


func _set_saturation(value: float) -> void:
	var amount: float = clampf(value, 0.0, 1.0)
	if amount != _saturation:
		_saturation = amount
		changed.emit(_saturation)
