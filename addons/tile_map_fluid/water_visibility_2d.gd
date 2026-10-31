class_name TileFluidVisibility2D
extends RefCounted


## Only solid bodies obstruct water; receiver Areas never intercept a floor dose.
## Source bodies are explicitly excluded; a receiver's own body may be the final ray hit.
static func reaches(world: World2D, source: Vector2, point: Vector2, mask: int,
		exclusions: Array[RID] = [], target: CollisionObject2D = null) -> bool:
	if not source.is_finite() or not point.is_finite():
		return false
	if mask == 0 or source.is_equal_approx(point):
		return true
	if world == null:
		return false
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(
		source, point, mask, exclusions)
	query.collide_with_areas = false
	query.hit_from_inside = true
	var ignored: Array[RID] = exclusions.duplicate()
	for attempt: int in range(16):
		var hit: Dictionary = world.direct_space_state.intersect_ray(query)
		if hit.is_empty() or (is_instance_valid(target) and hit.get("collider") == target):
			return true
		var collider: Node = hit.get("collider") as Node
		if collider == null or not collider.get_meta(&"water_underpaint", false) \
				or not TileFluidFieldObstacles.contains_hit(point, hit):
			return false
		# Entering underpaint must not hide a second hard barrier on the same ray.
		ignored.append(hit["rid"])
		query.exclude = ignored
	return false
