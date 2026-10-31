extends Node2D
## Editor-wired room; only the benchmark clock advances surfaces, emitters and receivers.

const Settings = preload("res://addons/tile_map_fluid/benchmarks/settings.gd")
const ReceiverScene: PackedScene = preload("res://addons/tile_map_fluid/demo/demo_receiver.tscn")
const ReceiverHost = preload("res://addons/tile_map_fluid/demo/demo_receiver.gd")

## Vanilla coordinate and visual layer owned by this scene.
@export var layer: TileMapLayer
## Sole saturation owner and its optional presentation.
@export var surface: TileFluidSurface2D
## Uploads can be timed explicitly without changing addon code.
@export var presentation: TileFluidSurfacePresentation
## Shared authored footprint used by the floor and direct receiver paths.
@export var footprint: TileFluidFootprint2D
## Ordinary emitter, including discovery and direct wetting costs.
@export var emitter: TileFluidEmitter2D
## Editor-visible footprint radius resource.
@export var circle: CircleShape2D
## Status is outside the physical world sort tree.
@export var status: Label

## Bodies/artwork remain present even when their contact workload is disabled.
var receivers: Array[TileFluidWettable2D] = []
## Stable clipped geometry counters for output.
var counts: Dictionary = {}
var _settings: Settings
var _grid: TileFluidGridSimulation
var _actors: Array[ReceiverHost] = []


## Configure before tree entry; never edits a shared production Resource.
func configure(settings: Settings, spacing: float) -> void:
	_settings = settings
	# The game's vector importer cannot supply sampled TileSet/shader textures. Rasterize
	# the same addon SVGs so this workload matches a stock-Godot copy of the addon.
	layer.tile_set = layer.tile_set.duplicate(true) as TileSet
	var atlas: TileSetAtlasSource = layer.tile_set.get_source(0) as TileSetAtlasSource
	atlas.texture = _raster("res://addons/tile_map_fluid/demo/floor.svg")
	presentation.appearance = presentation.appearance.duplicate(true) as TileFluidSurfaceAppearance
	presentation.appearance.texture = _raster("res://addons/tile_map_fluid/assets/wet_surface.svg")
	surface.settings = surface.settings.duplicate(true) as TileFluidSurfaceSettings
	surface.settings.sample_spacing = spacing
	surface.settings.dry_seconds = settings.dry_seconds
	circle.radius = settings.radius
	emitter.settings = emitter.settings.duplicate(true) as TileFluidEmitterSettings
	emitter.settings.rate = settings.rate
	for y: int in range(settings.tiles.position.y, settings.tiles.end.y):
		for x: int in range(settings.tiles.position.x, settings.tiles.end.x):
			var cell: Vector2i = Vector2i(x, y)
			if not settings.hole.has_point(cell) and x != settings.gap_column:
				layer.set_cell(cell, 0, Vector2i.ZERO)
	for index: int in range(settings.receiver_count):
		var actor: ReceiverHost = ReceiverScene.instantiate() as ReceiverHost
		actor.position = Vector2(110 + (index % 20) * 40, 170 + floori(index / 20.0) * 70)
		actor.set_physics_process(false)
		actor.set_process_unhandled_key_input(false)
		var receiver: TileFluidWettable2D = actor.receiver
		receiver.surface = surface
		receiver.set_physics_process(false)
		add_child(actor)
		_actors.append(actor)
		receivers.append(receiver)
		emitter.receivers.append(receiver)
	surface.set_physics_process(false)
	emitter.set_physics_process(false)
	presentation.set_process(false)


## Reveal the exact floor transition in captures after timed crowded rendering has finished.
func show_receivers(enabled: bool) -> void:
	for actor: ReceiverHost in _actors:
		actor.visible = enabled


## Called after physics registration so the angled wall clips all compared fields equally.
func prepare(workload: String) -> void:
	_grid = surface.simulation as TileFluidGridSimulation
	_grid.reset()
	surface.refresh_coverage()
	if workload in ["saturated_drying", "crowded_contacts", "geometry_updates"]:
		for cell: Vector2i in _grid.covered_cells():
			for patch: TileFluidFieldPatch in _grid.cell_patches(cell):
				_grid.deposit(patch.interior(patch.bounds.get_center()), 1.0)
	presentation.refresh()
	var patches: int = 0
	var vertices: int = 0
	for cell: Vector2i in _grid.covered_cells():
		for patch: TileFluidFieldPatch in _grid.cell_patches(cell):
			patches += 1
			vertices += patch.polygon.size()
	counts = { "cells": _grid.cell_count, "samples": _grid.sample_count, "patches": patches,
		"polygon_vertices": vertices, "water_buffer_bytes": _grid.sample_count * 4,
		"receivers": receivers.size(), "tiles": layer.get_used_cells().size() }


## One deterministic step; timers separate deposits, drying, contact reads, and CPU uploads.
func step(workload: String, tick: int) -> Dictionary:
	var costs: Dictionary = {}
	var delta: float = 1.0 / _settings.ticks_per_second
	var time: float = tick * delta
	status.text = "%s px · %s · %.1f s" % [surface.settings.sample_spacing, workload, time]
	footprint.position = Vector2(520 + sin(time * 0.7) * 350, 350 + sin(time * 1.1) * 180)
	var start: int = Time.get_ticks_usec()
	if workload == "moving_spray":
		emitter.emit_dose(_settings.rate * delta)
	elif workload == "game_splash":
		_grid.splash(layer.to_local(footprint.global_position), _settings.rate * delta,
			_settings.radius, surface.settings.obstacle_mask)
	costs.deposits = Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	_grid.advance(delta, _settings.dry_seconds)
	costs.simulation = Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	if workload == "crowded_contacts":
		for receiver: TileFluidWettable2D in receivers:
			receiver.advance(delta)
	costs.receiver_contacts = Time.get_ticks_usec() - start
	start = Time.get_ticks_usec()
	for index: int in range(receivers.size() if workload == "crowded_contacts" else 4):
		surface.saturation_at(receivers[index % receivers.size()].global_position)
	costs.traction_queries = Time.get_ticks_usec() - start
	if workload == "geometry_updates" and tick % _settings.ticks_per_second == 0:
		start = Time.get_ticks_usec()
		var cell: Vector2i = Vector2i(12, 8)
		if layer.get_cell_source_id(cell) == -1:
			layer.set_cell(cell, 0, Vector2i.ZERO)
		else:
			layer.erase_cell(cell)
		surface.refresh_coverage()
		costs.geometry_event = Time.get_ticks_usec() - start
	# Same 20 Hz uploads for every spacing, with rebuilding isolated from steady uploads.
	if tick % maxi(1, roundi(_settings.ticks_per_second / 20.0)) == 0:
		start = Time.get_ticks_usec()
		presentation.refresh()
		costs["rebuild_upload_event" if costs.has("geometry_event") else "upload_event"] = \
			Time.get_ticks_usec() - start
	return costs


func _raster(path: String) -> ImageTexture:
	var image: Image = Image.new()
	image.load_svg_from_string(FileAccess.get_file_as_string(path))
	return ImageTexture.create_from_image(image)
