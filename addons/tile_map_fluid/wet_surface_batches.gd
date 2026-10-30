class_name WetSurfaceBatches
extends RefCounted
## Owns external geometry and localized replacement independently of saturation uploads.

## Shared static topology table for every mesh and material.
var atlas: WetSurfaceAtlas = WetSurfaceAtlas.new()
var _bands: Dictionary[int, WetSurfaceRow] = {}
var _dirty: Dictionary[int, bool] = {}
var _all_dirty: bool = true


## Full backend replacement invalidates removed rows as well as newly covered ones.
func invalidate_all() -> void:
	_all_dirty = true


## Mark only ordering bands containing replaced cells; contact slots elsewhere stay stable.
func invalidate(cells: Array[Vector2i], band_rows: int) -> void:
	for cell: Vector2i in cells:
		_dirty[_key(cell.y, band_rows)] = true


## Synchronize static meshes after actual geometry changes, retaining all distant batches.
func synchronize(surface: WetSurface2D, parent: Node2D, band_rows: int,
		water_material: ShaderMaterial, artwork: Texture2D) -> bool:
	if not _all_dirty and _dirty.is_empty():
		return false
	var grid: WetGridSimulation = surface.simulation as WetGridSimulation
	var groups: Dictionary[int, Array] = {}
	for cell: Vector2i in grid.covered_cells():
		var key: int = _key(cell.y, band_rows)
		if _all_dirty or _dirty.has(key):
			if not groups.has(key):
				groups[key] = []
			groups[key].append(cell)
	var removed: Array[int] = _bands.keys() if _all_dirty else _dirty.keys()
	for key: int in removed:
		_remove(key)
	var keys: Array[int] = groups.keys()
	keys.sort()
	for key: int in keys:
		var cells: Array[Vector2i] = []
		cells.assign(groups[key])
		var anchor: Vector2 = surface.settings.sample_origin + Vector2(
			0, key * band_rows * surface.settings.sample_spacing)
		var band: WetSurfaceRow = WetSurfaceRow.new()
		band.name = "WetWaterBand%s" % key
		band.configure(grid, cells, anchor, atlas, water_material, artwork)
		parent.add_child(band)
		_bands[key] = band
	atlas.upload()
	_all_dirty = false
	_dirty.clear()
	return true


## Keep authored draw anchors aligned with transformed/composed layers and external parents.
func position_bands(pose: Transform2D, wet: bool) -> void:
	for band: WetSurfaceRow in _bands.values():
		band.global_transform = pose * Transform2D(0.0, band.anchor)
		band.visible = wet


## Read-only node handles for host overlap tests and diagnostics, without host ownership.
func bands() -> Array[WetSurfaceRow]:
	return _bands.values()


## Diagnostic access to the ordering band for a layer-local lattice cell.
func band_for_cell(cell: Vector2i, band_rows: int) -> WetSurfaceRow:
	return _bands.get(_key(cell.y, band_rows))


## Release owned bands; ancestor teardown hides immediately and safely defers their deletion.
func clear(defer_free: bool = false) -> void:
	for key: int in _bands.keys():
		_remove(key, defer_free)
	_dirty.clear()
	_all_dirty = true
	atlas = WetSurfaceAtlas.new()


func _remove(key: int, defer_free: bool = false) -> void:
	if not _bands.has(key):
		return
	var band: WetSurfaceRow = _bands[key]
	if is_instance_valid(band):
		band.release(atlas)
		if defer_free:
			band.hide()
			band.queue_free()
		else:
			band.free()
	_bands.erase(key)


func _key(row: int, band_rows: int) -> int:
	return floori(float(row) / band_rows)
