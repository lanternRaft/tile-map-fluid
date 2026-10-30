extends "res://tests/test_case.gd"

const Fixture: PackedScene = preload("res://tests/fixtures/wetness_simulation.tscn")


## Index buckets preserve filled-polygon edge semantics, including exterior lattice seams.
func test_tile_boundary_queries_stay_inclusive() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var surface: WetSurface2D = world.get_node("Layer/Surface") as WetSurface2D
	surface.tile_layer.clear()
	surface.tile_layer.set_cell(Vector2i.ZERO, 0, Vector2i.ZERO)
	surface.refresh_coverage()
	check(surface.contains_world_point(Vector2(32, 16)))
	check(surface.contains_world_point(Vector2.ZERO))
	check(not surface.contains_world_point(Vector2(32.1, 16)))


## Occupied tiles define coverage; holes and blocking collisions remain independent of artwork.
func test_tile_holes_and_regional_colliders() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var surface: WetSurface2D = world.get_node("Layer/Surface") as WetSurface2D
	var layer: TileMapLayer = surface.tile_layer
	layer.set_cell(Vector2i(0, 2), 0, Vector2i.ZERO)
	surface.refresh_coverage()
	var added: Vector2 = layer.to_global(Vector2(16, 80))
	check(surface.contains_world_point(added))
	check(not surface.contains_world_point(Vector2(16, 48)))
	check(surface.deposit(added, 0.75))
	var retained: Vector2 = layer.to_global(Vector2(16, 16))
	surface.deposit(retained, 0.5)
	var grid: WetGridSimulation = surface.simulation as WetGridSimulation
	var far: WetFieldPatch = grid.cell_patches(Vector2i.ZERO)[0]
	var wall: StaticBody2D = StaticBody2D.new()
	wall.position = added
	var shape: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(8, 8)
	shape.shape = rectangle
	wall.add_child(shape)
	world.add_child(wall)
	await frames(2)
	surface.refresh_obstacles(Rect2(added - Vector2.ONE * 5, Vector2.ONE * 10))
	check(surface.saturation_at(added) == 0.0)
	check(grid.cell_patches(Vector2i.ZERO)[0] == far)
	check(surface.saturation_at(retained) > 0.0)
	wall.collision_layer = 0
	await frames(2)
	surface.refresh_obstacles(Rect2(added - Vector2.ONE * 5, Vector2.ONE * 10))
	check(surface.deposit(added, 1.0))
	check(surface.saturation_at(added) > 0.0)
	layer.erase_cell(Vector2i(0, 2))
	surface.refresh_coverage()
	check(surface.saturation_at(added) == 0.0)
	check(surface.saturation_at(retained) > 0.0)


## Public receiver sampling stays local at 10,000 tiles, dry and wet, with 100 contacts.
func test_public_contact_queries_do_not_scale_with_floor_area() -> void:
	var rows: Array[Dictionary] = []
	for size: int in [8, 100]:
		var world: Node2D = track(Fixture.instantiate()) as Node2D
		add_child(world)
		var surface: WetSurface2D = world.get_node("Layer/Surface") as WetSurface2D
		surface.set_physics_process(false)
		var layer: TileMapLayer = surface.tile_layer
		layer.clear()
		for y: int in range(size):
			for x: int in range(size):
				layer.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
		surface.refresh_coverage()
		var receivers: Array[Wettable2D] = []
		for index: int in range(100):
			var receiver: Wettable2D = Wettable2D.new()
			receiver.surface = surface
			receiver.position = Vector2(size * 32 - 16, size * 32 - 16)
			receiver.set_physics_process(false)
			world.add_child(receiver)
			receivers.append(receiver)
		var costs: Array[int] = []
		for wet: bool in [false, true]:
			if wet:
				surface.deposit(receivers[0].global_position, 1.0)
			var times: Array[int] = []
			for pass_index: int in range(5):
				var start: int = Time.get_ticks_usec()
				for receiver: Wettable2D in receivers:
					receiver.advance(1.0 / 120.0)
					surface.saturation_at(receiver.global_position)
				times.append(Time.get_ticks_usec() - start)
			times.sort()
			costs.append(times[2])
			var saturation: float = receivers[0].surface_saturation
			check(saturation > 0.0 if wet else saturation == 0.0)
		rows.append({ "tiles": size * size, "dry_us": costs[0], "wet_us": costs[1] })
		world.free()
	# Generous relative bounds tolerate noisy hosts while rejecting a full-floor scan per contact.
	check(rows[1].dry_us < rows[0].dry_us * 8 + 1000, str(rows))
	check(rows[1].wet_us < rows[0].wet_us * 8 + 1000, str(rows))
	var directory: String = "res://reports/performance"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	FileAccess.open(directory.path_join("tile_contacts.json"), FileAccess.WRITE).store_string(
		JSON.stringify(rows, "\t"))
