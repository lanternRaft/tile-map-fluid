extends "res://tests/test_case.gd"

const Surface: PackedScene = preload("res://addons/tile_map_fluid/wet_surface.tscn")


func test_surface_configures_rigid_body_traction_and_restores_dry_damping() -> void:
	var surface: TileFluidSurface2D = _surface(false)
	surface.traction_enabled = true
	surface.wet_drag_multiplier = 0.1
	surface.splash(Vector2(16, 16), 1.0)
	var body: RigidBody2D = track(RigidBody2D.new()) as RigidBody2D
	body.linear_damp = 8.0
	body.angular_damp = 4.0
	body.position = Vector2(16, 16)
	body.gravity_scale = 0.0
	body.freeze = true
	var contact: TileFluidWettable2D = TileFluidWettable2D.new()
	contact.surface = surface
	contact.traction_body = body
	body.add_child(contact)
	add_child(body)
	contact.advance(0.1)
	check(is_equal_approx(body.linear_damp, 0.8))
	check(body.angular_damp == 4.0)
	surface.traction_affects_rotation = true
	contact.advance(0.1)
	check(is_equal_approx(body.angular_damp, 0.4))
	# Host changes to dry drag must survive wetting and contact transitions.
	body.linear_damp = 12.0
	contact.advance(0.1)
	check(is_equal_approx(body.linear_damp, 1.2))
	contact.set_contact_enabled(false)
	contact.advance(0.1)
	check(body.linear_damp == 12.0)
	check(body.angular_damp == 4.0)
	contact.set_contact_enabled(true)
	surface.traction_enabled = false
	contact.advance(0.1)
	check(body.linear_damp == 12.0)
	check(surface.traction_multiplier(NAN) == 1.0)


func test_staged_surface_matches_immediate_and_has_no_automatic_clock() -> void:
	var immediate: TileFluidSurface2D = _surface(false)
	var staged: TileFluidSurface2D = _surface(true)
	var grid: TileFluidGridSimulation = staged.simulation as TileFluidGridSimulation
	check(grid.sample_count == 0)
	var complete: bool = false
	for step: int in range(8):
		if staged.lifecycle.advance_initialization():
			complete = true
			break
	check(complete)
	check(grid.cell_count == (immediate.simulation as TileFluidGridSimulation).cell_count)
	check(staged.splash(Vector2(16, 16), 1.0))
	check(immediate.splash(Vector2(16, 16), 1.0))
	check(staged.saturation_at(Vector2(16, 16)) == immediate.saturation_at(Vector2(16, 16)))
	staged.lifecycle.staged = true
	staged._physics_process(100.0)
	check(staged.saturation_at(Vector2(16, 16)) == 1.0)
	staged.lifecycle.rebuild()
	complete = false
	for step: int in range(8):
		if staged.lifecycle.advance_initialization():
			complete = true
			break
	check(complete)
	check(staged.saturation_at(Vector2(16, 16)) == 0.0)


func test_obstacle_requests_coalesce_and_teardown_cancels_pending_work() -> void:
	var surface: TileFluidSurface2D = _surface(false)
	await frames(3)
	var grid: TileFluidGridSimulation = surface.simulation as TileFluidGridSimulation
	var replacements: Array[int] = []
	grid.geometry_changed.connect(func(cells: Array[Vector2i]) -> void:
		replacements.append(cells.size()))
	for request: int in range(8):
		surface.lifecycle.request_obstacles(Rect2(0, 0, 32, 32))
	await frames(3)
	check(replacements.size() == 1)
	surface.lifecycle.request_obstacles()
	surface.free()
	await frames(3)


func _surface(staged: bool) -> TileFluidSurface2D:
	var surface: TileFluidSurface2D = track(Surface.instantiate()) as TileFluidSurface2D
	var fixture: Node2D = load("res://tests/fixtures/wetness_simulation.tscn").instantiate() as Node2D
	var layer: TileMapLayer = fixture.get_node("Layer") as TileMapLayer
	surface.tile_layer.tile_set = layer.tile_set
	for y: int in range(3):
		for x: int in range(4):
			surface.tile_layer.set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
	fixture.free()
	surface.lifecycle.staged = staged
	surface.lifecycle.anchor_to_coverage = true
	surface.settings.obstacle_mask = 0
	add_child(surface)
	return surface
