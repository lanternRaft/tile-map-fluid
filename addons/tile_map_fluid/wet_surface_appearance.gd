class_name TileFluidSurfaceAppearance
extends Resource
## Inspector-editable artwork. Each presenter shares one material across all of its meshes.

## Seamless texture, sampled once per interpolation patch.
@export var texture: Texture2D = preload("res://addons/tile_map_fluid/assets/wet_surface.svg")
## Multiplied by saturation and texture alpha; no saturation means fully transparent.
@export var tint: Color = Color(0.14, 0.48, 0.58, 0.55)
## Seconds between uploads; simulation and gameplay sampling remain on the physics clock.
@export_range(0.016, 0.2, 0.001) var refresh_interval: float = 0.05
## Rows combined inside atomic ground parents; Y-sorted parents always retain single-row anchors.
@export_range(1, 128, 1) var rows_per_batch: int = 1
