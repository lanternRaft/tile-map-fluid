extends "res://tests/test_case.gd"

const Fixture: PackedScene = preload("res://tests/fixtures/wetness_contracts.tscn")


## Identical tiles and overlapping surfaces share configuration, never mutable saturation.
func test_placements_and_instances_are_independent() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface") as TileFluidSurface2D
	var other: TileFluidSurface2D = world.get_node("OtherLayer/Surface") as TileFluidSurface2D
	check((surface.tile_layer.tile_set) == (other.tile_layer.tile_set))
	check((surface.settings) == (other.settings))
	check(surface.deposit(Vector2(16, 16), 0.4))
	check(absf((surface.saturation_at(Vector2(16, 16))) - (0.4)) <=  0.0001)
	check((surface.saturation_at(Vector2(48, 16))) == (0.0))
	check((other.saturation_at(Vector2(16, 16))) == (0.0))


## Miswiring a backend cannot make two surfaces advance the same mutable field.
func test_surfaces_cannot_borrow_another_instances_backend() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface") as TileFluidSurface2D
	var other: TileFluidSurface2D = world.get_node("OtherLayer/Surface") as TileFluidSurface2D
	other.settings = other.settings.duplicate() as TileFluidSurfaceSettings
	other.settings.dry_seconds = 1.0
	other.deposit(Vector2(16, 16), 1.0)
	surface.simulation = other.simulation
	surface.set_physics_process(true)
	await get_tree().physics_frame
	await get_tree().physics_frame
	check((surface.validation_error()).contains("own TileFluidSurfaceSimulation child"))
	check(not (surface.deposit(Vector2(16, 16), 1.0)))
	check((other.saturation_at(Vector2(16, 16))) == (1.0))


## Surface APIs use the referenced layer transform, including negative cells and scaled rooms.
func test_layer_coordinates_and_live_coverage() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	world.transform = Transform2D(0.3, Vector2(2, 1.5), 0.0, Vector2(-200, 90))
	add_child(world)
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface") as TileFluidSurface2D
	var layer: TileMapLayer = surface.tile_layer
	layer.set_cell(Vector2i(-1, -1), 0, Vector2i.ZERO)
	surface.refresh_coverage()
	surface.position = Vector2(100, 200)
	check(surface.contains_world_point(layer.to_global(Vector2(-16, -16))))
	var point: Vector2 = layer.to_global(Vector2(16, 16))
	check(surface.deposit(point, 0.5))
	layer.erase_cell(Vector2i(1, 0))
	surface.refresh_coverage()
	check((surface.saturation_at(point)) == (0.5))
	check(not (surface.contains_world_point(layer.to_global(Vector2(48, 16)))))
	check(not (surface.deposit(layer.to_global(Vector2(48, 16)), 1.0)))


## Multiple shapes and explicit discovery cannot multiply doses; another layer is untouched.
func test_union_emission_deduplicates_receivers_and_routes_one_surface() -> void:
	# Area monitoring must not inherit contacts queued for disposal by earlier fixtures.
	var view: SubViewport = track(SubViewport.new()) as SubViewport
	view.world_2d = World2D.new()
	var world: Node2D = Fixture.instantiate() as Node2D
	view.add_child(world)
	add_child(view)
	await frames(3)
	var emitter: TileFluidEmitter2D = world.get_node("Emitter") as TileFluidEmitter2D
	var receiver: TileFluidWettable2D = world.get_node("Receiver") as TileFluidWettable2D
	var other: TileFluidWettable2D = world.get_node("OtherReceiver") as TileFluidWettable2D
	var discovered: Array[TileFluidWettable2D] = emitter.footprint.receivers()
	check(discovered.has(receiver) and discovered.has(other))
	check(emitter.emit_dose(0.25))
	check((receiver.saturation) == (0.25))
	check((other.saturation) == (0.0))
	check((emitter.surface.saturation_at(Vector2(16, 16))) == (0.25))
	check(((world.get_node("OtherLayer/Surface") as TileFluidSurface2D)
		.saturation_at(Vector2(16, 16))) == (0.0))


## Continuous seconds and instant saturation doses stay distinct; release stops immediately.
func test_rate_partition_and_inactive_state() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var emitter: TileFluidEmitter2D = world.get_node("Emitter") as TileFluidEmitter2D
	var receiver: TileFluidWettable2D = world.get_node("Receiver") as TileFluidWettable2D
	emitter.settings.rate = 0.4
	emitter.set_active(true)
	for tick: int in range(120):
		emitter.advance(1.0 / 120.0)
	check(absf((receiver.saturation) - (0.4)) <=  0.0001)
	emitter.set_active(false)
	emitter.advance(5.0)
	check(absf((receiver.saturation) - (0.4)) <=  0.0001)
	check(emitter.emit_dose(0.2))
	check(absf((receiver.saturation) - (0.6)) <=  0.0001)


## Invalid point/dose/time input cannot contaminate surface or receiver state.
func test_invalid_inputs_and_clamping() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var emitter: TileFluidEmitter2D = world.get_node("Emitter") as TileFluidEmitter2D
	var receiver: TileFluidWettable2D = world.get_node("Receiver") as TileFluidWettable2D
	for dose: float in [NAN, INF, -1.0, 0.0]:
		check(not (emitter.emit_dose(dose)))
		check(not (receiver.add_water(dose)))
		check(not (emitter.surface.deposit(Vector2(16, 16), dose)))
	check(not (emitter.surface.deposit(Vector2(NAN, 0), 1.0)))
	check((emitter.surface.saturation_at(Vector2(INF, 0))) == (0.0))
	receiver.add_water(5.0)
	receiver.advance(NAN)
	check((receiver.saturation) == (1.0))


## A signal-only receiver remains directly wettable when lifted, and dries independently.
func test_contact_absorption_lift_and_direct_water() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var receiver: TileFluidWettable2D = world.get_node("Receiver") as TileFluidWettable2D
	receiver.settings.dry_seconds = 0.0
	receiver.settings.ground_absorption = 1.0
	receiver.surface.deposit(receiver.global_position, 1.0)
	receiver.advance(0.5)
	check((receiver.saturation) == (0.5))
	check((receiver.surface.saturation_at(receiver.global_position)) == (1.0))
	receiver.set_contact_enabled(false)
	receiver.advance(0.5)
	check((receiver.surface_saturation) == (0.0))
	check((receiver.saturation) == (0.5))
	check(receiver.add_water(0.2))
	check((receiver.saturation) == (0.7))
	receiver.settings.dry_seconds = 1.0
	receiver.advance(1.0)
	check((receiver.saturation) == (0.0))
