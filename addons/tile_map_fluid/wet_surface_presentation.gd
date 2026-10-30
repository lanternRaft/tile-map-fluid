class_name WetSurfacePresentation
extends Node
## Optional grid artwork. Explicit parent integrates water into the host's ground or Y-sort band.

## Fired only when row artwork is replaced, never for ordinary wetting/drying uploads.
signal geometry_rebuilt

## Owning surface; this presenter supports its dedicated WetGridSimulation backend.
@export var surface: WetSurface2D
## Host-owned Node2D for row slices. Enable its Y sorting to interleave physical water rows.
@export var presentation_parent: Node2D
## Shared configuration; call rebuild() after changing appearance values at runtime.
@export var appearance: WetSurfaceAppearance = WetSurfaceAppearance.new()

var _bound: WetSurface2D
var _grid: WetGridSimulation
var _parent: Node2D
var _rows: Array[WetSurfaceRow] = []
var _anchors: PackedVector2Array = []
var _revision: int = -1
var _dirty: bool = true
var _elapsed: float = 0.0


func _ready() -> void:
	refresh()


func _exit_tree() -> void:
	_disconnect()
	clear()


func _process(delta: float) -> void:
	_elapsed += delta
	if appearance != null and _elapsed >= maxf(0.016, appearance.refresh_interval):
		_elapsed = 0.0
		refresh()


## Force new artwork after changing appearance. Does not alter simulation or physics.
func rebuild() -> void:
	_revision = -1
	refresh()


## Synchronize geometry only on coverage changes, then upload the same field used for traction.
func refresh() -> void:
	_bind()
	if not is_instance_valid(surface) or not is_instance_valid(presentation_parent) \
			or appearance == null or not surface.validation_error().is_empty():
		clear()
		return
	var grid: WetGridSimulation = surface.simulation as WetGridSimulation
	if grid == null or not is_inside_tree() or not presentation_parent.is_inside_tree() \
			or presentation_parent.get_world_2d() != surface.get_world_2d():
		clear()
		return
	if grid != _grid or presentation_parent != _parent or _revision != grid.geometry_revision:
		clear()
		_grid = grid
		_parent = presentation_parent
		_revision = grid.geometry_revision
		_build_rows()
		_dirty = true
		geometry_rebuilt.emit()
	for index: int in range(_rows.size()):
		_rows[index].global_transform = surface.tile_layer.global_transform \
			* Transform2D(0.0, _anchors[index])
		if _dirty:
			_rows[index].refresh(_grid)
	_dirty = false


## Release external row children immediately, including when the component leaves the tree.
func clear() -> void:
	for row: WetSurfaceRow in _rows:
		if is_instance_valid(row):
			row.free()
	_rows.clear()
	_anchors.clear()
	_grid = null
	_parent = null
	_revision = -1


func _build_rows() -> void:
	var rows: Dictionary[int, Array] = {}
	for cell: Vector2i in _grid.covered_cells():
		if not rows.has(cell.y):
			rows[cell.y] = []
		rows[cell.y].append(cell)
	var keys: Array[int] = rows.keys()
	keys.sort()
	for key: int in keys:
		var cells: Array[Vector2i] = []
		cells.assign(rows[key])
		var anchor: Vector2 = surface.settings.sample_origin \
			+ Vector2(0, key * surface.settings.sample_spacing)
		var row: WetSurfaceRow = WetSurfaceRow.new()
		row.name = "WetRow%s" % key
		_parent.add_child(row)
		row.configure(_grid, cells, anchor, appearance)
		_rows.append(row)
		_anchors.append(anchor)


func _mark_dirty() -> void:
	_dirty = true


func _bind() -> void:
	if surface != _bound:
		_disconnect()
		_bound = surface
		if is_instance_valid(_bound):
			_bound.changed.connect(_mark_dirty)
		_dirty = true


func _disconnect() -> void:
	if is_instance_valid(_bound) and _bound.changed.is_connected(_mark_dirty):
		_bound.changed.disconnect(_mark_dirty)
	_bound = null
