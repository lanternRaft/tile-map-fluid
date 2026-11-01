class_name TileFluidSurfaceSettings
extends Resource
## Shared configuration only; mutable water belongs to each surface's simulation node.

## Field spacing in TileMapLayer-local pixels. Extraction starts at 32 pixels.
@export_range(8.0, 64.0, 1.0) var sample_spacing: float = 32.0:
	set(value):
		if sample_spacing != value:
			sample_spacing = value
			revision += 1
			geometry_revision += 1
			_validation_issue = _validate()
			emit_changed()
## Layer-local lattice anchor; hosts can retain an existing nonzero-origin field.
@export var sample_origin: Vector2 = Vector2.ZERO:
	set(value):
		if sample_origin != value:
			sample_origin = value
			revision += 1
			geometry_revision += 1
			_validation_issue = _validate()
			emit_changed()
## Seconds for saturated floor to dry; zero disables evaporation.
@export_range(0.0, 120.0, 1.0) var dry_seconds: float = 72.0:
	set(value):
		if dry_seconds != value:
			dry_seconds = value
			revision += 1
			_validation_issue = _validate()
			emit_changed()
## Hard floor barriers to clip during coverage refresh; zero uses only supplied floor polygons.
@export_flags_2d_physics var obstacle_mask: int = 1:
	set(value):
		if obstacle_mask != value:
			obstacle_mask = value
			revision += 1
			geometry_revision += 1
			_validation_issue = _validate()
			emit_changed()
## Upper bound on covered lattice cells, independent of deposit count and envelope size.
@export_range(1, 1_048_576, 1) var maximum_cells: int = 65_536:
	set(value):
		if maximum_cells != value:
			maximum_cells = value
			revision += 1
			geometry_revision += 1
			_validation_issue = _validate()
			emit_changed()
## Optional boolean TileSet custom-data layer. Missing metadata uses the default below.
@export var receives_water_key: StringName = &"receives_water":
	set(value):
		if receives_water_key != value:
			receives_water_key = value
			revision += 1
			geometry_revision += 1
			_validation_issue = _validate()
			emit_changed()
## Used for atlas tiles when the custom-data layer is absent or its name is empty.
@export var receives_water_by_default: bool = true:
	set(value):
		if receives_water_by_default != value:
			receives_water_by_default = value
			revision += 1
			geometry_revision += 1
			_validation_issue = _validate()
			emit_changed()


## Monotonic dependency token; shared Resources never cache mutable water.
var geometry_revision: int = 0
var revision: int = 0
var _validation_issue: String = ""


## Runtime assignments must satisfy the same limits as editor-authored settings.
func validation_error() -> String:
	return _validation_issue


func _validate() -> String:
	if not sample_origin.is_finite():
		return "TileFluidSurfaceSettings.sample_origin must be finite."
	if not is_finite(sample_spacing) or sample_spacing < 8.0:
		return "TileFluidSurfaceSettings.sample_spacing must be finite and at least 8 pixels."
	if not is_finite(dry_seconds) or dry_seconds < 0.0:
		return "TileFluidSurfaceSettings.dry_seconds must be finite and nonnegative."
	if maximum_cells < 1:
		return "TileFluidSurfaceSettings.maximum_cells must be positive."
	return ""
