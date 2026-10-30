extends SceneTree
## Compare archived runs on a controlled machine; exits 0/pass, 1/regression, 2/incompatible.

const Comparison = preload("res://addons/tile_map_fluid/benchmarks/comparison.gd")


func _initialize() -> void:
	var baseline: String = ""
	var current: String = ""
	var tolerance: float = 0.25
	var noise_us: float = 50.0
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--baseline="):
			baseline = argument.trim_prefix("--baseline=")
		elif argument.begins_with("--current="):
			current = argument.trim_prefix("--current=")
		elif argument.begins_with("--tolerance="):
			tolerance = float(argument.trim_prefix("--tolerance="))
		elif argument.begins_with("--noise-us="):
			noise_us = float(argument.trim_prefix("--noise-us="))
		else:
			push_error("Unknown comparison option: " + argument)
			quit(2)
			return
	var before: Variant = JSON.parse_string(FileAccess.get_file_as_string(baseline))
	var after: Variant = JSON.parse_string(FileAccess.get_file_as_string(current))
	if not before is Dictionary or not after is Dictionary:
		push_error("Provide --baseline=REPORT_JSON and --current=REPORT_JSON.")
		quit(2)
		return
	var result: Dictionary = Comparison.compare(before, after, tolerance, noise_us)
	print(JSON.stringify(result))
	if result.has("error"):
		quit(2)
	else:
		quit(0 if result.regressions.is_empty() else 1)
