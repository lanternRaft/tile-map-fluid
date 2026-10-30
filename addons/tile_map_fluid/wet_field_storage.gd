class_name WetFieldStorage
extends RefCounted
## Surface-owned contacts. Rebuilding releases all old storage; emissions never allocate samples.

## Shared contact saturation, separate from authored resources and coverage.
var water: PackedFloat32Array = []
## Connected patches in each layer-local lattice cell, including negative coordinates.
var cells: Dictionary[Vector2i, Array] = {}
var _indices: Dictionary[Vector3, int] = {}
var _previous: Dictionary[Vector2i, Array] = {}
var _wet_samples: int = 0
var _empty: Array[WetFieldPatch] = []
var _references: PackedInt32Array = []
var _keys: PackedVector2Array = []
var _free: Array[int] = []


## Retain surviving clipped floor; newly exposed patches start dry, even at old wet seams.
func begin_rebuild(preserve: bool) -> void:
	_previous.clear()
	if preserve:
		for cell: Vector2i in cells:
			_remember(cell)
	cells.clear()
	water.clear()
	_indices.clear()
	_wet_samples = 0
	_references.clear()
	_keys.clear()
	_free.clear()


## Replace local cells, retaining distant patch identities and reusing released slots.
func begin_replace(replaced: Array[Vector2i]) -> void:
	_previous.clear()
	for cell: Vector2i in replaced:
		_remember(cell)
		for patch: WetFieldPatch in patches(cell):
			for corner: int in patch.corners:
				_references[corner] -= 1
				if _references[corner] == 0:
					set_water(corner, 0.0)
					_free.append(corner)
		cells.erase(cell)
	_indices.clear()
	for index: int in range(water.size()):
		if _references[index] > 0:
			var point: Vector2 = _keys[index]
			_indices[Vector3(point.x, point.y, water[index])] = index


## Share matching contacts, but never seed newly exposed floor from a retained wet neighbor.
func add_cell(cell: Vector2i, polygons: Array[PackedVector2Array]) -> void:
	var result: Array[WetFieldPatch] = []
	for polygon: PackedVector2Array in polygons:
		var bounds: Rect2 = WetFieldPolygons.bounds(polygon)
		var local: PackedVector2Array = Transform2D(0.0, -polygon[0]) * polygon
		if bounds.size.x < 0.01 or bounds.size.y < 0.01 \
				or Geometry2D.triangulate_polygon(local).is_empty():
			continue
		var patch: WetFieldPatch = WetFieldPatch.new()
		patch.configure(polygon)
		var retained: Color = _retained(cell, patch)
		for offset: int in range(patch.positions.size()):
			# Clipping uses a 1/1000 pixel lattice. Different initial values need separate
			# seam contacts after an edit so the new side is dry and the old side is retained.
			var point: Vector2 = patch.positions[offset].snapped(Vector2.ONE * 0.001)
			var key: Vector3 = Vector3(point.x, point.y, retained[offset])
			if not _indices.has(key):
				_indices[key] = _allocate(point, retained[offset])
			var corner: int = _indices[key]
			_references[corner] += 1
			patch.corners.append(corner)
		result.append(patch)
	if not result.is_empty():
		cells[cell] = result


## Drop the temporary retention map after coverage replacement.
func end_rebuild() -> void:
	_previous.clear()
	_indices.clear()


## No allocation for absent coverage, holes, or dry queries.
func patches(cell: Vector2i) -> Array[WetFieldPatch]:
	return cells.get(cell, _empty)


## Track wet occupancy using the stored float32 value, including values rounding to zero.
func set_water(index: int, value: float) -> void:
	var was_wet: bool = water[index] > 0.0
	water[index] = clampf(value, 0.0, 1.0)
	_wet_samples += int(water[index] > 0.0) - int(was_wet)


## Dry queries and idle evaporation skip all contact work.
func has_water() -> bool:
	return _wet_samples > 0


## One central pass, using scaled physics seconds supplied by the surface.
func evaporate(loss: float) -> void:
	_wet_samples = 0
	for index: int in range(water.size()):
		water[index] = maxf(0.0, water[index] - loss)
		_wet_samples += int(water[index] > 0.0)


func _remember(cell: Vector2i) -> void:
	var snapshots: Array[WetPatchSnapshot] = []
	for patch: WetFieldPatch in patches(cell):
		var snapshot: WetPatchSnapshot = WetPatchSnapshot.new()
		snapshot.patch = patch
		snapshot.water = patch.water(water)
		snapshots.append(snapshot)
	_previous[cell] = snapshots


func _retained(cell: Vector2i, patch: WetFieldPatch) -> Color:
	for snapshot: WetPatchSnapshot in _previous.get(cell, []):
		if snapshot.contains(patch.polygon):
			return snapshot.sample(patch.positions)
	return Color(0, 0, 0, 0)


func _allocate(point: Vector2, value: float) -> int:
	var index: int
	if _free.is_empty():
		index = water.size()
		water.append(0.0)
		_references.append(0)
		_keys.append(point)
	else:
		index = _free.pop_back()
		_keys[index] = point
	set_water(index, value)
	return index
