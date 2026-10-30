@icon("res://addons/tile_map_fluid/assets/icons/receiver.svg")
class_name Wettable2D
extends Area2D
## Wetness receiver with optional artwork tinting. Author Area shapes for footprint discovery.

## Current normalized saturation changed, including direct wetting, drying, and absorption.
signal changed(saturation: float)
## Valid dose, clamped unless settings report the full dose; emitted even at saturation.
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
## Discover the nearest ancestor-scoped surface in this physics world.
@export var automatic_surface: bool = false
## Indexed properties relative to this receiver; all must be truthy for floor contact.
@export var contact_required_paths: Array[NodePath] = []
## Indexed properties relative to this receiver; all must be falsey for floor contact.
@export var contact_blocked_paths: Array[NodePath] = []
## Optional direct-hit footprint, independent of floor-contact eligibility.
@export var footprint: CollisionShape2D
## Optional artwork wrapper whose modulate is owned by this receiver while assigned.
## Put other modulation effects on parents or children; materials remain untouched.
@export var artwork: Node2D:
	set(value):
		if artwork == value:
			return
		_restore_artwork()
		artwork = value
		if is_inside_tree():
			_apply_tint()
## Optional rigid body receiving the supporting surface's configured floor traction.
## Leave unset when a host movement/carrying component owns damping instead.
@export var traction_body: RigidBody2D

## Retained object saturation, independent of the floor and other placements.
var saturation: float = 0.0:
	get:
		return _saturation
## Last sampled floor saturation for optional movement consumers.
var surface_saturation: float = 0.0
var _saturation: float = 0.0
var _tinted_artwork: Node2D
var _authored_color: Color = Color.WHITE
var _traction: WetBodyTraction = WetBodyTraction.new()


func _enter_tree() -> void:
	_apply_tint()


func _exit_tree() -> void:
	_traction.restore()
	_restore_artwork()


func _restore_artwork() -> void:
	if is_instance_valid(_tinted_artwork):
		_tinted_artwork.modulate = _authored_color
	_tinted_artwork = null


func _apply_tint() -> void:
	if not is_instance_valid(artwork):
		return
	if _tinted_artwork != artwork:
		_tinted_artwork = artwork
		_authored_color = artwork.modulate
	var multiplier: Color = settings.object_tint if settings != null else Color.WHITE
	artwork.modulate = _authored_color * Color.WHITE.lerp(multiplier, _saturation)


func _physics_process(delta: float) -> void:
	advance(delta)


## Refresh live contact conditions and surface ownership after moving or reparenting.
func refresh_contact() -> void:
	if automatic_surface:
		if not is_inside_tree():
			surface = null
			return
		surface = null
		var ancestor: Node = get_parent()
		while ancestor != null:
			for node: Node in get_tree().get_nodes_in_group(&"wet_surfaces"):
				var candidate: WetSurface2D = node as WetSurface2D
				if candidate.contact_scope == ancestor and candidate.is_visible_in_tree() \
						and candidate.get_world_2d() == get_world_2d():
					surface = candidate
					break
			if surface != null:
				break
			ancestor = ancestor.get_parent()
	if not contact_required_paths.is_empty() or not contact_blocked_paths.is_empty():
		var enabled: bool = true
		for path: NodePath in contact_required_paths:
			enabled = enabled and _condition(path)
		for path: NodePath in contact_blocked_paths:
			enabled = enabled and not _condition(path)
		set_contact_enabled(enabled)


func _condition(path: NodePath) -> bool:
	var target: Node = get_node_or_null(NodePath(path.get_concatenated_names()))
	if target == null or path.get_subname_count() == 0:
		return false
	var value: Variant = target.get_indexed(NodePath(":" + path.get_concatenated_subnames()))
	return true if value else false


## Direct hits remain possible while contact is disabled. Invalid doses have no side effects.
func add_water(dose: float) -> bool:
	if not is_finite(dose) or dose <= 0.0:
		return false
	var amount: float = minf(dose, 1.0)
	_set_saturation(_saturation + amount)
	water_added.emit(dose if settings != null and settings.report_full_dose else amount)
	return true


## Explicit contact API for host adapters; avoids importing cargo or player types.
func set_contact_enabled(enabled: bool) -> void:
	contact_enabled = enabled


## WORLD contact used for direct hits, with no inferred parent or carrier paths.
func water_position() -> Vector2:
	return direct_point.global_position if is_instance_valid(direct_point) else global_position


## Advance by scaled physics seconds. Absorption never consumes the supporting surface.
func advance(delta: float) -> void:
	refresh_contact()
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
	_traction.apply(traction_body, surface if contact_enabled else null, surface_saturation)


func _set_saturation(value: float) -> void:
	var amount: float = clampf(value, 0.0, 1.0)
	if amount != _saturation:
		_saturation = amount
		_apply_tint()
		changed.emit(_saturation)
