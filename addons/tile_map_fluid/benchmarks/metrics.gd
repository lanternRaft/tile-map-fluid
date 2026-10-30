extends RefCounted
## Raw series are retained alongside nearest-rank summaries; microseconds unless labeled otherwise.

## Conditional upload/edit series contain only event frames; other series cover every tick.
var series: Dictionary[String, Array] = {}


## Add one explicit observation without hiding conditional work in its average.
func record(key: String, value: float) -> void:
	if not series.has(key):
		series[key] = []
	series[key].append(value)


## Preserve raw observations so tails and upload-only costs can be reanalyzed.
func report() -> Dictionary:
	var result: Dictionary = {}
	for key: String in series:
		result[key] = summary(series[key])
	return { "summary_us": result, "raw_us": series }


## Nearest-rank percentiles, with an explicit sample count and mean.
static func summary(values: Array) -> Dictionary:
	if values.is_empty():
		return {}
	var sorted: Array = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value: float in sorted:
		total += value
	return { "n": sorted.size(), "mean": total / sorted.size(),
		"p50": sorted[maxi(0, ceili(sorted.size() * 0.50) - 1)],
		"p95": sorted[maxi(0, ceili(sorted.size() * 0.95) - 1)],
		"p99": sorted[maxi(0, ceili(sorted.size() * 0.99) - 1)], "max": sorted[-1] }


## Process-wide engine/renderer counters, not a claim about isolated field or OS resident memory.
static func memory() -> Dictionary:
	var video: int = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_VIDEO_MEM_USED)
	var draws: int = RenderingServer.get_rendering_info(
		RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME)
	return { "engine_static_bytes": OS.get_static_memory_usage(),
		"video_bytes": video,
		"objects": Performance.get_monitor(Performance.OBJECT_COUNT),
		"nodes": Performance.get_monitor(Performance.OBJECT_NODE_COUNT),
		"draw_calls": draws }
