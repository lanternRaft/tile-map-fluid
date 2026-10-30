@icon("res://addons/tile_map_fluid/assets/icons/presentation.svg")
class_name WetSurfaceRow
extends MeshInstance2D
## One atomic ordering band, combining full rectangles and clipped polygons in the same mesh.

## Layer-local sort anchor, fixed until this band's geometry changes.
var anchor: Vector2
## Covered cells represented by this batch; holes allocate no vertices.
var cell_count: int = 0
## Triangle and vertex counts for resource diagnostics.
var triangle_count: int = 0
## Combined geometry vertices, including clipped boundary outlines.
var vertex_count: int = 0
var _slots: PackedInt32Array = []


## Triangulate unchanged CPU coverage once; saturation is fetched by the shared vertex shader.
func configure(grid: WetGridSimulation, cells: Array[Vector2i], origin: Vector2,
		atlas: WetSurfaceAtlas, water_material: ShaderMaterial, artwork: Texture2D) -> void:
	anchor = origin
	cell_count = cells.size()
	material = water_material
	texture = artwork
	var vertices: PackedVector2Array = []
	var lookups: PackedVector2Array = []
	var indices: PackedInt32Array = []
	for cell: Vector2i in cells:
		for patch: WetFieldPatch in grid.cell_patches(cell):
			var polygon: PackedVector2Array = Transform2D(0.0, -origin) * patch.polygon
			var triangles: PackedInt32Array = Geometry2D.triangulate_polygon(polygon)
			if triangles.is_empty():
				continue
			var slot: int = atlas.allocate(patch, origin)
			_slots.append(slot)
			var first: int = vertices.size()
			vertices.append_array(polygon)
			for point: int in range(polygon.size()):
				# UV is an exact integer address, not a fractional UV packed with a large ID.
				# The shader derives artwork UV from the unquantized vertex and patch domain.
				lookups.append(Vector2(slot * 2, 0))
			for index: int in triangles:
				indices.append(first + index)
	vertex_count = vertices.size()
	@warning_ignore("integer_division")
	triangle_count = indices.size() / 3
	if vertices.is_empty():
		return
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_TEX_UV] = lookups
	arrays[Mesh.ARRAY_INDEX] = indices
	var combined: ArrayMesh = ArrayMesh.new()
	combined.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	mesh = combined


## Return only this band's topology slots before replacing or removing its mesh.
func release(atlas: WetSurfaceAtlas) -> void:
	atlas.release(_slots)
	_slots.clear()
