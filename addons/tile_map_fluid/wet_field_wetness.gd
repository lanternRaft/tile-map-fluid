class_name TileFluidFieldWetness
extends RefCounted
## Passive linear drying. Only deposits write samples; reads evaluate elapsed evaporation.

## Float32 saturation at the most recent write, independent of the current clock.
var values: PackedFloat32Array = []
## Accumulated evaporation in saturation units, advanced using scaled simulation seconds.
var clock: float = 0.0
var _updated: PackedFloat64Array = []
var _records: PackedFloat32Array = []
var _last_wet: int = -1
var _expires: float = 0.0
var _editing: bool = false
var _expiry_dirty: bool = false


## Release records without rewinding time; cached GPU records must stay on the same timeline.
func clear() -> void:
	values.clear()
	_updated.clear()
	_records.clear()
	_last_wet = -1
	_expires = clock
	_editing = false
	_expiry_dirty = false


## Allocate a dry slot alongside the field's geometry-owned sample index.
func append() -> void:
	values.append(0.0)
	_updated.append(clock)
	_records.resize(values.size() * 4)


## Calculate a sample without mutating its stored record or allocating a snapshot.
func get_water(index: int) -> float:
	return maxf(0.0, values[index] - (clock - _updated[index]))


## Store current saturation and its simulation timestamp, including reused or released slots.
func set_water(index: int, value: float) -> void:
	values[index] = clampf(value, 0.0, 1.0)
	_updated[index] = clock
	var whole: float = floorf(clock)
	_records[index * 4] = values[index]
	_records[index * 4 + 1] = whole
	_records[index * 4 + 2] = clock - whole
	var expiry: float = clock + values[index]
	if index == _last_wet and expiry < _expires:
		_expiry_dirty = true
		if not _editing:
			_find_last_wet()
	elif values[index] > 0.0 and expiry >= _expires:
		_last_wet = index
		_expires = expiry


## Batch released slots so a geometry edit repairs occupancy at most once.
func begin_edit() -> void:
	_editing = true


## Finish occupancy bookkeeping before publishing replaced geometry.
func end_edit() -> void:
	_editing = false
	if _expiry_dirty:
		_find_last_wet()


## Expired samples remain untouched; the latest deadline makes occupancy a scalar comparison.
func has_water() -> bool:
	return _last_wet >= 0 and clock < _expires


## Read four live samples before bilinear interpolation, matching the shader's corner clamp.
func patch_water(patch: TileFluidFieldPatch) -> Color:
	return Color(get_water(patch.corners[0]), get_water(patch.corners[1]),
		get_water(patch.corners[2]), get_water(patch.corners[3]))


## Explicit diagnostic snapshots materialize live values; ordinary drying never calls this.
func snapshot() -> PackedFloat32Array:
	var result: PackedFloat32Array = []
	result.resize(values.size())
	for index: int in range(values.size()):
		result[index] = get_water(index)
	return result


## Split whole/fractional time so float32 shader data retains precision during long wet runs.
func shader_clock() -> Vector2:
	return Vector2(floorf(clock), clock - floorf(clock))


## Upload only on writes: saturation, whole update time, fractional update time, unused.
func shader_records() -> PackedFloat32Array:
	return _records.duplicate()


func _find_last_wet() -> void:
	_expiry_dirty = false
	_last_wet = -1
	_expires = clock
	# A decreasing write (geometry removal or explicit clearing) may remove the latest sample.
	# This scan happens on that write, never on a drying tick or query.
	for index: int in range(values.size()):
		var expiry: float = _updated[index] + values[index]
		if values[index] > 0.0 and expiry > _expires:
			_last_wet = index
			_expires = expiry


## Prepared contacts retain sample identities, not geometry or final wetness.
func contact_water(corners: PackedInt32Array) -> Color:
	return Color(get_water(corners[0]), get_water(corners[1]),
		get_water(corners[2]), get_water(corners[3]))
