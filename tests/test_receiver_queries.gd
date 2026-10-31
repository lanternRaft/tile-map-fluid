extends "res://tests/test_case.gd"

const Fixture: PackedScene = preload("res://tests/fixtures/wetness_simulation.tscn")


func _world() -> Node2D:
	var view: SubViewport = track(SubViewport.new()) as SubViewport
	view.world_2d = World2D.new()
	var world: Node2D = Fixture.instantiate() as Node2D
	view.add_child(world)
	add_child(view)
	return world


func _receiver(world: Node2D, point: Vector2) -> TileFluidWettable2D:
	var receiver: TileFluidWettable2D = TileFluidWettable2D.new()
	receiver.position = point
	receiver.surface = world.get_node("Layer/Surface") as TileFluidSurface2D
	receiver.monitoring = false
	receiver.monitorable = false
	receiver.collision_layer = 0
	world.add_child(receiver)
	receiver.set_physics_process(false)
	return receiver


## Discovery needs no authored shapes, explicit list, monitoring, or first physics frame.
func test_shape_free_receiver_and_same_tick_emitter_move() -> void:
	var world: Node2D = _world()
	var emitter: TileFluidEmitter2D = world.get_node("Emitter") as TileFluidEmitter2D
	emitter.receivers.clear()
	var receiver: TileFluidWettable2D = _receiver(world, Vector2(200, 16))
	emitter.footprint.global_position = receiver.global_position
	check(emitter.emit_dose(0.2))
	check(is_equal_approx(receiver.saturation, 0.2))
	await frames(4)
	emitter.footprint.global_position = Vector2(16, 16)
	check(emitter.emit_dose(0.2))
	check(is_equal_approx(receiver.saturation, 0.2))
	emitter.footprint.global_position = receiver.global_position
	check(emitter.emit_dose(0.2))
	check(is_equal_approx(receiver.saturation, 0.4))


## Crowded queries paginate rather than silently dropping hits at the engine result limit.
func test_crowded_query_and_union_deliver_once_after_physics_registration() -> void:
	var world: Node2D = _world()
	var emitter: TileFluidEmitter2D = world.get_node("Emitter") as TileFluidEmitter2D
	var contacts: Array[TileFluidWettable2D] = []
	for index: int in range(130):
		contacts.append(_receiver(world, Vector2(16, 16)))
	emitter.receivers.assign([contacts[0], contacts[0]])
	await frames(4)
	check(emitter.emit_dose(0.25))
	for receiver: TileFluidWettable2D in contacts:
		check(is_equal_approx(receiver.saturation, 0.25))


## Recent transforms supplement stale broad-phase positions, without leaking worlds or visibility.
func test_moved_hidden_and_other_world_receivers() -> void:
	var world: Node2D = _world()
	var emitter: TileFluidEmitter2D = world.get_node("Emitter") as TileFluidEmitter2D
	emitter.receivers.clear()
	var receiver: TileFluidWettable2D = _receiver(world, Vector2(200, 16))
	var other_world: Node2D = _world()
	var other: TileFluidWettable2D = _receiver(other_world, Vector2(16, 16))
	await frames(4)
	receiver.position = Vector2(16, 16)
	check(emitter.emit_dose(0.2))
	check(is_equal_approx(receiver.saturation, 0.2))
	check(is_zero_approx(other.saturation))
	receiver.hide()
	emitter.emit_dose(0.2)
	check(is_equal_approx(receiver.saturation, 0.2))
	receiver.show()
	world.remove_child(receiver)
	world.add_child(receiver)
	emitter.emit_dose(0.2)
	check(is_equal_approx(receiver.saturation, 0.4))


## Broad bounds include lifted direct markers and ground footprints used by cone sprays.
func test_proxy_covers_marker_and_ground_shape() -> void:
	var world: Node2D = _world()
	var receiver: TileFluidWettable2D = _receiver(world, Vector2(300, 100))
	var marker: Marker2D = Marker2D.new()
	marker.position = Vector2(-200, 0)
	receiver.add_child(marker)
	receiver.direct_point = marker
	var footprint: CollisionShape2D = CollisionShape2D.new()
	var rectangle: RectangleShape2D = RectangleShape2D.new()
	rectangle.size = Vector2(80, 40)
	footprint.shape = rectangle
	receiver.add_child(footprint)
	receiver.footprint = footprint
	await frames(4)
	check(TileFluidReceiverQuery.in_bounds(world, Rect2(95, 95, 10, 10)).has(receiver))
	check(TileFluidReceiverQuery.in_bounds(world, Rect2(330, 95, 10, 10)).has(receiver))


## Parenting a receiver into another World2D cannot keep its old proxy discoverable.
func test_reparent_between_worlds_updates_query_registration() -> void:
	var world: Node2D = _world()
	var other_world: Node2D = _world()
	var receiver: TileFluidWettable2D = _receiver(world, Vector2(16, 16))
	await frames(4)
	receiver.reparent(other_world)
	var bounds: Rect2 = Rect2(8, 8, 16, 16)
	check(not TileFluidReceiverQuery.in_bounds(world, bounds).has(receiver))
	check(TileFluidReceiverQuery.in_bounds(other_world, bounds).has(receiver))


## The cone spray uses the same query path, including a zero-width cone and optional scope.
func test_spray_queries_without_explicit_receivers_and_respects_scope() -> void:
	var world: Node2D = _world()
	var receiver: TileFluidWettable2D = _receiver(world, Vector2(48, 16))
	var spray: TileFluidSpray2D = TileFluidSpray2D.new()
	spray.surface = receiver.surface
	spray.position = Vector2(0, 16)
	spray.settings.spread = 0.0
	spray.settings.obstacle_mask = 0
	world.add_child(spray)
	spray.set_physics_process(false)
	await frames(4)
	spray.emit_dose(0.2)
	check(is_equal_approx(receiver.saturation, 0.2))
	var scope: Node2D = Node2D.new()
	world.add_child(scope)
	spray.receiver_scope = scope
	spray.emit_dose(0.2)
	check(is_equal_approx(receiver.saturation, 0.2))
