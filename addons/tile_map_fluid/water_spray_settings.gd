class_name WaterSpraySettings
extends Resource
## Cone geometry and additive soft splashes shared by scene-authored spray nodes.

## Maximum radial floor-space reach from the outlet, in world pixels.
@export_range(1.0, 1000.0, 1.0) var reach: float = 160.0
## Cone half-angle in degrees; the near outlet retains an eight-pixel half-width.
@export_range(1.0, 89.0, 1.0) var spread: float = 12.0
## Saturation per second at each splash and directly hit receiver.
@export_range(0.0, 20.0, 0.05) var rate: float = 3.33333333333333
## World spacing between independent, additive splash centers.
@export_range(8.0, 128.0, 1.0) var sample_spacing: float = 28.0
## Radius in layer-local pixels on initially dry floor.
@export_range(1.0, 128.0, 1.0) var initial_radius: float = 22.0
## Radius in layer-local pixels at full local saturation.
@export_range(1.0, 128.0, 1.0) var maximum_radius: float = 32.0
## Bodies blocking both cone samples and direct receiver hits.
@export_flags_2d_physics var obstacle_mask: int = 1


## Reject invalid runtime values before they reach geometry or saturation storage.
func is_valid() -> bool:
	for value: float in [reach, spread, rate, sample_spacing, initial_radius, maximum_radius]:
		if not is_finite(value) or value < 0.0:
			return false
	return reach > 0.0 and spread < 90.0 and sample_spacing >= 8.0 \
		and initial_radius > 0.0 and maximum_radius > 0.0
