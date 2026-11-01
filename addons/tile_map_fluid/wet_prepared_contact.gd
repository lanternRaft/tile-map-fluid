class_name TileFluidPreparedContact
extends RefCounted
## Internal geometry-only receiver handle. Invalidated before any reused sample-slot read.
## Contact conditions, ownership and World2D are checked live by Wettable.advance().
var surface: TileFluidSurface2D
var grid: TileFluidGridSimulation
var revision: int = -1
var geometry_revision: int = -1
var point: Vector2
var pose: Transform2D
var supported: bool = false
var patch_id: int = 0
var corners: PackedInt32Array = []
var fraction: Vector2

func clear() -> void:
	surface = null
	grid = null
	patch_id = 0
	corners = PackedInt32Array()
	supported = false
	revision = -1
	geometry_revision = -1
