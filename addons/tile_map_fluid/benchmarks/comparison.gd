extends RefCounted
## Opt-in regression checks require matched hardware/workloads; no universal millisecond budget.


## Returns incompatibility separately from measured regressions; thresholds are relative plus noise.
static func compare(baseline: Dictionary, current: Dictionary, tolerance: float = 0.25,
		noise_us: float = 50.0) -> Dictionary:
	if not is_finite(tolerance) or tolerance < 0.0 or not is_finite(noise_us) or noise_us < 0.0:
		return { "error": "Thresholds must be finite and nonnegative." }
	if baseline.get("schema") != 2 or current.get("schema") != 2:
		return { "error": "Both reports must use benchmark schema 2; capture a new baseline." }
	for key: String in ["os", "processor", "cpu_count", "display", "renderer", "adapter",
			"engine", "workload_settings"]:
		if not baseline.has(key) or not _same(baseline[key], current.get(key)):
			return { "error": "Incompatible reports: " + key }
	var previous: Dictionary[String, Dictionary] = _rows(baseline)
	var latest: Dictionary[String, Dictionary] = _rows(current)
	if previous.is_empty() or previous.size() != baseline.get("rows", []).size() \
			or latest.size() != current.get("rows", []).size() or previous.size() != latest.size():
		return { "error": "Reports need the same nonempty, unique workload rows." }
	var failures: Array[String] = []
	var checked: int = 0
	for key: String in previous:
		if not latest.has(key):
			return { "error": "Missing workload: " + key }
		var old: Dictionary = previous[key]
		var new: Dictionary = latest[key]
		for field: String in ["counts", "simulated_seconds", "warmup_seconds", "paced"]:
			if not old.has(field) or not _same(old[field], new.get(field)):
				return { "error": "Incompatible " + key + ": " + field }
		var before: Dictionary = old.metrics.summary_us
		var after: Dictionary = new.metrics.summary_us
		if before.keys().size() != after.keys().size():
			return { "error": "Changed timer coverage: " + key }
		for timer: String in before:
			if not after.has(timer) or before[timer].n != after[timer].n:
				return { "error": "Changed timer sample count: " + key + "/" + timer }
			# Pacing intentionally dominates frame intervals; compare capacity frames only.
			if timer == "frame_wall" and old.paced:
				continue
			for statistic: String in ["p50", "p95"]:
				var value: float = after[timer][statistic]
				var previous_us: float = before[timer][statistic]
				if (not is_finite(value)
						or value < 0.0
						or not is_finite(previous_us)
						or previous_us < 0.0):
					return { "error": "Invalid timing: " + key + "/" + timer }
				checked += 1
				var limit: float = previous_us + maxf(noise_us, previous_us * tolerance)
				if value > limit:
					failures.append("%s/%s/%s: %.1fus > %.1fus limit (baseline %.1fus)" % [
						key, timer, statistic, value, limit, previous_us])
	return { "checked": checked, "regressions": failures }


static func _same(before: Variant, after: Variant) -> bool:
	return typeof(before) == typeof(after) and before == after


static func _rows(report: Dictionary) -> Dictionary[String, Dictionary]:
	var result: Dictionary[String, Dictionary] = {}
	for row: Dictionary in report.get("rows", []):
		result["%s/%s" % [row.spacing, row.workload]] = row
	return result
