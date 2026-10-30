extends Resource
## Matched synthetic workloads; changing spacing never changes geometry, dose or actor count.

## Local field spacings compared in the listed order.
@export var spacings: PackedFloat32Array = PackedFloat32Array([32, 16, 8])
## Measured simulation seconds per workload, after warmup.
@export_range(0.1, 120.0) var seconds: float = 30.0
## Untimed initial seconds of each workload; preparation and shader compilation are excluded.
@export_range(0.0, 30.0) var warmup: float = 3.0
## Explicit simulation steps per second, independent of renderer throughput.
@export_range(30, 240) var ticks_per_second: int = 120
## Actual nodes present at every resolution, advanced only in the crowded workload.
@export_range(1, 500) var receiver_count: int = 100
## Tile coordinates; includes negative coordinates and a disconnected island.
@export var tiles: Rect2i = Rect2i(-2, -1, 32, 18)
## Missing tiles form an interior hole.
@export var hole: Rect2i = Rect2i(4, 4, 2, 2)
## Absent column separates an island on the right.
@export var gap_column: int = 26
## World circular footprint, identical at every resolution.
@export_range(1.0, 128.0) var radius: float = 22.0
## Normalized per-contact saturation per simulated second.
@export_range(0.01, 10.0) var rate: float = 1.25
## Floor lifetime; saturated/drying remains wet throughout the default measurement window.
@export_range(1.0, 120.0) var dry_seconds: float = 72.0
## Pace wall time as well as simulation time; disable for uncapped capacity measurements.
@export var paced: bool = true


## Reject invalid CLI/Resource assignments before allocating a workload or reporting measurements.
func validation_error() -> String:
	if not is_finite(seconds) or seconds <= 0.0 or not is_finite(warmup) or warmup < 0.0:
		return "Seconds must be positive and warmup nonnegative, both finite."
	if ticks_per_second < 1 or receiver_count < 1 or not tiles.has_area():
		return "Clock, receiver count and tile rectangle must be positive."
	if not is_finite(radius) or radius <= 0.0 or not is_finite(rate) or rate <= 0.0 \
			or not is_finite(dry_seconds) or dry_seconds <= 0.0:
		return "Radius, rate and drying time must be finite and positive."
	if spacings.is_empty():
		return "At least one spacing is required."
	for spacing: float in spacings:
		if not is_finite(spacing) or spacing < 8.0:
			return "Spacings must be finite and at least eight pixels."
	return ""


## Record all exported workload values so timing comparisons reject changed experiments.
func signature() -> Dictionary:
	var result: Dictionary = {}
	for property: Dictionary in get_property_list():
		var usage: int = property.usage
		if usage & PROPERTY_USAGE_STORAGE and usage & PROPERTY_USAGE_SCRIPT_VARIABLE:
			result[property.name] = var_to_str(get(property.name))
	return result
