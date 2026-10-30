extends SceneTree
## Matched clocks/inputs, CPU component timers, rendered frame tails and explicit hardware identity.

const Settings = preload("res://addons/tile_map_fluid/benchmarks/settings.gd")
const Room = preload("res://addons/tile_map_fluid/benchmarks/room.gd")
const Metrics = preload("res://addons/tile_map_fluid/benchmarks/metrics.gd")
const Probe = preload("res://addons/tile_map_fluid/benchmarks/resolution_probe.gd")
const RoomScene: PackedScene = preload("res://addons/tile_map_fluid/benchmarks/room.tscn")
const WORKLOADS: PackedStringArray = ["dry_idle", "moving_spray", "game_splash",
	"saturated_drying", "crowded_contacts", "geometry_updates"]

var _settings: Settings = Settings.new()
var _output: String = "res://reports/benchmarks/default"
var _workloads: PackedStringArray = WORKLOADS
var _probe_only: bool = false
var _report: Dictionary = {}


func _initialize() -> void:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--settings="):
			_settings = load(argument.trim_prefix("--settings=")) as Settings
		elif argument.begins_with("--output="):
			_output = argument.trim_prefix("--output=")
		elif argument.begins_with("--seconds="):
			_settings.seconds = float(argument.trim_prefix("--seconds="))
		elif argument.begins_with("--warmup="):
			_settings.warmup = float(argument.trim_prefix("--warmup="))
		elif argument.begins_with("--spacing="):
			_settings.spacings = PackedFloat32Array([float(argument.trim_prefix("--spacing="))])
		elif argument.begins_with("--workload="):
			_workloads = PackedStringArray([argument.trim_prefix("--workload=")])
		elif argument == "--probe-only":
			_probe_only = true
		elif argument == "--uncapped":
			_settings.paced = false
		else:
			push_error("Unknown benchmark option: " + argument)
			quit(2)
			return
		if _settings == null:
			push_error("Cannot load benchmark settings.")
			quit(2)
			return
	var local: String = ProjectSettings.localize_path(
		ProjectSettings.globalize_path(_output)).simplify_path()
	if not _settings.validation_error().is_empty() \
			or not local.begins_with("res://reports/"):
		push_error("Use valid settings and an output directory under reports/: "
			+ _settings.validation_error())
		quit(2)
		return
	for workload: String in _workloads:
		if not WORKLOADS.has(workload):
			quit(2)
			return
	_launch.call_deferred()


func _launch() -> void:
	root.size = Vector2i(1152, 720)
	root.content_scale_size = Vector2i(1152, 720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_output))
	_report = { "schema": 2, "workload_settings": _settings.signature(),
		"engine": Engine.get_version_info(), "os": OS.get_name(),
		"processor": OS.get_processor_name(), "cpu_count": OS.get_processor_count(),
		"display": DisplayServer.get_name(),
		"renderer": RenderingServer.get_current_rendering_method(),
		"adapter": RenderingServer.get_video_adapter_name(), "arguments": OS.get_cmdline_args(),
		"utc": Time.get_datetime_string_from_system(true), "rows": [], "probes": [] }
	var hashes: Dictionary = {}
	for filename: String in ["run.gd", "room.gd", "room.tscn", "settings.gd", "metrics.gd",
			"resolution_probe.gd", "capture.gd"]:
		var path: String = "res://addons/tile_map_fluid/benchmarks/" + filename
		hashes[path] = FileAccess.get_file_as_string(path).sha256_text()
	_report.source_sha256 = hashes
	ResourceSaver.save(_settings, _output.path_join("settings.tres"))
	for spacing: float in _settings.spacings:
		var baseline: Dictionary = Metrics.memory()
		var room: Room = RoomScene.instantiate() as Room
		room.configure(_settings, spacing)
		root.add_child(room)
		await physics_frame
		await physics_frame
		if not room.surface.validation_error().is_empty():
			push_error(room.surface.validation_error())
			quit(1)
			return
		if not _probe_only:
			for workload: String in _workloads:
				var row: Dictionary = await _measure(room, workload, spacing)
				row.memory_before_room = baseline
				_report.rows.append(row)
				_save()
		_report.probes.append(await Probe.run(room, _output))
		_save()
		room.queue_free()
		await process_frame
		await process_frame
	quit()


func _measure(room: Room, workload: String, spacing: float) -> Dictionary:
	var start: int = Time.get_ticks_usec()
	room.prepare(workload)
	var preparation_us: int = Time.get_ticks_usec() - start
	var metrics: Metrics = Metrics.new()
	var warmup: int = roundi(_settings.warmup * _settings.ticks_per_second)
	var measured: int = maxi(1, roundi(_settings.seconds * _settings.ticks_per_second))
	var previous: int = 0
	var measured_start: int = 0
	var pending: Dictionary = {}
	var memory_start: Dictionary = {}
	var peak_static: int = 0
	# Attribute each interval to the work before it, including that frame's render submission.
	for tick: int in range(warmup + measured + 1):
		await process_frame
		var now: int = Time.get_ticks_usec()
		if _settings.paced and previous > 0:
			# --fixed-fps bypasses Godot's frame cap. Keep a sustained wall-time window
			# explicitly while retaining identical tick counts and input trajectories.
			var remaining: int = roundi(1_000_000.0 / _settings.ticks_per_second) - (now - previous)
			if remaining > 0:
				OS.delay_usec(remaining)
			now = Time.get_ticks_usec()
		if tick == warmup:
			measured_start = now
			memory_start = Metrics.memory()
		if tick > warmup:
			metrics.record("frame_wall", now - previous)
			for key: String in pending:
				metrics.record(key, pending[key])
		previous = now
		if tick < warmup + measured:
			start = Time.get_ticks_usec()
			pending = room.step(workload, tick)
			pending.work_total = Time.get_ticks_usec() - start
		peak_static = maxi(peak_static, OS.get_static_memory_usage())
	var wall_seconds: float = float(Time.get_ticks_usec() - measured_start) / 1_000_000.0
	var result: Dictionary = { "spacing": spacing, "workload": workload,
		"paced": _settings.paced,
		"simulated_seconds": float(measured) / _settings.ticks_per_second,
		"warmup_seconds": _settings.warmup, "wall_seconds": wall_seconds,
		"preparation_us": preparation_us, "counts": room.counts.duplicate(),
		"memory_start": memory_start, "memory_end": Metrics.memory(),
		"peak_engine_static_bytes": peak_static, "metrics": metrics.report() }
	print(JSON.stringify({ "spacing": spacing, "workload": workload,
		"wall_seconds": wall_seconds, "summary_us": result.metrics.summary_us }))
	return result


func _save() -> void:
	var file: FileAccess = FileAccess.open(_output.path_join("results.json"), FileAccess.WRITE)
	if file == null:
		push_error("Cannot write wetness benchmark results.")
		quit(1)
		return
	file.store_string(JSON.stringify(_report, "\t"))
