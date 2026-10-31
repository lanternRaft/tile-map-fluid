class_name TileFluidSurfaceAtlas
extends RefCounted
## Static patch topology. Explicit contact indices keep disconnected sides of walls separate.

## Two RGBA float texels per patch: four contact indices and the local bilinear domain.
var data: TileFluidFloatTexture = TileFluidFloatTexture.new()
## Active patches, independent of released slots retained for bounded regional reuse.
var patch_count: int = 0
var _values: PackedFloat32Array = []
var _free: PackedInt32Array = []


## Assign a stable slot; unaffected meshes retain their original contact lookups after edits.
func allocate(patch: TileFluidFieldPatch, anchor: Vector2) -> int:
	@warning_ignore("integer_division")
	var slot: int = _values.size() / 8
	if _free.is_empty():
		_values.resize(_values.size() + 8)
	else:
		slot = _free[-1]
		_free.resize(_free.size() - 1)
	var offset: int = slot * 8
	for corner: int in range(4):
		_values[offset + corner] = patch.corners[corner]
	_values[offset + 4] = patch.bounds.position.x - anchor.x
	_values[offset + 5] = patch.bounds.position.y - anchor.y
	_values[offset + 6] = patch.bounds.size.x
	_values[offset + 7] = patch.bounds.size.y
	patch_count += 1
	return slot


## Released topology slots are reused on the next local geometry replacement.
func release(slots: PackedInt32Array) -> void:
	_free.append_array(slots)
	patch_count -= slots.size()


## Geometry changes alone upload topology; ordinary wetting updates only saturation.
func upload() -> void:
	data.upload(_values, 4)
