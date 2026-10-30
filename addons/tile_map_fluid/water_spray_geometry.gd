class_name WaterSprayGeometry
extends RefCounted
## Shared cone and contact probes for direct water and host plant-care targeting.


## Radial reach clips the widening cone; the outlet has a minimum half-width.
static func contains(point: Vector2, origin: Vector2, facing: Vector2,
		reach: float, spread: float) -> bool:
	var offset: Vector2 = point - origin
	var forward: float = offset.dot(facing)
	return forward >= 0.0 and offset.length() <= reach \
		and absf(offset.cross(facing)) <= maxf(8.0, forward * tan(deg_to_rad(spread)))


## Preserve the game's ray contract: the receiving body may be the final hit.
static func reaches(world: World2D, point: Vector2, origin: Vector2, facing: Vector2,
		reach: float, spread: float, mask: int, target: CollisionObject2D = null) -> bool:
	if not contains(point, origin, facing, reach, spread):
		return false
	var query: PhysicsRayQueryParameters2D = PhysicsRayQueryParameters2D.create(origin, point, mask)
	query.hit_from_inside = true
	var hit: Dictionary = world.direct_space_state.intersect_ray(query)
	return hit.is_empty() or (target != null and hit.get("collider") == target)


## Try the shape center, then its nearest point to the finite spray axis.
## This intentionally preserves the game's two-probe policy rather than exact shape overlap.
static func reaches_shape(world: World2D, contact: CollisionShape2D, origin: Vector2,
		facing: Vector2, reach: float, spread: float, mask: int,
		target: CollisionObject2D = null) -> bool:
	if reaches(world, contact.global_position, origin, facing, reach, spread, mask, target):
		return true
	if contact.shape == null:
		return false
	var forward: float = clampf((contact.global_position - origin).dot(facing), 0.0, reach)
	var local: Vector2 = contact.to_local(origin + facing * forward)
	if contact.shape is CircleShape2D:
		local = local.limit_length((contact.shape as CircleShape2D).radius)
	else:
		var bounds: Rect2 = contact.shape.get_rect()
		local = local.clamp(bounds.position, bounds.end)
	return reaches(world, contact.to_global(local), origin, facing, reach, spread, mask, target)
