class_name WettableSettings
extends Resource

## Seconds for a saturated receiver to dry; zero disables drying.
@export_range(0.0, 120.0, 1.0) var dry_seconds: float = 36.0
## Saturation gained per second toward the supporting surface's saturation; never drains floor.
@export_range(0.0, 5.0, 0.05) var ground_absorption: float = 0.5


## Runtime values must be finite and nonnegative, including when resources are shared.
func validation_error() -> String:
	if not is_finite(dry_seconds) or dry_seconds < 0.0:
		return "WettableSettings.dry_seconds must be finite and nonnegative."
	if not is_finite(ground_absorption) or ground_absorption < 0.0:
		return "WettableSettings.ground_absorption must be finite and nonnegative."
	return ""
