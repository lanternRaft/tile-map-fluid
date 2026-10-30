@icon("res://addons/tile_map_fluid/assets/icons/fluid.svg")
class_name WetSurfaceLifecycle
extends Node
## Optional staged preparation and physics-safe obstacle batching for a composed surface.

## Surface whose coverage and backend this component prepares.
@export var surface: WetSurface2D
## Optional renderer refreshed alongside each prepared region.
@export var presentation: WetSurfacePresentation
## Frozen hosts advance preparation explicitly instead of building the whole field at ready.
@export var staged: bool = false
## Anchor the sampling lattice to the coverage envelope instead of a fixed authored origin.
@export var anchor_to_coverage: bool = false

var _row: int = -1
var _pending: bool = false
var _full: bool = false
var _area: Rect2
var _initialized: bool = false


func _ready() -> void:
	if not staged:
		request_obstacles()
		if presentation != null:
			presentation.automatic_updates = true


func _exit_tree() -> void:
	if get_tree().physics_frame.is_connected(_after_physics):
		get_tree().physics_frame.disconnect(_after_physics)
	if get_tree().process_frame.is_connected(_flush):
		get_tree().process_frame.disconnect(_flush)
	_pending = false
	_full = false
	_area = Rect2()
	_row = -1
	_initialized = false


## Merge collider edits until physics has registered their new shapes; empty means full field.
func request_obstacles(area: Rect2 = Rect2()) -> void:
	_full = _full or not area.has_area()
	_area = _area.merge(area) if _area.has_area() else area
	if _pending or not is_inside_tree() or staged:
		return
	_pending = true
	get_tree().physics_frame.connect(_after_physics, CONNECT_ONE_SHOT)


## Explicit initialization preserves the synchronous path for already registered geometry.
func initialize() -> void:
	if _initialized:
		request_obstacles()
		return
	_initialized = true
	surface.refresh_coverage(Rect2(), false)
	if anchor_to_coverage:
		surface.settings.sample_origin = surface.coverage_bounds().position
	if staged:
		return
	surface.refresh_coverage()
	request_obstacles()
	_refresh_presentation()


## Advance one immutable row. The surface's automatic clock stays paused until completion.
func advance_initialization() -> bool:
	if not staged:
		return true
	var grid: WetGridSimulation = surface.simulation as WetGridSimulation
	if grid == null or surface.tile_layer == null:
		return false
	if _row < 0:
		surface.refresh_coverage(Rect2(), false)
		grid.reset(surface.settings, surface.tile_layer.global_transform)
		_row = 0
		if presentation != null:
			presentation.automatic_updates = false
		return false
	var bounds: Rect2 = surface.coverage_bounds()
	var spacing: float = surface.settings.sample_spacing
	var origin: Vector2 = surface.settings.sample_origin
	var first: Vector2i = Vector2i(((bounds.position - origin) / spacing).floor())
	var end: Vector2i = Vector2i(((bounds.end - origin) / spacing).ceil())
	if first.y + _row >= end.y:
		staged = false
		_full = false
		_area = Rect2()
		if presentation != null:
			presentation.automatic_updates = true
		return true
	var local: Rect2 = Rect2(origin + Vector2(first.x, first.y + _row) * spacing,
		Vector2(end.x - first.x, 1) * spacing)
	surface.refresh_obstacles(WetFieldPolygons.bounds(
		surface.tile_layer.global_transform * WetFieldPolygons.rectangle(local)), false)
	_refresh_presentation()
	_row += 1
	return false


## Clear water and restart preparation using the current configuration.
func rebuild() -> void:
	_row = -1
	_initialized = false
	if presentation != null:
		presentation.clear()
	if staged:
		return
	var grid: WetGridSimulation = surface.simulation as WetGridSimulation
	if grid != null:
		grid.reset(surface.settings, surface.tile_layer.global_transform)
	initialize()


func _after_physics() -> void:
	get_tree().process_frame.connect(_flush, CONNECT_ONE_SHOT)


func _flush() -> void:
	var area: Rect2 = Rect2() if _full else _area
	_pending = false
	_full = false
	_area = Rect2()
	if not staged:
		surface.refresh_obstacles(area)


func _refresh_presentation() -> void:
	if presentation != null:
		presentation.refresh()
