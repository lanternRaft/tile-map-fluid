extends "res://tests/test_case.gd"

const Fixture: PackedScene = preload("res://tests/fixtures/wetness_presentation.tscn")


## Wetting and drying reuse geometry; coverage edits replace rows and clear removed floor.
func test_uploads_reuse_rows_until_coverage_changes() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	await get_tree().physics_frame
	await get_tree().physics_frame
	var presentation: WetSurfacePresentation = world.get_node("Presentation") \
		as WetSurfacePresentation
	var surface: WetSurface2D = presentation.surface
	var grid: WetGridSimulation = surface.simulation as WetGridSimulation
	surface.refresh_coverage()
	presentation.refresh()
	var parent: Node2D = presentation.presentation_parent
	var row: WetSurfaceRow = parent.get_child(0) as WetSurfaceRow
	var mesh: Mesh = row.mesh
	var revision: int = grid.geometry_revision
	var rebuilt: Array[bool] = []
	presentation.geometry_rebuilt.connect(func() -> void: rebuilt.append(true))
	surface.deposit(Vector2(48, 16), 0.8)
	presentation.refresh()
	check(absf((surface.saturation_at(Vector2(48, 16))) - (0.8)) <=  0.00001)
	grid.advance(0.2, 1.0)
	presentation.refresh()
	check(absf((surface.saturation_at(Vector2(48, 16))) - (0.6)) <=  0.00001)
	check((parent.get_child(0)) == (row))
	check((row.mesh) == (mesh))
	check((grid.geometry_revision) == (revision))
	check((rebuilt.size()) == (0))
	surface.tile_layer.erase_cell(Vector2i(1, 0))
	surface.refresh_coverage()
	presentation.refresh()
	check((rebuilt.size()) == (1))
	check(not (is_instance_valid(row)))
	check((surface.saturation_at(Vector2(48, 16))) == (0.0))


## Row transforms follow the referenced layer, even when their explicit sort parent is transformed.
func test_external_parent_transform_rebinding_and_removal() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var presentation: WetSurfacePresentation = world.get_node("Presentation") \
		as WetSurfacePresentation
	var layer: TileMapLayer = presentation.surface.tile_layer
	layer.transform = Transform2D(0.2, Vector2(1.4, 0.8), 0.0, Vector2(120, 80))
	presentation.presentation_parent.transform = Transform2D(0.4, Vector2(20, 40))
	presentation.refresh()
	var row: Node2D = presentation.presentation_parent.get_child(0) as Node2D
	check(row.global_transform.is_equal_approx(layer.global_transform))
	var other: WetSurface2D = world.get_node("OtherLayer/Surface") as WetSurface2D
	presentation.surface = other
	presentation.refresh()
	check(not (is_instance_valid(row)))
	var parent: Node2D = presentation.presentation_parent
	world.remove_child(presentation)
	check((parent.get_child_count()) == (0))
	world.add_child(presentation)
	presentation.refresh()
	check((parent.get_child_count()) == (1))
	other.simulation.free()
	presentation.refresh()
	check((parent.get_child_count()) == (0))


## A visual rebuild does not reclip floor physics or reset retained saturation.
func test_appearance_rebuild_preserves_simulation() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var presentation: WetSurfacePresentation = world.get_node("Presentation") \
		as WetSurfacePresentation
	var surface: WetSurface2D = presentation.surface
	surface.deposit(Vector2(48, 16), 0.75)
	var grid: WetGridSimulation = surface.simulation as WetGridSimulation
	var revision: int = grid.geometry_revision
	presentation.appearance = presentation.appearance.duplicate() as WetSurfaceAppearance
	presentation.appearance.tint = Color.RED
	presentation.rebuild()
	check((grid.geometry_revision) == (revision))
	check((surface.saturation_at(Vector2(48, 16))) == (0.75))
