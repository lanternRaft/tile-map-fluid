extends SceneTree
## Discovers test methods and isolates every case in a fresh Node with deterministic cleanup.

const TestCase = preload("res://tests/test_case.gd")


func _initialize() -> void:
	# A stuck coroutine cannot turn a test run into an unbounded CI job.
	create_timer(60.0, true, false, true).timeout.connect(func() -> void:
		printerr("Test run exceeded 60 seconds.")
		quit(1))
	_run.call_deferred()


func _run() -> void:
	var failures: int = 0
	var cases: int = 0
	var checks: int = 0
	for filename: String in DirAccess.get_files_at("res://tests"):
		if not filename.begins_with("test_") or filename == "test_case.gd" \
				or not filename.ends_with(".gd"):
			continue
		var rendered: bool = filename.begins_with("test_rendered")
		if OS.get_cmdline_user_args().has("--rendered-only") and not rendered:
			continue
		if rendered and DisplayServer.get_name() == "headless":
			print("SKIP %s (requires a renderer)" % filename)
			continue
		var script: GDScript = load("res://tests/" + filename) as GDScript
		if script == null or not script.can_instantiate():
			quit(1)
			return
		for method: Dictionary in script.get_script_method_list():
			var name: String = method.name
			if not name.begins_with("test_"):
				continue
			var test: TestCase = script.new() as TestCase
			test.process_mode = Node.PROCESS_MODE_ALWAYS
			root.add_child(test)
			var previous_scale: float = Engine.time_scale
			if test.has_method("before_test"):
				test.call("before_test")
			await test.call(name)
			if test.has_method("after_test"):
				test.call("after_test")
			paused = false
			Engine.time_scale = previous_scale
			checks += test.checks
			failures += test.failures
			cases += 1
			print("%s %s/%s (%d checks)" % [
				"PASS" if test.failures == 0 else "FAIL", filename, name, test.checks])
			test.cleanup()
			test.free()
			await process_frame
	print("TILE_MAP_FLUID_TESTS_COMPLETE cases=%d checks=%d failures=%d" % [
		cases, checks, failures])
	quit(0 if failures == 0 and cases > 0 else 1)
