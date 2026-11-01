extends SceneTree
## Actual demo, deterministic fixed-tick CPU runs or wall-clock rendered trials.
var demo: Node
var ticks: int = 0
var start: int
var previous: int
var frames: Array[float] = []
var args: Dictionary = {}
var warm: int = 240
var measured_ticks: int = 0
var tick_operations: Array = []
var last_totals: Dictionary = {}
var replay: Array = []
var receivers: Array[Node] = []
var startup: int
var setup_usec: int
var event_queue: Array = []
var all_start: int = Time.get_ticks_usec()

func _initialize() -> void:
	for arg: String in OS.get_cmdline_user_args():
		var pair := arg.split("=", true, 1)
		if pair.size() == 2:
			args[pair[0]] = pair[1]
	seed(13463)
	_run.call_deferred()

func _run() -> void:
	startup = Time.get_ticks_usec()
	demo = load("res://addons/tile_map_fluid/demo/demo.tscn").instantiate()
	root.add_child(demo)
	await process_frame
	demo.workload.hose_count = int(args.get("hoses", "1"))
	demo._toggle_stress(true)
	demo.get_node("StressController")._apply_speed(int(args.get("speed", "1")))
	setup_usec = Time.get_ticks_usec() - startup
	for node: Node in root.find_children("*", "Area2D", true, false):
		if node.has_method("refresh_contact"):
			receivers.append(node)
	if args.get("replay", "false") == "true":
		for index: int in range(receivers.size()):
			var receiver: Node = receivers[index]
			receiver.changed.connect(func(value: float) -> void: event_queue.append([index, "changed", value]))
			receiver.water_added.connect(func(value: float) -> void: event_queue.append([index, "water", value]))
			receiver.contact_changed.connect(func(value: bool) -> void: event_queue.append([index, "contact", value]))
		demo.emitter.surface.changed.connect(func() -> void: event_queue.append(["floor", demo.emitter.surface.saturation_at(demo.receiver.global_position)]))
	physics_frame.connect(_tick)
	process_frame.connect(_frame)

func _tick() -> void:
	if args.get("moving", "false") == "true":
		for index: int in range(demo.workload.receiver_count):
			var body: Node2D = demo.workload._objects[index]
			body.global_position = demo.aim_bounds.get_center() + Vector2(index % 8 - 3.5, floori(index / 8.0) - 3.5) * 128.0 + Vector2(sin(ticks / 120.0), cos(ticks / 120.0)) * 24.0
	if ticks > warm and root.has_node("Stage1Metrics"):
		var totals: Dictionary = root.get_node("Stage1Metrics").totals
		var row: Dictionary = {}
		for key: String in totals:
			row[key] = totals[key][0] - last_totals.get(key, 0)
			last_totals[key] = totals[key][0]
		tick_operations.append(row)
	if args.get("replay", "false") == "true":
		var state: Array = []
		for receiver: Node in receivers:
			state.append([receiver.saturation, receiver.surface_saturation, receiver.contact_enabled, receiver.global_position.x, receiver.global_position.y])
		var digest := HashingContext.new()
		digest.start(HashingContext.HASH_SHA256)
		digest.update(demo.emitter.surface.simulation.saturation_buffer().to_byte_array())
		replay.append([digest.finish().hex_encode(), state, event_queue.duplicate()])
		event_queue.clear()
	ticks += 1
	if ticks == warm:
		start = Time.get_ticks_usec()
		previous = start
		if root.has_node("Stage1Metrics"):
			root.get_node("Stage1Metrics").reset()
	if ticks > warm:
		measured_ticks += 1
	if args.get("mode", "cpu") == "cpu" and measured_ticks >= int(args.get("ticks", "3600")):
		_finish()

func _frame() -> void:
	if ticks <= warm:
		return
	var now := Time.get_ticks_usec()
	frames.append((now - previous) / 1000.0)
	previous = now
	if args.get("mode", "cpu") == "rendered" and now - start >= float(args.get("seconds", "30")) * 1000000.0:
		_finish()

func _finish() -> void:
	physics_frame.disconnect(_tick)
	process_frame.disconnect(_frame)
	var seconds := (Time.get_ticks_usec() - start) / 1000000.0
	var result := {"args": args, "ticks": measured_ticks, "seconds": seconds,
		"ticks_per_second": measured_ticks / seconds, "frames_ms": frames,
		"window_visible": root.visible, "window_focused": root.has_focus(),
		"window_can_draw": DisplayServer.window_can_draw(), "viewport_size": [root.size.x, root.size.y],
		"setup_usec": setup_usec, "process_wall_seconds": (Time.get_ticks_usec() - all_start) / 1000000.0,
		"receiver_count": receivers.size(), "replay": replay, "tick_operations": tick_operations, "memory": Performance.get_monitor(Performance.MEMORY_STATIC)}
	if root.has_node("Stage1Metrics"):
		result["operations"] = root.get_node("Stage1Metrics").totals
	if args.get("edits", "false") == "true":
		result["edit_costs"] = _edit_costs()
	FileAccess.open(args.get("out", "/tmp/stage1.json"), FileAccess.WRITE).store_string(JSON.stringify(result))
	if args.get("capture", "false") == "true":
		root.get_texture().get_image().save_png(args.get("out", "/tmp/stage1.json") + ".png")
	quit()


func _edit_costs() -> Dictionary:
	var result := {"regional_usec": [], "full_usec": [], "first_receiver_pass_usec": [], "reused_receiver_pass_usec": []}
	for index: int in range(int(args.get("edit_repeats", "5"))):
		var before := Time.get_ticks_usec()
		demo.emitter.surface.refresh_obstacles(Rect2(demo.aim_bounds.get_center(), Vector2(64, 64)))
		result.regional_usec.append(Time.get_ticks_usec() - before)
		for pass_index: int in range(2):
			before = Time.get_ticks_usec()
			for receiver: Node in receivers:
				if demo.emitter.surface.has_method("_sample_contact"):
					demo.emitter.surface._sample_contact(receiver.global_position, receiver.get("_prepared_contact"))
				else:
					demo.emitter.surface.saturation_at(receiver.global_position)
			if pass_index == 0:
				result.first_receiver_pass_usec.append(Time.get_ticks_usec() - before)
			else:
				result.reused_receiver_pass_usec.append(Time.get_ticks_usec() - before)
		before = Time.get_ticks_usec()
		demo.emitter.surface.refresh_coverage()
		result.full_usec.append(Time.get_ticks_usec() - before)
	return result
