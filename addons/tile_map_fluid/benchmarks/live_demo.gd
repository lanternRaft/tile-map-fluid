extends SceneTree
## One trial of the interactive demo. tools/bench_demo.py supplies validated settings.

const Demo = preload("res://addons/tile_map_fluid/demo/demo.gd")
const Scene: PackedScene = preload("res://addons/tile_map_fluid/demo/demo.tscn")
const Metrics = preload("res://addons/tile_map_fluid/benchmarks/metrics.gd")

var config: Dictionary
var demo: Demo
var emissions: int = 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() != 1 or not FileAccess.file_exists(args[0]):
		printerr("Launch this benchmark with python3 tools/bench_demo.py")
		quit(2)
		return
	config = JSON.parse_string(FileAccess.get_file_as_string(args[0]))
	_run.call_deferred()


func _run() -> void:
	seed(int(config.seed))
	var setup_start := Time.get_ticks_usec()
	demo = Scene.instantiate()
	root.add_child(demo)
	await process_frame
	demo.workload.hose_count = int(config.hoses)
	demo.workload.receiver_count = int(config.receivers)
	demo.workload.obstacle_count = int(config.barriers)
	demo.get_node("Instructions/Speed").select(1 if config.speed == 8 else 0)
	demo.get_node("Instructions/Hoses").select(int(config.hoses) - 1)
	demo.get_node("Instructions/Stress").set_pressed(true)
	# Leave the same physics bodies, proxies, moving hose and scene composition in every case.
	var spray_on: bool = config.case not in ["no-spray", "neither"]
	for spray: TileFluidSpray2D in demo.workload.get_children():
		spray.active = spray_on
		spray.emitted.connect(func(_dose: float) -> void: emissions += 1)
	var receivers := demo.find_children("*", "TileFluidWettable2D", true, false)
	if config.case in ["no-contact-ticks", "neither"]:
		for receiver: Node in receivers:
			receiver.set_physics_process(false)
	var proxies := demo.find_children("*", "TileFluidReceiverProxy2D", true, false)
	var surface := demo.emitter.surface
	if not surface.validation_error().is_empty() or receivers.size() != int(config.receivers) + 3 \
			or proxies.size() != receivers.size() or demo.workload.get_child_count() != int(config.hoses):
		printerr("Unexpected live demo population or invalid surface.")
		quit(1)
		return
	var setup_us := Time.get_ticks_usec() - setup_start
	await physics_frame
	for tick: int in range(int(config.warmup_ticks)):
		await physics_frame
	# Use matching boundaries at both ends. A physics_frame precedes its node callbacks.
	var rendered: bool = config.mode == "rendered"
	if rendered:
		await process_frame
	var start_ticks := Engine.get_physics_frames()
	var start_emissions := emissions
	var uploads_before := int(surface.presentation.diagnostics().uploads)
	var intervals: Array[int] = []
	var started := Time.get_ticks_usec()
	var previous := started
	if rendered:
		while previous - started < float(config.seconds) * 1000000:
			await process_frame
			var now := Time.get_ticks_usec()
			intervals.append(now - previous)
			previous = now
	else:
		for tick: int in range(int(config.ticks)):
			await physics_frame
			var now := Time.get_ticks_usec()
			intervals.append(now - previous)
			previous = now
	var wall_us := previous - started
	var ticks := Engine.get_physics_frames() - start_ticks
	var doses := emissions - start_emissions
	var grid := surface.simulation as TileFluidGridSimulation
	if ticks < 1 or doses != ticks * (int(config.hoses) if spray_on else 0) or grid.cell_count < 1:
		printerr("Invalid workload: %d emissions in %d physics ticks." % [doses, ticks])
		quit(1)
		return
	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(grid.saturation_buffer().to_byte_array())
	var report := {
		"config": config, "setup_us": setup_us, "wall_us": wall_us, "ticks": ticks,
		"tick_rate": ticks * 1000000.0 / wall_us, "wall_us_per_tick": float(wall_us) / ticks,
		"interval_kind": "render_frame" if rendered else "fixed_tick_loop",
		"interval_us": intervals, "interval_summary_us": Metrics.summary(intervals),
		"emissions": doses, "field_sha256": digest.finish().hex_encode(),
		"receivers": receivers.size(), "proxies": proxies.size(), "cells": grid.cell_count,
		"has_water": grid.has_water(), "samples": grid.sample_count, "uploads": int(surface.presentation.diagnostics().uploads) - uploads_before,
		"dry_seconds": surface.settings.dry_seconds, "step_hz": demo.saved_ticks,
		"sample_spacing": surface.settings.sample_spacing, "engine": Engine.get_version_info().string,
		"os": OS.get_name(), "cpu": OS.get_processor_name(), "display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(), "gpu": RenderingServer.get_video_adapter_name(),
		"viewport": [root.size.x, root.size.y], "arguments": OS.get_cmdline_args(),
		"memory": Metrics.memory()
	}
	if rendered:
		var over_budget := 0
		for interval: int in intervals:
			if interval > 1000000.0 / 120:
				over_budget += 1
		report["fps"] = intervals.size() * 1000000.0 / wall_us
		report["over_budget_fraction"] = float(over_budget) / intervals.size()
		if not DisplayServer.window_can_draw() or DisplayServer.get_name() == "headless":
			printerr("Rendered benchmark requires a drawable window.")
			quit(1)
			return
	if config.edit_probe:
		var edits := _measure_door(surface, grid)
		if edits.is_empty():
			printerr("Regional rebuild did not reflect the door state.")
			quit(1)
			return
		report["regional_refresh_us"] = edits
		report["regional_summary_us"] = Metrics.summary(edits)
		digest.start(HashingContext.HASH_SHA256)
		digest.update(grid.saturation_buffer().to_byte_array())
		report["field_after_refresh_sha256"] = digest.finish().hex_encode()
	var file := FileAccess.open(config.output, FileAccess.WRITE)
	if file == null:
		printerr("Cannot write trial report: ", config.output)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	quit()

## Toggle a real stock-physics blocker. Keep collider setup, state checks and renderer
## submission outside the timer so the series measures only synchronous regional edits.
func _measure_door(surface: TileFluidSurface2D, grid: TileFluidGridSimulation) -> Array[int]:
	var bounds := Rect2(demo.aim_bounds.get_center(), Vector2(64, 64))
	var shape := RectangleShape2D.new()
	shape.size = Vector2(28, 52)
	var body := PhysicsServer2D.body_create()
	PhysicsServer2D.body_set_mode(body, PhysicsServer2D.BODY_MODE_STATIC)
	PhysicsServer2D.body_add_shape(body, shape.get_rid())
	PhysicsServer2D.body_set_state(body, PhysicsServer2D.BODY_STATE_TRANSFORM,
		Transform2D(0.0, bounds.get_center()))
	PhysicsServer2D.body_set_space(body, demo.get_world_2d().space)
	var edits: Array[int] = []
	for index: int in range(21):
		var closed := index % 2 == 1
		PhysicsServer2D.body_set_collision_layer(body, 1 if closed else 0)
		var before := Time.get_ticks_usec()
		var valid := surface.refresh_obstacles(bounds)
		var elapsed := Time.get_ticks_usec() - before
		var contact := TileFluidPreparedContact.new()
		grid.prepare_contact(surface.tile_layer.to_local(bounds.get_center()), contact)
		if not valid or (contact.patch_id == 0) != closed:
			edits.clear()
			break
		if index > 0:
			edits.append(elapsed)
	PhysicsServer2D.free_rid(body)
	return edits
