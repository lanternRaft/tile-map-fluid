extends WetCoverageProvider2D
## Represents a game-owned clipped room and independently gated opening without game imports.

## World pieces supplied by a room adapter; tests replace them and emit coverage_changed.
var pieces: Array[PackedVector2Array] = []


## Returns filled pieces, with absent regions representing holes or closed access.
func world_polygons() -> Array[PackedVector2Array]:
	return pieces.duplicate()


## Potential access stays inside this stable world envelope.
func world_envelope() -> Rect2:
	return Rect2(-64, -64, 128, 128)
