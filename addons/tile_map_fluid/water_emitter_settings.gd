class_name WaterEmitterSettings
extends Resource

## Saturation added per second to EACH covered sample/receiver, independent of footprint area.
@export_range(0.0, 20.0, 0.05) var rate: float = 1.0
## Solid bodies tested between the outlet and each contact. Zero disables obstruction.
@export_flags_2d_physics var obstacle_mask: int = 1


## Reject invalid runtime rates rather than letting NaN contaminate a field.
func validation_error() -> String:
	return "WaterEmitterSettings.rate must be finite and nonnegative." \
		if not is_finite(rate) or rate < 0.0 else ""
