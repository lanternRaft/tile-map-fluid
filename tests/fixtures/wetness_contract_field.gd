extends TileFluidSurfaceSimulation
## Contract probe, not a grid simulation: two fixed contacts expose dispatch and ownership.

## Layer-local probes match the two authored placements of one shared atlas tile.
@export var points: PackedVector2Array = PackedVector2Array([Vector2(16, 16), Vector2(48, 16)])

var _water: PackedFloat32Array = PackedFloat32Array([0.0, 0.0])
var _coverage: TileFluidSurfaceCoverage
var _pose: Transform2D


## Retain valid contacts while allowing coverage tests to remove a placement.
func configure(coverage: TileFluidSurfaceCoverage, pose: Transform2D,
		_settings: TileFluidSurfaceSettings) -> void:
	_coverage = coverage
	_pose = pose
	for index: int in range(points.size()):
		if not coverage.contains(points[index]):
			_water[index] = 0.0


## Only exact probe contacts are supported; interpolation belongs to the extracted backend.
func deposit(point: Vector2, dose: float) -> bool:
	var index: int = _index(point)
	if index < 0:
		return false
	_water[index] = clampf(_water[index] + dose, 0.0, 1.0)
	changed.emit()
	return true


## Visit each probe once, independent of how many footprint shapes contain it.
func stamp(footprint: TileFluidFootprint2D, dose: float, source: Vector2,
		obstacle_mask: int, exclusions: Array[RID]) -> bool:
	var applied: bool = false
	for point: Vector2 in points:
		var world_point: Vector2 = _pose * point
		if _coverage.contains(point) and footprint.contains_world_point(world_point) \
				and TileFluidVisibility2D.reaches(footprint.get_world_2d(), source,
					world_point, obstacle_mask, exclusions):
			applied = deposit(point, dose) or applied
	return applied


## Observable probe saturation, without rendering or TileData runtime mutation.
func sample(point: Vector2) -> float:
	var index: int = _index(point)
	return _water[index] if index >= 0 else 0.0


## Exposes physics-time dispatch while leaving real evaporation extraction to section 3.
func advance(delta: float, dry_seconds: float) -> void:
	if dry_seconds <= 0.0:
		return
	for index: int in range(_water.size()):
		_water[index] = maxf(0.0, _water[index] - delta / dry_seconds)
	changed.emit()


func _index(point: Vector2) -> int:
	for index: int in range(points.size()):
		if points[index].is_equal_approx(point):
			return index
	return -1
