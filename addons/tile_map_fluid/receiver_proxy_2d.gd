class_name TileFluidReceiverProxy2D
extends Area2D
## Addon-owned conservative physics bounds; delivery still checks the receiver's exact geometry.

## Private query layer, independent of gameplay collision layers and authored receiver Areas.
const QUERY_LAYER: int = 1 << 31
## Recent changes supplement the physics snapshot until registration catches up.
const PENDING_GROUP: StringName = &"tile_fluid_pending_proxies"

## Receiver owning this runtime-only child.
var receiver: TileFluidWettable2D
var _rectangle: RectangleShape2D = RectangleShape2D.new()
var _bounds: Rect2
var _pending_frame: int = -1


func _enter_tree() -> void:
	_pending_frame = Engine.get_physics_frames()
	add_to_group(PENDING_GROUP)


func _ready() -> void:
	collision_layer = QUERY_LAYER
	collision_mask = 0
	monitoring = false
	monitorable = true
	disable_mode = CollisionObject2D.DISABLE_MODE_KEEP_ACTIVE
	process_physics_priority = -100
	var contact: CollisionShape2D = CollisionShape2D.new()
	contact.shape = _rectangle
	add_child(contact)
	set_as_top_level(true)
	synchronize()


func _physics_process(_delta: float) -> void:
	synchronize()
	if Engine.get_physics_frames() > _pending_frame + 1:
		remove_from_group(PENDING_GROUP)


## Update broad bounds after receiver transforms, direct-marker movement or contact changes.
func synchronize() -> void:
	if not is_inside_tree() or not is_instance_valid(receiver):
		return
	var point: Vector2 = receiver.water_position()
	if not point.is_finite():
		return
	var bounds: Rect2 = Rect2(point - Vector2.ONE, Vector2.ONE * 2.0)
	if is_instance_valid(receiver.footprint) and receiver.footprint.shape != null \
			and not receiver.footprint.disabled:
		bounds = bounds.merge(receiver.footprint.global_transform * receiver.footprint.shape.get_rect())
	if bounds == _bounds:
		return
	_bounds = bounds
	_rectangle.size = bounds.size
	global_transform = Transform2D(0.0, bounds.get_center())
	_pending_frame = Engine.get_physics_frames()
	add_to_group(PENDING_GROUP)


## Only short-lived unsynchronized changes use a fallback, never a full room traversal.
func pending_in(bounds: Rect2, world: World2D) -> bool:
	if not is_inside_tree():
		return false
	if Engine.get_physics_frames() > _pending_frame + 1:
		remove_from_group(PENDING_GROUP)
		return false
	if get_world_2d() != world:
		return false
	synchronize()
	return _bounds.intersects(bounds, true)
