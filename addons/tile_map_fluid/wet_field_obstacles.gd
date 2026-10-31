class_name TileFluidFieldObstacles
extends RefCounted
## Stock-physics clipping. Geometry masks are independent of emitter visibility masks.


## Hard barriers split interpolation patches; unsupported shapes conservatively remove coverage.
static func clip(world: World2D, pose: Transform2D, rect: Rect2, mask: int,
		pieces: Array[PackedVector2Array]) -> Array[PackedVector2Array]:
	if world == null or mask == 0:
		return pieces
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = rect.size - Vector2.ONE * 0.002
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = pose * Transform2D(0.0, rect.get_center())
	query.collision_mask = mask
	var hits: Array[Dictionary] = world.direct_space_state.intersect_shape(query, 64)
	if hits.size() == 64:
		return []
	for hit: Dictionary in hits:
		var collider: Node = hit.get("collider") as Node
		if collider != null and collider.get_meta(&"water_underpaint", false):
			continue
		var outline: PackedVector2Array = _polygon(hit, pose.affine_inverse())
		if outline.is_empty():
			return []
		pieces = TileFluidFieldPolygons.subtract(pieces, outline)
		if pieces.is_empty():
			break
	return pieces


## Underpaint rays may enter an opted-in body but must not pass out of its far side.
static func contains_hit(point: Vector2, hit: Dictionary) -> bool:
	var outline: PackedVector2Array = _polygon(hit, Transform2D.IDENTITY)
	return not outline.is_empty() and Geometry2D.is_point_in_polygon(point, outline)


static func _polygon(hit: Dictionary, inverse: Transform2D) -> PackedVector2Array:
	var body: RID = hit["rid"]
	var index: int = hit["shape"]
	var shape: RID = PhysicsServer2D.body_get_shape(body, index)
	var pose: Transform2D = PhysicsServer2D.body_get_state(
		body, PhysicsServer2D.BODY_STATE_TRANSFORM)
	pose = inverse * pose * PhysicsServer2D.body_get_shape_transform(body, index)
	var data: Variant = PhysicsServer2D.shape_get_data(shape)
	match PhysicsServer2D.shape_get_type(shape):
		PhysicsServer2D.SHAPE_RECTANGLE:
			var half_size: Vector2 = data
			return pose * TileFluidSurfaceCoverage.rectangle(Rect2(-half_size, half_size * 2.0))
		PhysicsServer2D.SHAPE_CONVEX_POLYGON:
			return pose * (data as PackedVector2Array)
	return PackedVector2Array()
