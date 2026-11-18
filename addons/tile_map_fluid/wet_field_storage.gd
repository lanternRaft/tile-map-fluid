class_name TileFluidFieldStorage
extends RefCounted
## Surface-owned contacts. Rebuilding releases all old storage; emissions never allocate samples.

## Stored saturation at the last write; use wetness for current values after drying.
var water: PackedFloat32Array:
	get:
		return wetness.values
## Passive sample records shared by gameplay and presentation.
var wetness: TileFluidFieldWetness = TileFluidFieldWetness.new()
## Connected patches in each layer-local lattice cell, including negative coordinates.
var cells: Dictionary[Vector2i, Array] = {}
# Coincident corners can own different water after a wall moves. Index geometry only;
# evaluate their live, passively dried values when reconnecting a seam.
var _slots_at: Dictionary[Vector2, Array] = {}
var _previous: Dictionary[Vector2i, Array] = {}
var _empty: Array[TileFluidFieldPatch] = []
var _references: PackedInt32Array = []
var _free: Array[int] = []


## Retain surviving clipped floor; newly exposed patches start dry, even at old wet seams.
func begin_rebuild(preserve: bool) -> void:
	_previous.clear()
	if preserve:
		for cell: Vector2i in cells:
			_remember(cell)
	cells.clear()
	wetness.clear()
	_slots_at.clear()
	_references.clear()
	_free.clear()


## Replace local cells, retaining distant patch identities and reusing released slots.
func begin_replace(replaced: Array[Vector2i]) -> void:
	wetness.begin_edit()
	_previous.clear()
	for cell: Vector2i in replaced:
		_remember(cell)
		for patch: TileFluidFieldPatch in patches(cell):
			for offset: int in range(patch.corners.size()):
				var corner: int = patch.corners[offset]
				_references[corner] -= 1
				if _references[corner] == 0:
					set_water(corner, 0.0)
					var point := patch.positions[offset].snapped(Vector2.ONE * 0.001)
					var slots: Array = _slots_at[point]
					slots.erase(corner)
					if slots.is_empty():
						_slots_at.erase(point)
					_free.append(corner)
		cells.erase(cell)


## Share matching contacts, but never seed newly exposed floor from a retained wet neighbor.
func add_cell(cell: Vector2i, polygons: Array[PackedVector2Array]) -> void:
	var result: Array[TileFluidFieldPatch] = []
	for polygon: PackedVector2Array in polygons:
		var bounds: Rect2 = TileFluidFieldPolygons.bounds(polygon)
		var local: PackedVector2Array = Transform2D(0.0, -polygon[0]) * polygon
		if bounds.size.x < 0.01 or bounds.size.y < 0.01 \
				or Geometry2D.triangulate_polygon(local).is_empty():
			continue
		var patch: TileFluidFieldPatch = TileFluidFieldPatch.new()
		patch.configure(polygon)
		var retained: Color = _retained(cell, patch)
		for offset: int in range(patch.positions.size()):
			# Clipping uses a 1/1000 pixel lattice. Different initial values need separate
			# seam contacts after an edit so the new side is dry and the old side is retained.
			var point: Vector2 = patch.positions[offset].snapped(Vector2.ONE * 0.001)
			var corner: int = _find_or_allocate(point, retained[offset])
			_references[corner] += 1
			patch.corners.append(corner)
		result.append(patch)
	if not result.is_empty():
		cells[cell] = result


## Drop the temporary retention map after coverage replacement.
func end_rebuild() -> void:
	wetness.end_edit()
	_previous.clear()


## No allocation for absent coverage, holes, or dry queries.
func patches(cell: Vector2i) -> Array[TileFluidFieldPatch]:
	return cells.get(cell, _empty)


## Store saturation at the current simulation time; drying never rewrites the sample.
func set_water(index: int, value: float) -> void:
	wetness.set_water(index, value)


## Dry queries and idle evaporation skip all contact work.
func has_water() -> bool:
	return wetness.has_water()


func _remember(cell: Vector2i) -> void:
	var snapshots: Array[TileFluidPatchSnapshot] = []
	for patch: TileFluidFieldPatch in patches(cell):
		var snapshot: TileFluidPatchSnapshot = TileFluidPatchSnapshot.new()
		snapshot.patch = patch
		snapshot.water = wetness.patch_water(patch)
		snapshots.append(snapshot)
	_previous[cell] = snapshots


func _retained(cell: Vector2i, patch: TileFluidFieldPatch) -> Color:
	for snapshot: TileFluidPatchSnapshot in _previous.get(cell, []):
		if snapshot.contains(patch.polygon):
			return snapshot.sample(patch.positions)
	return Color(0, 0, 0, 0)


func _find_or_allocate(point: Vector2, value: float) -> int:
	var slots: Array = _slots_at.get_or_add(point, [])
	var index: int = -1
	for slot: int in slots:
		# Match the real_t precision of the previous Vector3(position.x, position.y, water) key.
		if Vector3(0, 0, wetness.get_water(slot)).z == value:
			index = maxi(index, slot)
	if index >= 0:
		return index
	if _free.is_empty():
		index = water.size()
		wetness.append()
		_references.append(0)
	else:
		index = _free.pop_back()
	slots.append(index)
	set_water(index, value)
	return index
