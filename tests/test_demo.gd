extends "res://tests/test_case.gd"

const Demo: PackedScene = preload("res://addons/tile_map_fluid/demo/demo.tscn")


func test_all_wet_toggle_and_particle_arrival() -> void:
	var demo: Node2D = track(Demo.instantiate())
	add_child(demo)
	await frames(2)
	demo.set_physics_process(false)
	var surface: WetSurface2D = demo.emitter.surface
	demo.droplets.append({"start": Vector2(280, 280), "end": Vector2(320, 320),
		"age": 0.0, "source": Vector2(280, 280), "landed": false})
	check(is_zero_approx(surface.saturation_at(Vector2(320, 320))))
	demo._physics_process(0.2)
	check(is_zero_approx(surface.saturation_at(Vector2(320, 320))), "No water before arrival")
	demo._physics_process(0.13)
	check(surface.saturation_at(Vector2(320, 320)) > 0.0, "Particle deposits on arrival")
	demo._toggle_performance(true)
	for point: Vector2 in [Vector2(80, 144), Vector2(800, 480), Vector2(600, 300)]:
		check(surface.saturation_at(point) > 0.99, "All-wet covers floor at %s: %f" % [point, surface.saturation_at(point)])
	check(is_zero_approx(surface.settings.dry_seconds))
	check(demo.mushroom.saturation > 0.99 and demo.crate.saturation > 0.99)
	demo._toggle_performance(false)
	check(is_equal_approx(surface.settings.dry_seconds, 18.0))


func test_solid_objects_direct_wetting_and_wet_braking() -> void:
	var demo: Node2D = track(Demo.instantiate())
	add_child(demo)
	await frames(2)
	demo.set_physics_process(false)
	check(demo.mushroom.get_parent() is StaticBody2D)
	check(demo.crate.get_parent() is RigidBody2D)
	demo.emitter.global_position = Vector2(740, 332)
	demo.footprint.global_position = demo.mushroom.global_position
	check(demo.emitter.emit_dose(0.5))
	check(demo.mushroom.saturation >= 0.5, "Static mushroom accepts direct spray")
	var character: CharacterBody2D = demo.get_node("Receiver")
	character.set_physics_process(false)
	character.velocity = Vector2(180, 0)
	character._physics_process(0.05)
	var dry_speed: float = character.velocity.length()
	demo._toggle_performance(true)
	character.velocity = Vector2(180, 0)
	character._physics_process(0.05)
	check(character.velocity.length() > dry_speed + 50.0, "Wet ground preserves momentum")


func test_character_pushes_wettable_crate() -> void:
	var demo: Node2D = track(Demo.instantiate())
	add_child(demo)
	await frames(2)
	demo.set_physics_process(false)
	var body: RigidBody2D = demo.crate.get_parent()
	demo.emitter.global_position = body.global_position + Vector2(100, 0)
	demo.footprint.global_position = body.global_position
	demo.emitter.emit_dose(0.5)
	check(demo.crate.saturation >= 0.5, "Crate accepts direct spray")
	var character: CharacterBody2D = demo.get_node("Receiver")
	character.set_physics_process(false)
	character.global_position = body.global_position + Vector2(-40, 12)
	var start_x: float = body.position.x
	for index: int in range(40):
		character.velocity = Vector2(180, 0)
		character._physics_process(1.0 / 120.0)
		await frames(1)
	check(body.position.x > start_x + 1.0, "Walking into crate pushes its rigid body")


func test_surface_owns_renderer_in_world_sorting_band() -> void:
	var demo: Node2D = track(Demo.instantiate())
	add_child(demo)
	await frames(2)
	var surface: WetSurface2D = demo.emitter.surface
	check(not demo.has_node("Presentation"), "No separately authored renderer")
	check(surface.presentation.get_parent() == surface, "Surface owns its renderer")
	surface.deposit(Vector2(320, 320), 1.0)
	surface.presentation.refresh()
	var bands: Array[WetSurfaceRow] = surface.presentation.render_bands()
	check(not bands.is_empty(), "Surface automatically renders water")
	check(bands[0].get_parent() == demo, "Rows share the world sorting band")
	var band: WetSurfaceRow = bands[0]
	remove_child(demo)
	surface.free()
	await frames(2)
	check(not is_instance_valid(band), "Removing surface removes its render rows")
