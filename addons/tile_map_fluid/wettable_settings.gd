class_name TileFluidWettableSettings
extends Resource

## Multiplicative artwork color at full saturation.
@export var object_tint: Color = Color(0.72, 0.87, 0.94, 1.0):
	set(value):
		if object_tint != value:
			object_tint = value
			revision += 1
			_validation_issue = _validate()
			emit_changed()
## Preserve unbounded positive doses for reactions independent of saturation.
@export var report_full_dose: bool = true:
	set(value):
		if report_full_dose != value:
			report_full_dose = value
			revision += 1
			_validation_issue = _validate()
			emit_changed()
## Seconds for a saturated receiver to dry; zero disables drying.
@export_range(0.0, 120.0, 1.0) var dry_seconds: float = 36.0:
	set(value):
		if dry_seconds != value:
			dry_seconds = value
			revision += 1
			_validation_issue = _validate()
			emit_changed()
## Saturation gained per second toward the supporting surface's saturation; never drains floor.
@export_range(0.0, 5.0, 0.05) var ground_absorption: float = 0.5:
	set(value):
		if ground_absorption != value:
			ground_absorption = value
			revision += 1
			_validation_issue = _validate()
			emit_changed()


## Monotonic dependency token; shared Resources never cache mutable water.
var revision: int = 0
var _validation_issue: String = ""


## Runtime values must be finite and nonnegative, including when resources are shared.
func validation_error() -> String:
	return _validation_issue


func _validate() -> String:
	if not is_finite(dry_seconds) or dry_seconds < 0.0:
		return "TileFluidWettableSettings.dry_seconds must be finite and nonnegative."
	if not is_finite(ground_absorption) or ground_absorption < 0.0:
		return "TileFluidWettableSettings.ground_absorption must be finite and nonnegative."
	return ""
