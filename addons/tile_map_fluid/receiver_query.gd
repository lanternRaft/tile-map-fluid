class_name TileFluidReceiverQuery
extends RefCounted
## Shared direct broad phase for union emitters and cone sprays; no tracked overlap lists.


## Query a WORLD rectangle; paginate RIDs so crowded hits cannot be truncated.
static func in_bounds(subject: Node2D, bounds: Rect2) -> Array[TileFluidWettable2D]:
	var result: Array[TileFluidWettable2D] = []
	if not subject.is_inside_tree() or not bounds.has_area() \
			or not bounds.position.is_finite() or not bounds.size.is_finite():
		return result
	var world: World2D = subject.get_world_2d()
	var shape: RectangleShape2D = RectangleShape2D.new()
	shape.size = bounds.size
	var query: PhysicsShapeQueryParameters2D = PhysicsShapeQueryParameters2D.new()
	query.shape = shape
	query.transform = Transform2D(0.0, bounds.get_center())
	query.collision_mask = TileFluidReceiverProxy2D.QUERY_LAYER
	query.collide_with_areas = true
	query.collide_with_bodies = false
	var visited: Dictionary[TileFluidWettable2D, bool] = {}
	var exclusions: Array[RID] = []
	while true:
		query.exclude = exclusions
		var hits: Array[Dictionary] = world.direct_space_state.intersect_shape(query, 64)
		for hit: Dictionary in hits:
			exclusions.append(hit.rid)
			var proxy: TileFluidReceiverProxy2D = hit.collider as TileFluidReceiverProxy2D
			if proxy != null and proxy.is_inside_tree() and proxy.get_world_2d() == world:
				_append(result, visited, proxy.receiver)
		if hits.size() < 64:
			break
	# Only recently changed proxies supplement the physics snapshot, including same-tick spawns.
	for node: Node in subject.get_tree().get_nodes_in_group(TileFluidReceiverProxy2D.PENDING_GROUP):
		var proxy: TileFluidReceiverProxy2D = node as TileFluidReceiverProxy2D
		if proxy.pending_in(bounds, world):
			_append(result, visited, proxy.receiver)
	return result


static func _append(result: Array[TileFluidWettable2D],
		visited: Dictionary[TileFluidWettable2D, bool], receiver: TileFluidWettable2D) -> void:
	if is_instance_valid(receiver) and receiver.is_inside_tree() and not visited.has(receiver):
		visited[receiver] = true
		result.append(receiver)
