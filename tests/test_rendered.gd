extends "res://tests/test_case.gd"

const Fixture: PackedScene = preload("res://tests/fixtures/wetness_presentation.tscn")
const TintFixture: PackedScene = preload("res://tests/fixtures/wettable_tint.tscn")
const Demo: PackedScene = preload("res://addons/tile_map_fluid/demo/demo.tscn")
const Pixels = preload("res://tests/draw_order_pixels.gd")


## Real full-cell batches and clipped polygons render the same field without crossing a thin wall.
func test_batched_and_clipped_pixels_follow_wetting_drying_and_removed_coverage() -> void:
	var view: SubViewport = _view()
	var world: Node2D = Fixture.instantiate() as Node2D
	world.position = Vector2(48, 48)
	view.add_child(world)
	var presentation: WetSurfacePresentation = world.get_node("Presentation") \
		as WetSurfacePresentation
	var surface: WetSurface2D = presentation.surface
	surface.tile_layer.hide()
	(world.get_node("OtherLayer") as TileMapLayer).hide()
	presentation.appearance = presentation.appearance.duplicate() as WetSurfaceAppearance
	presentation.appearance.tint = Color.WHITE
	await get_tree().physics_frame
	await get_tree().physics_frame
	surface.refresh_coverage()
	presentation.rebuild()
	var dry: Image = await Pixels.capture(view)
	check((dry.get_pixel(56, 64).a) == (0.0))
	surface.deposit(surface.tile_layer.to_global(Vector2(8, 16)), 1.0)
	presentation.refresh()
	var wet: Image = await Pixels.capture(view)
	check((wet.get_pixel(56, 64).a) > (0.7))
	check((wet.get_pixel(72, 64).a) == (0.0))
	check((wet.get_pixel(63, 64).a) == (0.0))
	# A later deposit in the adjacent full cell shares its seam with the right patch.
	surface.deposit(surface.tile_layer.to_global(Vector2(48, 16)), 1.0)
	presentation.refresh()
	wet = await Pixels.capture(view)
	check((wet.get_pixel(96, 64).a) > (0.7))
	var grid: WetGridSimulation = surface.simulation as WetGridSimulation
	grid.advance(0.5, 1.0)
	presentation.refresh()
	var drying: Image = await Pixels.capture(view)
	check((drying.get_pixel(96, 64).a) >= (0.3) and (drying.get_pixel(96, 64).a) <= ( 0.5))
	surface.tile_layer.erase_cell(Vector2i(1, 0))
	surface.refresh_coverage()
	presentation.refresh()
	var removed: Image = await Pixels.capture(view)
	check((removed.get_pixel(96, 64).a) == (0.0))


## Drying restores actual authored pixels, including nonwhite wrapper and descendant modulation.
func test_object_pixels_restore_after_independent_drying() -> void:
	var view: SubViewport = _view()
	var world: Node2D = TintFixture.instantiate() as Node2D
	world.position = Vector2(64, 64)
	view.add_child(world)
	var receiver: Wettable2D = world.get_node("Receiver") as Wettable2D
	receiver.set_physics_process(false)
	receiver.settings = receiver.settings.duplicate() as WettableSettings
	receiver.settings.dry_seconds = 1.0
	var dry: Image = await Pixels.capture(view)
	receiver.add_water(1.0)
	var wet: Image = await Pixels.capture(view)
	check((dry.get_pixel(64, 64).r - wet.get_pixel(64, 64).r) > (0.08))
	receiver.advance(1.0)
	var restored: Image = await Pixels.capture(view)
	check(restored.get_pixel(64, 64).is_equal_approx(dry.get_pixel(64, 64)))
	check(wet.get_pixel(128, 64).is_equal_approx(dry.get_pixel(128, 64)))


## Demo water remains below opaque receiver/wall artwork in its actual Y-sorted host band.
func test_demo_water_rows_preserve_receiver_and_wall_pixels() -> void:
	var view: SubViewport = _view()
	view.size = Vector2i(896, 640)
	var demo: Node2D = Demo.instantiate() as Node2D
	demo.set_process(false)
	view.add_child(demo)
	var presentation: WetSurfacePresentation = demo.emitter.surface.presentation
	var surface: WetSurface2D = presentation.surface
	var receiver: Wettable2D = demo.get_node("Receiver/Wettable") as Wettable2D
	var body: CharacterBody2D = demo.get_node("Receiver") as CharacterBody2D
	var emitter: WaterEmitter2D = demo.get_node("Source") as WaterEmitter2D
	for component: Node in [surface, receiver, body, emitter]:
		component.set_physics_process(false)
	var dry: Image = await Pixels.capture(view)
	surface.deposit(Vector2(288, 344), 1.0)
	surface.deposit(Vector2(430, 300), 1.0)
	presentation.refresh()
	var wet: Image = await Pixels.capture(view)
	check(wet.get_pixel(288, 344).is_equal_approx(dry.get_pixel(288, 344)))
	check(wet.get_pixel(439, 300).is_equal_approx(dry.get_pixel(439, 300)))
	check((dry.get_pixel(316, 344).r - wet.get_pixel(316, 344).r) > (0.1))


func _view() -> SubViewport:
	var view: SubViewport = track(SubViewport.new()) as SubViewport
	view.size = Vector2i(256, 192)
	view.world_2d = World2D.new()
	view.transparent_bg = true
	view.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(view)
	return view
