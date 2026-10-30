class_name WetSurfaceMetrics
extends RefCounted
## Read-only lattice diagnostics for tools; sparse simulation storage remains authoritative.


## Size of the coverage envelope in lattice cells, including uncovered holes.
static func dimensions(surface: WetSurface2D) -> Vector2i:
	var bounds: Rect2 = surface.coverage_bounds()
	var spacing: float = surface.settings.sample_spacing
	var origin: Vector2 = surface.settings.sample_origin
	return Vector2i(((bounds.end - origin) / spacing).ceil()) \
		- Vector2i(((bounds.position - origin) / spacing).floor())


## Layer-local cell coordinates for an arbitrary contact.
static func cell_at(surface: WetSurface2D, point: Vector2) -> Vector2i:
	return Vector2i(((point - surface.settings.sample_origin) /
		surface.settings.sample_spacing).floor())


## Layer-local row-major rectangle within the coverage envelope.
static func cell_rect(surface: WetSurface2D, index: int) -> Rect2:
	var size: Vector2i = dimensions(surface)
	if size.x <= 0:
		return Rect2()
	@warning_ignore("integer_division")
	var cell: Vector2i = Vector2i(index % size.x, index / size.x)
	var bounds: Rect2 = surface.coverage_bounds()
	cell += cell_at(surface, bounds.position)
	var point: Vector2 = surface.settings.sample_origin \
		+ Vector2(cell) * surface.settings.sample_spacing
	return Rect2(point, Vector2.ONE * surface.settings.sample_spacing).intersection(bounds)


## Count wet covered cells independently of rendering allocation.
static func wet_cell_count(surface: WetSurface2D) -> int:
	var grid: WetGridSimulation = surface.simulation as WetGridSimulation
	if grid == null:
		return 0
	var count: int = 0
	for cell: Vector2i in grid.covered_cells():
		for patch: WetFieldPatch in grid.cell_patches(cell):
			var water: Color = grid.patch_water(patch)
			if maxf(maxf(water.r, water.g), maxf(water.b, water.a)) > 0.0:
				count += 1
				break
	return count


## Enclose a world dirty rectangle in layer coordinates, including rotated/scaled fields.
static func local_bounds(pose: Transform2D, area: Rect2) -> Rect2:
	return WetFieldPolygons.bounds(pose.affine_inverse() *
		WetFieldPolygons.rectangle(area)) if area.has_area() else Rect2()
