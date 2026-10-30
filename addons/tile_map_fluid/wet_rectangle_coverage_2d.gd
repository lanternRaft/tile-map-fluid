@icon("res://addons/tile_map_fluid/assets/icons/coverage.svg")
class_name WetRectangleCoverage2D
extends WetCoverageProvider2D
## Optional bounded surface for isolated tools/tests without authored tiles.

## Local rectangle; ordinary gameplay surfaces should reference their floor TileMapLayers.
@export var bounds: Rect2


## One filled source, indexed and clipped by the same backend as tile coverage.
func world_polygons() -> Array[PackedVector2Array]:
	return [global_transform * WetSurfaceCoverage.rectangle(bounds)] if bounds.has_area() else []


## Conservative world envelope under rotation or nonuniform scale.
func world_envelope() -> Rect2:
	return WetFieldPolygons.bounds(global_transform * WetSurfaceCoverage.rectangle(bounds))
