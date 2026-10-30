@icon("res://addons/tile_map_fluid/assets/icons/coverage.svg")
@abstract class_name WetCoverageProvider2D
extends Node2D
## Optional game-owned adapter for composed layers, clipped polygons, and live openings.

## Emit after changing coverage; empty bounds mean a full refresh, otherwise WORLD bounds.
signal coverage_changed(world_bounds: Rect2)


## Adapter notification after batching tile edits or changing clipped/opening coverage.
func notify_coverage_changed(world_bounds: Rect2 = Rect2()) -> void:
	coverage_changed.emit(world_bounds)


## Returns bounded, simple, filled WORLD polygons; holes are represented by absent pieces.
## The surface converts to its layer's coordinates. Providers must not expose game types.
@abstract func world_polygons() -> Array[PackedVector2Array]

## Stable WORLD envelope includes potential closed openings so access changes need not resize.


@abstract func world_envelope() -> Rect2
