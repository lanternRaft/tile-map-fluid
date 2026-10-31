@icon("res://addons/tile_map_fluid/assets/icons/simulation.svg")
@abstract class_name TileFluidSurfaceSimulation
extends Node
## Typed backend boundary. Use TileFluidGridSimulation for the reusable clipped field.
## Runtime saturation belongs to this node, never a shared Resource or TileData.

## Reports a changed saturation field (also after evaporation or coverage replacement).
signal changed


## Backends use only their owning surface's physics world, including during staged preparation.
func _world() -> World2D:
	var surface: TileFluidSurface2D = get_parent() as TileFluidSurface2D
	return surface.get_world_2d() if surface != null and surface.is_inside_tree() else null


## Backends may explain bounded-allocation or geometry failures through the owning surface.
func validation_error() -> String:
	return ""


## Backend notification after mutating its owned saturation field.
func notify_changed() -> void:
	changed.emit()


## Replace coverage, retaining water on unaffected samples and initializing new coverage dry.
## Polygons are layer-local; pose converts those coordinates to world space for obstruction.
@abstract func configure(coverage: TileFluidSurfaceCoverage, pose: Transform2D,
		settings: TileFluidSurfaceSettings) -> void


## Optional regional updates; custom backends may retain their full-refresh implementation.


func update_region(coverage: TileFluidSurfaceCoverage, pose: Transform2D,
		settings: TileFluidSurfaceSettings, _area: Rect2, _seam_neighbors: bool = true) -> void:
	configure(coverage, pose, settings)


## Deposit a normalized dose at a layer-local point; clamp each touched sample to [0, 1].


@abstract func deposit(point: Vector2, dose: float) -> bool

## Visit the UNION of footprint shapes once per emission, applying dose once per sample.
## Use footprint.contains_world_point and TileFluidVisibility2D for geometry and obstruction.


@abstract func stamp(footprint: TileFluidFootprint2D, dose: float, source: Vector2,
		obstacle_mask: int, exclusions: Array[RID]) -> bool

## Sample local saturation/traction, returning zero outside valid clipped patches.


@abstract func sample(point: Vector2) -> float

## Advance by scaled physics seconds; zero dry_seconds disables evaporation.


@abstract func advance(delta: float, dry_seconds: float) -> void
