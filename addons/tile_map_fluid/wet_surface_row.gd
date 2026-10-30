class_name WetSurfaceRow
extends MultiMeshInstance2D
## Atomic horizontal water slice. Full patches are batched; only clipped edges need polygons.

const WATER_SHADER: Shader = preload("res://addons/tile_map_fluid/assets/wet_surface.gdshader")

var _full: Array[WetFieldPatch] = []
var _edges: Array[WetFieldPatch] = []
var _materials: Array[ShaderMaterial] = []


## Build fixed geometry once per coverage revision, reusing the original bilinear shader.
func configure(grid: WetGridSimulation, cells: Array[Vector2i], anchor: Vector2,
		appearance: WetSurfaceAppearance) -> void:
	texture = appearance.texture
	material = _material(appearance.tint)
	for cell: Vector2i in cells:
		for patch: WetFieldPatch in grid.cell_patches(cell):
			if _is_rectangle(patch):
				_full.append(patch)
			else:
				_add_edge(patch, anchor, appearance)
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2.ONE
	var batch: MultiMesh = MultiMesh.new()
	batch.transform_format = MultiMesh.TRANSFORM_2D
	batch.use_custom_data = true
	batch.mesh = quad
	batch.instance_count = _full.size()
	multimesh = batch
	for index: int in range(_full.size()):
		var bounds: Rect2 = _full[index].bounds
		batch.set_instance_transform_2d(index, Transform2D(
			0.0, bounds.size, 0.0, bounds.get_center() - anchor))
	refresh(grid)


## Upload saturation alone; no geometry, TileSet, material resource, or physics replacement.
func refresh(grid: WetGridSimulation) -> void:
	for index: int in range(_full.size()):
		multimesh.set_instance_custom_data(index, grid.patch_water(_full[index]))
	for index: int in range(_edges.size()):
		_materials[index].set_shader_parameter("patch_saturation", grid.patch_water(_edges[index]))


func _add_edge(patch: WetFieldPatch, anchor: Vector2,
		appearance: WetSurfaceAppearance) -> void:
	var artwork: Polygon2D = Polygon2D.new()
	var outline: PackedVector2Array = []
	for point: Vector2 in patch.polygon:
		outline.append((point - patch.bounds.position) / patch.bounds.size - Vector2.ONE * 0.5)
	artwork.polygon = outline
	artwork.position = patch.bounds.get_center() - anchor
	artwork.scale = patch.bounds.size
	artwork.texture = appearance.texture
	var shader_material: ShaderMaterial = _material(appearance.tint)
	shader_material.set_shader_parameter("use_patch_water", true)
	artwork.material = shader_material
	add_child(artwork)
	_edges.append(patch)
	_materials.append(shader_material)


func _material(tint: Color) -> ShaderMaterial:
	var result: ShaderMaterial = ShaderMaterial.new()
	result.shader = WATER_SHADER
	result.set_shader_parameter("water_tint", tint)
	return result


func _is_rectangle(patch: WetFieldPatch) -> bool:
	if patch.polygon.size() != 4:
		return false
	for point: Vector2 in patch.polygon:
		if not (is_equal_approx(point.x, patch.bounds.position.x)
				or is_equal_approx(point.x, patch.bounds.end.x)) \
				or not (is_equal_approx(point.y, patch.bounds.position.y)
				or is_equal_approx(point.y, patch.bounds.end.y)):
			return false
	return true
