class_name TileFluidSurfaceWater
extends RefCounted
## Validated world-space deposits, union stamps and soft splashes over a surface backend.


## A soft splash preserves saturation-dependent radii without prescribing tool supply rules.
static func splash(surface: TileFluidSurface2D, point: Vector2, dose: float,
		initial_radius: float, maximum_radius: float) -> bool:
	if not point.is_finite() or not is_finite(dose) or dose <= 0.0 \
			or not is_finite(initial_radius) or initial_radius <= 0.0 \
			or not is_finite(maximum_radius) or maximum_radius <= 0.0 \
			or not surface.validation_error().is_empty():
		return false
	var grid: TileFluidGridSimulation = surface.simulation as TileFluidGridSimulation
	if grid == null or not surface.contains_world_point(point):
		return false
	var saturation: float = clampf(surface.saturation_at(point) + dose, 0.0, 1.0)
	return grid.splash(surface.tile_layer.to_local(point), dose,
		lerpf(initial_radius, maximum_radius, saturation), surface.settings.obstacle_mask)


## A point dose wets its containing interpolation patch.
static func deposit(surface: TileFluidSurface2D, point: Vector2, dose: float) -> bool:
	if not point.is_finite() or not is_finite(dose) or dose <= 0.0 \
			or not surface.validation_error().is_empty() or not surface.contains_world_point(point):
		return false
	return surface.simulation.deposit(surface.tile_layer.to_local(point), minf(dose, 1.0))


## The same finite, bounded interpolation path serves receivers and host movement.
static func sample(surface: TileFluidSurface2D, point: Vector2) -> float:
	if not point.is_finite() or not surface.validation_error().is_empty() \
			or not surface.contains_world_point(point):
		return 0.0
	var value: float = surface.simulation.sample(surface.tile_layer.to_local(point))
	return clampf(value, 0.0, 1.0) if is_finite(value) else 0.0


## One validated union dose per field contact.
static func stamp(surface: TileFluidSurface2D, footprint: TileFluidFootprint2D, dose: float,
		source: Vector2, obstacle_mask: int, exclusions: Array[RID]) -> bool:
	if footprint == null or not source.is_finite() or not is_finite(dose) or dose <= 0.0:
		return false
	if not surface.validation_error().is_empty() or not footprint.validation_error().is_empty():
		return false
	if not surface.is_inside_tree() or not footprint.is_inside_tree() \
			or surface.get_world_2d() != footprint.get_world_2d():
		return false
	return surface.simulation.stamp(footprint, minf(dose, 1.0), source, obstacle_mask, exclusions)
