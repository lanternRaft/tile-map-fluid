@icon("res://addons/tile_map_fluid/assets/icons/presentation.svg")
class_name WetSurfacePresentation
extends Node2D
## Addon-owned meshes, topology and bulk wetness uploads. Gameplay remains CPU authoritative.

## Actual static geometry replacement, never an ordinary saturation upload.
signal geometry_rebuilt
## Emitted once per bulk visual update, including the final dry clearing update.
signal field_uploaded

## Owning surface with a dedicated WetGridSimulation backend.
@export var surface: WetSurface2D
## Imported SVG or raster texture, tint, batching and visual update cadence.
@export var appearance: WetSurfaceAppearance = WetSurfaceAppearance.new()
## Staged hosts disable automatic work and call refresh() at their preparation boundaries.
@export var automatic_updates: bool = true

## Surface-owned renderers place row anchors in the world sorting band.
var render_parent: Node2D

var _grid: WetGridSimulation
var _batches: WetSurfaceBatches = WetSurfaceBatches.new()
var _field: WetFloatTexture = WetFloatTexture.new()
var _material: ShaderMaterial
var _dirty: bool = true
var _band_rows: int = 1
var _elapsed: float = 0.0
var _uploads: int = 0


func _init() -> void:
	y_sort_enabled = true


func _ready() -> void:
	if automatic_updates:
		refresh()


func _exit_tree() -> void:
	# Child lists are locked during tree exit; hide rows and defer their deletion.
	clear(true)


func _process(delta: float) -> void:
	if not automatic_updates or appearance == null:
		return
	_elapsed += delta
	if _elapsed >= maxf(0.016, appearance.refresh_interval):
		_elapsed = 0.0
		refresh()


## Apply changed appearance without changing simulation, water, physics or TileSet resources.
func rebuild() -> void:
	clear()
	refresh()


## Rebuild affected bands only, then publish the packed saturation snapshot in one texture upload.
func refresh() -> void:
	if not is_instance_valid(surface) \
			or appearance == null or not is_inside_tree() \
			or get_world_2d() != surface.get_world_2d() \
			or not surface.validation_error().is_empty():
		clear()
		return
	var grid: WetGridSimulation = surface.simulation as WetGridSimulation
	if grid == null:
		clear()
		return
	var band_rows: int = 1 if y_sort_enabled \
		else maxi(1, appearance.rows_per_batch)
	if grid != _grid or band_rows != _band_rows:
		clear()
		_grid = grid
		_band_rows = band_rows
		_grid.changed.connect(_mark_dirty)
		_grid.geometry_changed.connect(_geometry_changed)
		_grid.geometry_replaced.connect(_invalidate_all)
		_material = ShaderMaterial.new()
		_material.shader = preload("res://addons/tile_map_fluid/assets/wet_surface.gdshader")
		_material.set_shader_parameter("water_tint", appearance.tint)
		_material.set_shader_parameter("wetness_field", _field.texture)
		_material.set_shader_parameter("patch_table", _batches.atlas.data.texture)
	var rebuilt: bool = _batches.synchronize(surface, render_parent if is_instance_valid(render_parent) else self, _band_rows,
		_material, appearance.texture)
	if _dirty or rebuilt:
		_field.upload(grid.saturation_buffer(), 1)
		_dirty = false
		_uploads += 1
		field_uploaded.emit()
	_batches.position_bands(surface.tile_layer.global_transform, grid.has_water())
	if rebuilt:
		geometry_rebuilt.emit()


## Release mesh children, signal bindings and owned GPU resources, including on invalidation.
func clear(defer_free: bool = false) -> void:
	if is_instance_valid(_grid):
		_grid.changed.disconnect(_mark_dirty)
		_grid.geometry_changed.disconnect(_geometry_changed)
		_grid.geometry_replaced.disconnect(_invalidate_all)
	_batches.clear(defer_free)
	_grid = null
	_material = null
	_field = WetFloatTexture.new()
	_dirty = true


## Explicit read-only handles for host overlap tests; the addon retains lifecycle ownership.
func render_bands() -> Array[WetSurfaceRow]:
	return _batches.bands()


## Read-only GPU field for rendered validation; gameplay always samples the CPU simulation.
func saturation_texture() -> Texture2D:
	return _field.texture


## Diagnostic handle for overlap tests and regional geometry checks.
func band_for_cell(cell: Vector2i) -> WetSurfaceRow:
	return _batches.band_for_cell(cell, _band_rows)


## Allocation and upload counters for comparisons without inspecting implementation children.
func diagnostics() -> Dictionary:
	var cells: int = 0
	var vertices: int = 0
	var triangles: int = 0
	for band: WetSurfaceRow in render_bands():
		cells += band.cell_count
		vertices += band.vertex_count
		triangles += band.triangle_count
	return {"bands": render_bands().size(), "cells": cells,
		"patches": _batches.atlas.patch_count, "vertices": vertices, "triangles": triangles,
		"saturation_bytes": _field.byte_count, "topology_bytes": _batches.atlas.data.byte_count,
		"materials": int(_material != null), "data_textures": 2 if _material != null else 0,
		"uploads": _uploads}


func _mark_dirty() -> void:
	_dirty = true


func _geometry_changed(cells: Array[Vector2i]) -> void:
	_batches.invalidate(cells, _band_rows)


func _invalidate_all() -> void:
	_batches.invalidate_all()
