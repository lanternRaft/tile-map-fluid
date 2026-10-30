extends "res://tests/test_case.gd"

const Fixture: PackedScene = preload("res://tests/fixtures/wetness_simulation.tscn")


## Equal active seconds deliver equal receiver doses; toggling never adds an initial pulse.
func test_continuous_doses_and_immediate_stop() -> void:
	var spray: WaterSpray2D = _spray()
	var receiver: Wettable2D = spray.receivers[0]
	spray.settings.rate = 0.2
	spray.active = true
	spray.advance(0.1)
	check(is_equal_approx(receiver.saturation, 0.02))
	spray.advance(0.2)
	check(is_equal_approx(receiver.saturation, 0.06))
	spray.active = false
	spray.advance(10.0)
	check(is_equal_approx(receiver.saturation, 0.06))
	spray.active = true
	spray.advance(0.0)
	spray.advance(NAN)
	spray.advance(-1.0)
	check(is_equal_approx(receiver.saturation, 0.06))
	spray.advance(0.1)
	check(is_equal_approx(receiver.saturation, 0.08))


## Independent splash overlap intentionally increases wetting as sampling becomes denser.
func test_dense_samples_accumulate_more_water() -> void:
	var dense: WaterSpray2D = _spray()
	var sparse: WaterSpray2D = _spray()
	dense.settings.spread = 0.0
	sparse.settings.spread = 0.0
	dense.settings.initial_radius = 32.0
	sparse.settings.initial_radius = 32.0
	dense.settings.sample_spacing = 28.0
	sparse.settings.sample_spacing = 56.0
	dense.emit_dose(0.01)
	sparse.emit_dose(0.01)
	var point: Vector2 = Vector2(48, 16)
	check(dense.surface.saturation_at(point) > sparse.surface.saturation_at(point))
	check(dense.surface.saturation_at(point) > 0.01)


## A wet splash center expands its radius into neighboring patches, beyond a narrow cone.
func test_saturated_centers_spread_farther() -> void:
	var dry: WaterSpray2D = _spray()
	var wet: WaterSpray2D = _spray()
	for spray: WaterSpray2D in [dry, wet]:
		spray.settings.spread = 0.0
		spray.settings.reach = 28.0
		spray.settings.initial_radius = 8.0
		spray.settings.maximum_radius = 64.0
	wet.surface.deposit(Vector2(28, 16), 0.9)
	dry.emit_dose(0.01)
	wet.emit_dose(0.01)
	check(is_zero_approx(dry.surface.saturation_at(Vector2(48, 72))))
	check(wet.surface.saturation_at(Vector2(48, 72)) > 0.0)
	check(is_zero_approx(wet.surface.saturation_at(Vector2(-48, 16))))


## Grounded wide objects accept edge probes; lifted objects fall back to their direct marker.
func test_shape_edges_marker_fallback_and_surface_isolation() -> void:
	var spray: WaterSpray2D = _spray()
	var receiver: Wettable2D = spray.receivers[0]
	receiver.position = Vector2(48, 48)
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(32, 64)
	shape.shape = rectangle
	receiver.add_child(shape)
	receiver.footprint = shape
	spray.settings.spread = 0.0
	spray.emit_dose(0.1)
	check(is_equal_approx(receiver.saturation, 0.1))
	receiver.contact_enabled = false
	spray.emit_dose(0.1)
	check(is_equal_approx(receiver.saturation, 0.1))
	receiver.position = Vector2(48, 16)
	spray.emit_dose(0.1)
	check(is_equal_approx(receiver.saturation, 0.2))
	receiver.surface = null
	spray.emit_dose(0.1)
	check(is_equal_approx(receiver.saturation, 0.2))


## A hard barrier blocks both sampled splash centers and shape-aware receiver hits.
func test_wall_blocks_floor_and_receivers() -> void:
	var spray: WaterSpray2D = _spray()
	var receiver: Wettable2D = spray.receivers[0]
	receiver.position = Vector2(112, 16)
	var wall: StaticBody2D = StaticBody2D.new()
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(8, 256)
	shape.shape = rectangle
	wall.position = Vector2(80, 16)
	wall.add_child(shape)
	spray.get_parent().add_child(wall)
	await frames(2)
	spray.settings.obstacle_mask = 1
	spray.surface.settings.obstacle_mask = 1
	spray.surface.refresh_obstacles()
	spray.emit_dose(0.1)
	check(is_zero_approx(receiver.saturation))
	check(is_zero_approx(spray.surface.saturation_at(Vector2(112, 16))))
	check(spray.surface.saturation_at(Vector2(48, 16)) > 0.0)


func _spray() -> WaterSpray2D:
	var fixture: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(fixture)
	var surface: WetSurface2D = fixture.get_node("Layer/Surface") as WetSurface2D
	var layer: TileMapLayer = surface.tile_layer
	for x: int in range(-2, 8):
		for y: int in range(-3, 4):
			layer.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	surface.settings = surface.settings.duplicate() as WetSurfaceSettings
	surface.settings.obstacle_mask = 0
	surface.refresh_coverage()
	var spray: WaterSpray2D = WaterSpray2D.new()
	spray.surface = surface
	spray.position = Vector2(0, 16)
	spray.settings.obstacle_mask = 0
	var receiver: Wettable2D = fixture.get_node("Receiver") as Wettable2D
	receiver.position = Vector2(48, 16)
	spray.receivers = [receiver, receiver]
	fixture.add_child(spray)
	spray.set_physics_process(false)
	return spray
