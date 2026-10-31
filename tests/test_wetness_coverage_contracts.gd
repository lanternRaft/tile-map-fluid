extends "res://tests/test_case.gd"

const Fixture: PackedScene = preload("res://tests/fixtures/wetness_contracts.tscn")


## A missing metadata layer has an explicit default; configured metadata must be boolean.
func test_metadata_defaults_and_boolean_opt_in() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface") as TileFluidSurface2D
	check(surface.contains_world_point(Vector2(16, 16)))
	surface.settings = surface.settings.duplicate() as TileFluidSurfaceSettings
	surface.settings.receives_water_by_default = false
	surface.refresh_coverage()
	check(not (surface.contains_world_point(Vector2(16, 16))))
	var tiles: TileSet = surface.tile_layer.tile_set.duplicate(true) as TileSet
	surface.tile_layer.tile_set = tiles
	tiles.add_custom_data_layer()
	tiles.set_custom_data_layer_name(0, &"receives_water")
	tiles.set_custom_data_layer_type(0, TYPE_BOOL)
	var data: TileData = surface.tile_layer.get_cell_tile_data(Vector2i.ZERO)
	data.set_custom_data(&"receives_water", true)
	surface.refresh_coverage()
	check(surface.contains_world_point(Vector2(16, 16)))
	check(surface.contains_world_point(Vector2(48, 16)))
	tiles.set_custom_data_layer_type(0, TYPE_FLOAT)
	check(not (surface.refresh_coverage()))
	check((surface.validation_error()).contains("boolean"))
	check(not (surface.deposit(Vector2(16, 16), 1.0)))


## Unsupported tile layouts must not get rectangular water.
func test_unsupported_layers_and_unbound_backend_fail_clearly() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface") as TileFluidSurface2D
	var tiles: TileSet = surface.tile_layer.tile_set.duplicate(true) as TileSet
	surface.tile_layer.tile_set = tiles
	tiles.tile_shape = TileSet.TILE_SHAPE_ISOMETRIC
	check(not (surface.refresh_coverage()))
	check((surface.validation_error()).contains("rectangular"))
	tiles.tile_shape = TileSet.TILE_SHAPE_SQUARE
	surface.refresh_coverage()
	surface.simulation = null
	check((surface.validation_error()).contains("Simulation child"))
	check(not (surface.deposit(Vector2(16, 16), 1.0)))


## Tile edits preserve retained water and initialize newly occupied tiles dry.
func test_tile_holes_and_live_openings() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface") as TileFluidSurface2D
	var layer: TileMapLayer = surface.tile_layer
	layer.clear()
	layer.set_cell(Vector2i.ZERO, 0, Vector2i.ZERO)
	surface.refresh_coverage()
	check(surface.contains_world_point(Vector2(16, 16)))
	check(not surface.contains_world_point(Vector2(48, 16)))
	surface.deposit(Vector2(16, 16), 0.5)
	layer.set_cell(Vector2i(1, 0), 0, Vector2i.ZERO)
	surface.refresh_coverage()
	check(surface.contains_world_point(Vector2(48, 16)))
	check(surface.saturation_at(Vector2(48, 16)) == 0.0)
	check(surface.saturation_at(Vector2(16, 16)) > 0.0)
