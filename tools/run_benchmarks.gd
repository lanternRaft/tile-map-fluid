extends SceneTree
## CI smoke run validates complete measured workload coverage and retains the raw benchmark report.


func _initialize() -> void:
	var directory: String = ProjectSettings.globalize_path("res://reports/benchmarks/ci")
	DirAccess.make_dir_recursive_absolute(directory)
	var report_path: String = directory.path_join("results.json")
	if FileAccess.file_exists(report_path):
		DirAccess.remove_absolute(report_path)
	var output: Array = []
	var code: int = OS.execute(OS.get_executable_path(), ["--headless", "--path",
		ProjectSettings.globalize_path("res://"), "--log-file", directory.path_join("engine.log"),
		"--script", "res://addons/tile_map_fluid/benchmarks/run.gd", "--", "--seconds=1.1",
		"--warmup=0.1", "--uncapped", "--output=res://reports/benchmarks/ci"], output, true)
	var console_output: String = "\n".join(output)
	FileAccess.open(
		directory.path_join("output.log"),
		FileAccess.WRITE,
	).store_string(console_output)
	var report: Variant = JSON.parse_string(FileAccess.get_file_as_string(report_path)) \
		if FileAccess.file_exists(report_path) else null
	var failed: bool = code != 0 or console_output.contains("ERROR:") \
		or console_output.contains("leaked")
	if not report is Dictionary or report.get("rows", []).size() != 18:
		failed = true
	else:
		for row: Dictionary in report.rows:
			if row.workload == "geometry_updates" \
					and not row.metrics.summary_us.has("geometry_event"):
				failed = true
	if failed:
		printerr(console_output)
		printerr("Incomplete benchmark run; see " + directory)
	else:
		print("PASS: 18 measured workloads, including live geometry events. Reports: " + directory)
	quit(1 if failed else 0)
