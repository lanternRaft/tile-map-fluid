extends "res://tests/test_case.gd"
## Benchmark reports reject slowdowns and incompatible measurements.

const Comparison = preload("res://addons/tile_map_fluid/benchmarks/comparison.gd")


func test_identical_report_passes_and_checks_each_statistic() -> void:
	var baseline: Dictionary = _report()
	var result: Dictionary = Comparison.compare(baseline, baseline.duplicate(true))
	check((result.checked) == (2))
	check(result.regressions.is_empty())


func test_measured_slowdown_fails_while_small_noise_passes() -> void:
	var baseline: Dictionary = _report()
	var slower: Dictionary = baseline.duplicate(true)
	slower.rows[0].metrics.summary_us.simulation.p95 = 200.0
	check((Comparison.compare(baseline, slower).regressions.size()) == (1))
	var noisy: Dictionary = baseline.duplicate(true)
	noisy.rows[0].metrics.summary_us.simulation.p95 = 140.0
	check(Comparison.compare(baseline, noisy).regressions.is_empty())


func test_changed_hardware_engine_or_settings_are_incompatible() -> void:
	var baseline: Dictionary = _report()
	for key: String in ["processor", "engine", "workload_settings"]:
		var changed: Dictionary = baseline.duplicate(true)
		changed[key] = "different"
		check(Comparison.compare(baseline, changed).has("error"))


func test_changed_coverage_or_timer_counts_are_incompatible() -> void:
	var baseline: Dictionary = _report()
	var missing: Dictionary = baseline.duplicate(true)
	missing.rows.clear()
	check(Comparison.compare(baseline, missing).has("error"))
	var changed: Dictionary = baseline.duplicate(true)
	changed.rows[0].counts.samples = 200
	check(Comparison.compare(baseline, changed).has("error"))
	changed = baseline.duplicate(true)
	changed.rows[0].metrics.summary_us.simulation.n = 10
	check(Comparison.compare(baseline, changed).has("error"))


func test_paced_intervals_are_excluded_but_capacity_intervals_are_compared() -> void:
	var baseline: Dictionary = _report()
	baseline.rows[0].metrics.summary_us.frame_wall = { "n": 100, "p50": 100.0, "p95": 100.0 }
	var current: Dictionary = baseline.duplicate(true)
	current.rows[0].metrics.summary_us.frame_wall.p95 = 500.0
	check(Comparison.compare(baseline, current).regressions.is_empty())
	baseline.rows[0].paced = false
	current.rows[0].paced = false
	check((Comparison.compare(baseline, current).regressions.size()) == (1))


func test_invalid_thresholds_do_not_report_a_pass() -> void:
	var baseline: Dictionary = _report()
	check(Comparison.compare(baseline, baseline, -1.0).has("error"))


func _report() -> Dictionary:
	return { "schema": 2, "os": "test", "processor": "test", "cpu_count": 1,
		"display": "headless", "renderer": "test", "adapter": "test", "engine": "test",
		"workload_settings": { "seconds": "10.0" }, "rows": [{ "spacing": 32,
		"workload": "dry_idle", "counts": { "samples": 100 }, "simulated_seconds": 10.0,
		"warmup_seconds": 1.0, "paced": true, "metrics": { "summary_us": {
		"simulation": { "n": 100, "p50": 100.0, "p95": 100.0 } } } }] }
