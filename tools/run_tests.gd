extends SceneTree
## Supervise vanilla tests so runtime/parse errors cannot produce a successful exit.


func _initialize() -> void:
	var directory: String = ProjectSettings.globalize_path("res://reports/tests")
	if OS.get_cmdline_user_args().has("--rendered-only"):
		directory = directory.path_join("rendered")
	DirAccess.make_dir_recursive_absolute(directory)
	var output: Array = []
	# Test subprocesses need no audio device, including on rendered CI runners.
	var arguments: PackedStringArray = ["--audio-driver", "Dummy", "--path",
		ProjectSettings.globalize_path("res://"), "--fixed-fps", "120", "--log-file",
		directory.path_join("engine.log"), "--script", "res://tests/run.gd"]
	if DisplayServer.get_name() == "headless":
		arguments.append("--headless")
	else:
		arguments.append_array(["--rendering-method", "gl_compatibility", "--disable-vsync"])
	arguments.append("--")
	arguments.append_array(OS.get_cmdline_user_args())
	var code: int = OS.execute(OS.get_executable_path(), arguments, output, true)
	var console_output: String = ""
	for chunk: String in output:
		console_output += chunk
		print(chunk)
	FileAccess.open(
		directory.path_join("output.log"),
		FileAccess.WRITE,
	).store_string(console_output)
	var engine_log: String = FileAccess.get_file_as_string(directory.path_join("engine.log"))
	var failed: bool = code != 0 or not console_output.contains("TILE_MAP_FLUID_TESTS_COMPLETE") \
		or console_output.contains("FAIL:") or console_output.contains("ERROR:") \
		or engine_log.contains("ERROR:") \
		or engine_log.contains("leaked")
	quit(1 if failed else 0)
