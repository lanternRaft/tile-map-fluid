extends "res://tests/test_case.gd"

const Fixture: PackedScene = preload("res://tests/fixtures/wetness_presentation.tscn")


## Removing the presenter subtree safely releases its mesh children.
func test_mesh_cleanup_during_subtree_removal() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var presentation: WetSurfacePresentation = world.get_node("Presentation") as WetSurfacePresentation
	presentation.rebuild()
	var bands: Array[WetSurfaceRow] = presentation.render_bands()
	remove_child(world)
	await get_tree().process_frame
	for band: WetSurfaceRow in bands:
		check(not is_instance_valid(band))
	add_child(world)
	presentation.refresh()
	check(not presentation.render_bands().is_empty())


## Bulk snapshots retain exact float32 contacts without allowing a reader to mutate gameplay.
func test_packed_snapshot_is_independent_and_matches_shared_contacts() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var surface: WetSurface2D = world.get_node("Layer/Surface") as WetSurface2D
	var grid: WetGridSimulation = surface.simulation as WetGridSimulation
	var before: PackedFloat32Array = grid.saturation_buffer()
	grid.deposit(Vector2(48, 16), 0.73)
	var wet: PackedFloat32Array = grid.saturation_buffer()
	var patch: WetFieldPatch = grid.cell_patches(Vector2i(1, 0))[0]
	check(patch.water(before).is_equal_approx(Color(0, 0, 0, 0)))
	check(patch.water(wet).is_equal_approx(grid.patch_water(patch)))
	wet[patch.corners[0]] = 0.0
	check(is_equal_approx(grid.patch_water(patch).r, 0.73))


## Local changes retain distant mesh identity and reuse topology slots across repeated edits.
func test_regional_mesh_replacement_and_bounded_topology() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var presentation: WetSurfacePresentation = world.get_node("Presentation") as WetSurfacePresentation
	var surface: WetSurface2D = presentation.surface
	var grid: WetGridSimulation = surface.simulation as WetGridSimulation
	surface.tile_layer.set_cell(Vector2i(0, 4), 0, Vector2i.ZERO)
	surface.refresh_coverage()
	presentation.refresh()
	var distant: WetSurfaceRow = presentation.band_for_cell(Vector2i(0, 4))
	var mesh: Mesh = distant.mesh
	var capacity: int = int(presentation.diagnostics().topology_bytes)
	for cycle: int in range(20):
		var rect: Rect2 = Rect2(0, 0, 12 if cycle % 2 == 0 else 14, 32)
		var pieces: Dictionary[Vector2i, Array] = {
			Vector2i.ZERO: [WetSurfaceCoverage.rectangle(rect)]}
		var near: WetSurfaceRow = presentation.band_for_cell(Vector2i.ZERO)
		grid.replace_cells(pieces, surface.tile_layer.global_transform, surface.settings)
		presentation.refresh()
		check(not is_instance_valid(near))
		check(presentation.band_for_cell(Vector2i(0, 4)) == distant)
		check(distant.mesh == mesh)
		check(int(presentation.diagnostics().topology_bytes) == capacity)
	var material: Material = distant.material
	for band: WetSurfaceRow in presentation.render_bands():
		check(band.material == material)
	check(int(presentation.diagnostics().materials) == 1)


## Reset clears old bands even without a replaced-cell list; restored coverage starts dry.
func test_reset_clears_geometry_and_dry_uploads_stop() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var presentation: WetSurfacePresentation = world.get_node("Presentation") as WetSurfacePresentation
	var surface: WetSurface2D = presentation.surface
	var grid: WetGridSimulation = surface.simulation as WetGridSimulation
	grid.deposit(Vector2(48, 16), 1.0)
	presentation.refresh()
	check(presentation.band_for_cell(Vector2i(1, 0)).visible)
	grid.advance(2.0, 1.0)
	presentation.refresh()
	check(not presentation.band_for_cell(Vector2i(1, 0)).visible)
	var uploads: int = int(presentation.diagnostics().uploads)
	for tick: int in range(10):
		grid.advance(1.0, 1.0)
		presentation.refresh()
	check(int(presentation.diagnostics().uploads) == uploads)
	grid.reset()
	presentation.refresh()
	check(presentation.render_bands().is_empty())
	surface.refresh_coverage()
	presentation.refresh()
	check(not grid.has_water())
	check(not presentation.render_bands().is_empty())


## Multirow batching is permitted only in an atomic host band; sorted hosts retain row anchors.
func test_presentation_controls_batching_and_negative_rows() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var presentation: WetSurfacePresentation = world.get_node("Presentation") as WetSurfacePresentation
	var surface: WetSurface2D = presentation.surface
	surface.tile_layer.set_cell(Vector2i(0, -2), 0, Vector2i.ZERO)
	surface.tile_layer.set_cell(Vector2i(0, -1), 0, Vector2i.ZERO)
	surface.refresh_coverage()
	presentation.appearance = presentation.appearance.duplicate() as WetSurfaceAppearance
	presentation.appearance.rows_per_batch = 8
	presentation.refresh()
	check(presentation.band_for_cell(Vector2i(0, -2)) != presentation.band_for_cell(Vector2i(0, -1)))
	presentation.y_sort_enabled = false
	presentation.refresh()
	check(presentation.band_for_cell(Vector2i(0, -2)) == presentation.band_for_cell(Vector2i(0, -1)))
	check(presentation.band_for_cell(Vector2i(0, -2)).anchor.y == -256.0)
