extends "res://tests/test_case.gd"

const Fixture: PackedScene = preload("res://tests/fixtures/wetness_simulation.tscn")
const Provider = preload("res://tests/fixtures/wetness_contract_provider.gd")


## Golden 32px values retain the pre-extraction bilinear seam and evaporation behavior.
func test_existing_resolution_matches_original_field() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var surface: WetSurface2D = world.get_node("Layer/Surface") as WetSurface2D
	surface.deposit(Vector2(16, 16), 0.4)
	for x: int in range(1, 64, 3):
		var expected: float = 0.4 if x <= 32 else lerpf(0.4, 0.0, float(x - 32) / 32.0)
		check(absf((surface.saturation_at(Vector2(x, 16))) - (expected)) <=  0.0001)
	surface.deposit(Vector2(48, 16), 0.4)
	surface.simulation.advance(0.5, 2.0)
	for x: int in range(1, 64, 3):
		var expected: float = lerpf(0.15, 0.55, float(x) / 32.0) if x <= 32 \
			else lerpf(0.55, 0.15, float(x - 32) / 32.0)
		check(absf((surface.saturation_at(Vector2(x, 16))) - (expected)) <=  0.0001)


## Point deposits retain the original bilinear seam behavior and never mutate another surface.
func test_clamping_evaporation_and_bounded_storage() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var surface: WetSurface2D = world.get_node("Layer/Surface") as WetSurface2D
	var other: WetSurface2D = world.get_node("OtherLayer/Surface") as WetSurface2D
	var field: WetGridSimulation = surface.simulation as WetGridSimulation
	var samples: int = field.sample_count
	surface.deposit(Vector2(16, 16), 0.4)
	check(absf((surface.saturation_at(Vector2(16, 16))) - (0.4)) <=  0.0001)
	check(absf((surface.saturation_at(Vector2(48, 16))) - (0.2)) <=  0.0001)
	check((other.saturation_at(Vector2(16, 16))) == (0.0))
	for index: int in range(100):
		surface.deposit(Vector2(16, 16), 1.0)
	check((surface.saturation_at(Vector2(16, 16))) == (1.0))
	check((field.sample_count) == (samples))
	field.advance(NAN, 2.0)
	field.advance(1.0, 0.0)
	check((field.sample(Vector2(16, 16))) == (1.0))
	field.advance(0.5, 2.0)
	check((field.sample(Vector2(16, 16))) == (0.75))
	field.advance(2.0, 2.0)
	check((field.sample(Vector2(16, 16))) == (0.0))


## Lattice identity survives envelope changes, negative tiles, and layer/component transforms.
func test_changed_coverage_preserves_unaffected_cells_and_additions_are_dry() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	world.transform = Transform2D(0.3, Vector2(2, 1.5), 0.0, Vector2(-200, 90))
	add_child(world)
	var surface: WetSurface2D = world.get_node("Layer/Surface") as WetSurface2D
	var layer: TileMapLayer = surface.tile_layer
	surface.position = Vector2(900, 400)
	var point: Vector2 = layer.to_global(Vector2(16, 16))
	surface.deposit(point, 0.5)
	layer.set_cell(Vector2i(-1, -1), 0, Vector2i.ZERO)
	layer.set_cell(Vector2i(0, 1), 0, Vector2i.ZERO)
	surface.refresh_coverage()
	check((surface.saturation_at(point)) == (0.5))
	check((surface.saturation_at(layer.to_global(Vector2(16, 48)))) == (0.0))
	check((surface.saturation_at(layer.to_global(Vector2(-16, -16)))) == (0.0))
	layer.erase_cell(Vector2i.ZERO)
	surface.refresh_coverage()
	check((surface.saturation_at(point)) == (0.0))
	layer.set_cell(Vector2i.ZERO, 0, Vector2i.ZERO)
	surface.refresh_coverage()
	check((surface.saturation_at(point)) == (0.0))
	world.position += Vector2(60, -30)
	check(absf((surface.saturation_at(layer.to_global(Vector2(48, 16)))) - (0.25)) <=  0.0001)


## Holes, thin gaps, disconnected islands and overlapping providers never bridge dry space.
func test_clipped_islands_and_live_provider_changes() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var surface: WetSurface2D = world.get_node("Layer/Surface") as WetSurface2D
	var provider: Provider = Provider.new()
	world.add_child(provider)
	var left: PackedVector2Array = WetSurfaceCoverage.rectangle(Rect2(-7, 3, 21, 26))
	var right: PackedVector2Array = WetSurfaceCoverage.rectangle(Rect2(16, 3, 13, 26))
	provider.pieces = [left, left, right,
		WetSurfaceCoverage.rectangle(Rect2(64, 64, 9, 11))]
	surface.coverage_provider = provider
	surface.refresh_coverage()
	surface.deposit(Vector2(8, 16), 1.0)
	check((surface.saturation_at(Vector2(8, 16))) == (1.0))
	check((surface.saturation_at(Vector2(15, 16))) == (0.0))
	check((surface.saturation_at(Vector2(20, 16))) == (0.0))
	check((surface.saturation_at(Vector2(68, 68))) == (0.0))
	provider.pieces = [left]
	provider.notify_coverage_changed()
	check((surface.saturation_at(Vector2(8, 16))) == (1.0))
	provider.pieces = [left, right]
	provider.notify_coverage_changed()
	check((surface.saturation_at(Vector2(20, 16))) == (0.0))
	provider.pieces = [PackedVector2Array([Vector2.ZERO, Vector2.ONE, Vector2(INF, 0)])]
	provider.notify_coverage_changed()
	check(not (surface.refresh_coverage()))
	provider.pieces = [left]
	provider.notify_coverage_changed()
	check((surface.saturation_at(Vector2(8, 16))) == (0.0))


## Sparse envelopes stay bounded, and unreasonable coverage fails with an actionable reason.
func test_allocation_limit_fails_closed_and_recovers_dry() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var surface: WetSurface2D = world.get_node("Layer/Surface") as WetSurface2D
	surface.deposit(Vector2(16, 16), 1.0)
	surface.settings = surface.settings.duplicate() as WetSurfaceSettings
	surface.settings.maximum_cells = 1
	check(not (surface.refresh_coverage()))
	check((surface.validation_error()).contains("maximum_cells"))
	check((surface.saturation_at(Vector2(16, 16))) == (0.0))
	surface.settings.maximum_cells = 8
	check(surface.refresh_coverage())
	check((surface.saturation_at(Vector2(16, 16))) == (0.0))
	surface.tile_layer.set_cell(Vector2i(1000, -1000), 0, Vector2i.ZERO)
	check(surface.refresh_coverage())
	var field: WetGridSimulation = surface.simulation as WetGridSimulation
	check((field.cell_count) == (3))
