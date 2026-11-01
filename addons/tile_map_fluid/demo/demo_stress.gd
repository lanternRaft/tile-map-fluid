extends Node
## Owns benchmark timing, map transitions and restoration of engine settings.

## Demo composition root; all water references belong to this scene.
@export var demo: Node2D


func _select_speed(index: int) -> void:
	if demo.stress_active:
		_apply_speed(8 if index == 1 else 1)


func _apply_speed(speed: int) -> void:
	Engine.time_scale = float(speed)
	Engine.physics_ticks_per_second = demo.saved_ticks * speed
	Engine.max_physics_steps_per_frame = maxi(demo.saved_steps, 64)
	_reset_stress_sample()


func _reset_stress_sample() -> void:
	demo.sample_start = Time.get_ticks_usec() + 2000000
	demo.previous_frame_usec = 0
	demo.sample_frames = 0
	demo.sample_ticks = 0
	demo.slow_frames = 0
	demo.sample_worst_ms = 0.0
	demo.stress_report = "Warming up large-map test…"


func _sample_stress() -> void:
	# Wall time is independent of Engine.time_scale and catches dropped physics steps.
	var now: int = Time.get_ticks_usec()
	if now < demo.sample_start:
		demo.sample_ticks = 0
		return
	if demo.previous_frame_usec == 0:
		demo.sample_start = now
		demo.previous_frame_usec = now
		demo.sample_ticks = 0
		return
	var seconds: float = (now - demo.sample_start) / 1000000.0
	demo.sample_frames += 1
	var frame_ms: float = (now - demo.previous_frame_usec) / 1000.0
	demo.previous_frame_usec = now
	demo.sample_worst_ms = maxf(demo.sample_worst_ms, frame_ms)
	if frame_ms > 1000.0 / 120.0:
		demo.slow_frames += 1
	if seconds < 2.0:
		return
	var fps: float = demo.sample_frames / seconds
	var ticks: float = demo.sample_ticks / seconds
	var target: int = Engine.physics_ticks_per_second
	demo.stress_report = "128×128 | %.0f FPS | Physics %.0f/%d Hz | >8.33ms: %d | Worst %.2fms | %s" % [
		fps, ticks, target, demo.slow_frames, demo.sample_worst_ms,
		"ON TARGET" if fps >= 119.0 and ticks >= target * 0.99 else "BELOW TARGET"]
	demo.stress_report += "\nLive cone spray · %d hoses · %d receivers · %d barriers · stock physics" % [
		demo.workload.hose_count, demo.workload.receiver_count, demo.workload.obstacle_count]


func _toggle_stress(enabled: bool) -> void:
	demo.stress_active = enabled
	demo.get_node("Instructions/Performance").disabled = enabled
	demo.get_node("Instructions/Speed").disabled = not enabled
	demo.get_node("Receiver").automatic = enabled
	demo.droplets.clear()
	demo.spawn_accumulator = 0.0
	demo.route_time = 0.0
	if enabled:
		demo.get_node("Instructions/Performance").set_pressed(false)
		# Also handle programmatic entry while the preview is active.
		if demo.performance_active:
			demo._toggle_performance(false)
		demo.get_node("Floor").clear()
		for y: int in range(128):
			for x: int in range(128):
				demo.get_node("Floor").set_cell(Vector2i(x, y), 0, Vector2i.ZERO)
		demo.aim_bounds = Rect2(demo.get_node("Floor").position, Vector2(4096, 4096))
		demo.get_node("Receiver").movement_bounds = demo.aim_bounds.grow(-32.0)
		demo.get_node("Receiver").position = demo.aim_bounds.get_center()
		demo.workload.prepare(demo.emitter.surface, demo, demo.mushroom.get_parent(), demo.get_node("Wall"), demo.aim_bounds.get_center())
		demo.camera = Camera2D.new()
		demo.get_node("Receiver").add_child(demo.camera)
		# Keep the character clear of the fixed HUD.
		demo.camera.offset = Vector2(0, -32)
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
		Engine.max_fps = 0
		_apply_speed(8 if demo.get_node("Instructions/Speed").selected == 1 else 1)
	else:
		demo.workload.clear()
		demo.get_node("Floor").tile_map_data = demo.original_tiles
		demo.aim_bounds = Rect2(64, 128, 768, 384)
		demo.get_node("Receiver").movement_bounds = Rect2(84, 148, 728, 344)
		demo.get_node("Receiver").position = Vector2(288, 368)
		if is_instance_valid(demo.camera):
			demo.camera.enabled = false
			demo.camera.queue_free()
		_restore_timing()
	demo.get_node("Receiver").velocity = Vector2.ZERO
	demo.emitter.surface.refresh_coverage()
	demo.get_node("Instructions/Stress").text = "Stop performance test" if enabled else "Performance · live spray"


func _restore_timing() -> void:
	Engine.time_scale = demo.saved_time_scale
	Engine.physics_ticks_per_second = demo.saved_ticks
	Engine.max_physics_steps_per_frame = demo.saved_steps
	Engine.max_fps = demo.saved_fps
	DisplayServer.window_set_vsync_mode(demo.saved_vsync)


func _exit_tree() -> void:
	if demo.stress_active:
		print("Large-map test: ", demo.stress_report)
		_restore_timing()


## Wall-clock frame measurements for both the preview and the live workload.
func update_hud() -> void:
	if demo.stress_active:
		_sample_stress()
	var now: int = Time.get_ticks_usec()
	var delta: float = (now - demo.session_previous_usec) / 1000000.0 if demo.session_previous_usec > 0 else 0.0
	demo.session_previous_usec = now
	demo.elapsed += delta
	demo.frames += 1
	demo.worst_frame = maxf(demo.worst_frame, delta)
	demo.status.text = "Floor at character: %d%%    Character: %d%%    Mushroom: %d%%    Crate: %d%%    Contact: %s" % [
		roundi(demo.emitter.surface.saturation_at(demo.receiver.global_position) * 100.0),
		roundi(demo.receiver.saturation * 100.0), roundi(demo.mushroom.saturation * 100.0), roundi(demo.crate.saturation * 100.0),
		"grounded" if demo.receiver.contact_enabled else "lifted"]
	demo.get_node("Instructions/FPS").text = "FPS: %d    Frame: %.2f ms    %s average: %.1f FPS    Worst: %.2f ms    Draw calls: %d" % [
		Engine.get_frames_per_second(), delta * 1000.0,
		"All-wet" if demo.performance_active else "Session", demo.frames / maxf(demo.elapsed, 0.001),
		demo.worst_frame * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]

	if demo.stress_active:
		demo.get_node("Instructions/FPS").text = demo.stress_report


