class_name TileFluidSurfaceSettings
extends Resource
## Shared configuration only; mutable water belongs to each surface's simulation node.

## Field spacing in TileMapLayer-local pixels. Extraction starts at 32 pixels.
@export_range(8.0, 64.0, 1.0) var sample_spacing: float = 32.0
## Layer-local lattice anchor; hosts can retain an existing nonzero-origin field.
@export var sample_origin: Vector2 = Vector2.ZERO
## Seconds for saturated floor to dry; zero disables evaporation.
@export_range(0.0, 120.0, 1.0) var dry_seconds: float = 72.0
## Hard floor barriers to clip during coverage refresh; zero uses only supplied floor polygons.
@export_flags_2d_physics var obstacle_mask: int = 1
## Upper bound on covered lattice cells, independent of deposit count and envelope size.
@export_range(1, 1_048_576, 1) var maximum_cells: int = 65_536
## Optional boolean TileSet custom-data layer. Missing metadata uses the default below.
@export var receives_water_key: StringName = &"receives_water"
## Used for atlas tiles when the custom-data layer is absent or its name is empty.
@export var receives_water_by_default: bool = true


## Runtime assignments must satisfy the same limits as editor-authored settings.
func validation_error() -> String:
	if not sample_origin.is_finite():
		return "TileFluidSurfaceSettings.sample_origin must be finite."
	if not is_finite(sample_spacing) or sample_spacing < 8.0:
		return "TileFluidSurfaceSettings.sample_spacing must be finite and at least 8 pixels."
	if not is_finite(dry_seconds) or dry_seconds < 0.0:
		return "TileFluidSurfaceSettings.dry_seconds must be finite and nonnegative."
	if maximum_cells < 1:
		return "TileFluidSurfaceSettings.maximum_cells must be positive."
	return ""
