extends "res://tests/test_case.gd"

const Demo: PackedScene = preload("res://addons/tile_map_fluid/demo/demo.tscn")


func test_all_wet_toggle_and_particle_arrival() -> void:
	var demo: Node2D = track(Demo.instantiate())
	add_child(demo)
	await frames(2)
	demo.set_physics_process(false)
	var surface: TileFluidSurface2D = demo.emitter.surface
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
	check(is_equal_approx(surface.settings.dry_seconds, 72.0))


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
	var surface: TileFluidSurface2D = demo.emitter.surface
	check(not demo.has_node("Presentation"), "No separately authored renderer")
	check(surface.presentation.get_parent() == surface, "Surface owns its renderer")
	surface.deposit(Vector2(320, 320), 1.0)
	surface.presentation.refresh()
	var bands: Array[TileFluidSurfaceRow] = surface.presentation.render_bands()
	check(not bands.is_empty(), "Surface automatically renders water")
	check(bands[0].get_parent() == demo, "Rows share the world sorting band")
	var band: TileFluidSurfaceRow = bands[0]
	remove_child(demo)
	surface.free()
	await frames(2)
	check(not is_instance_valid(band), "Removing surface removes its render rows")


func test_large_map_autopilot_and_timing_restore() -> void:
	var ticks := Engine.physics_ticks_per_second
	var scale := Engine.time_scale
	var steps := Engine.max_physics_steps_per_frame
	var cap := Engine.max_fps
	var demo: Node2D = track(Demo.instantiate())
	add_child(demo)
	await frames(2)
	demo._toggle_stress(true)
	demo.set_physics_process(false)
	check(demo.workload.get_child_count() > 0, "Performance mode builds real cone sprays")
	check(demo.emitter.surface.settings.dry_seconds > 0.0, "Performance keeps drying enabled")
	var spray: TileFluidSpray2D = demo.workload.get_child(0)
	check(spray.active and spray.settings.rate > 0.0, "Benchmark uses an active production spray")
	var origin: Vector2 = demo.get_node("Receiver").global_position
	var point: Vector2 = origin + Vector2(84, 0)
	var before: float = demo.emitter.surface.saturation_at(point)
	demo.workload.advance(1.0 / 120.0, origin, 0.0)
	check(demo.emitter.surface.saturation_at(point) > before, "Real cone spray deposits water")
	demo.set_physics_process(true)
	check(demo.get_node("Floor").get_used_cells().size() == 128 * 128)
	check(Engine.physics_ticks_per_second == ticks * 8)
	check(is_equal_approx(Engine.time_scale, 8.0))
	check(demo.get_node("Receiver").automatic)
	check(demo.emitter.surface.contains_world_point(Vector2(4000, 4000)))
	var start: Vector2 = demo.get_node("Receiver").position
	await frames(12)
	check(demo.get_node("Receiver").position.distance_to(start) > 1.0, "Autopilot walks")
	check(not demo.droplets.is_empty(), "Autopilot sprays")
	demo._select_speed(0)
	check(Engine.physics_ticks_per_second == ticks)
	demo._toggle_stress(false)
	check(demo.workload.get_child_count() == 0, "Stopping removes benchmark sprays")
	check(demo.get_node("Floor").get_used_cells().size() == 24 * 12)
	check(not demo.get_node("Receiver").automatic)
	check(Engine.physics_ticks_per_second == ticks and Engine.time_scale == scale)
	check(Engine.max_physics_steps_per_frame == steps and Engine.max_fps == cap)


func test_performance_exits_preview_and_warmup_excludes_setup() -> void:
	var ticks: int = Engine.physics_ticks_per_second
	var scale: float = Engine.time_scale
	var demo: Node2D = track(Demo.instantiate())
	add_child(demo)
	await frames(2)
	demo._toggle_performance(true)
	demo._toggle_stress(true)
	check(not demo.performance_active, "Live test exits static preview")
	check(demo.emitter.surface.settings.dry_seconds > 0.0, "Preview cannot disable live drying")
	demo.sample_ticks = 10000
	demo._sample_stress()
	check(demo.sample_ticks == 0 and demo.sample_frames == 0, "Warmup excludes setup ticks and frames")
	demo._select_speed(0)
	check(demo.sample_frames == 0 and demo.previous_frame_usec == 0, "Speed change resets measurement")
	remove_child(demo)
	check(Engine.physics_ticks_per_second == ticks and Engine.time_scale == scale,
		"Closing an active test restores engine timing")
