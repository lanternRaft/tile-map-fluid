extends "res://tests/test_case.gd"
## Exact differential checks: no numeric tolerance is needed; operation/Color precision is retained.
const Fixture: PackedScene = preload("res://tests/fixtures/wetness_simulation.tscn")

class ReferenceWettable extends TileFluidWettable2D:
	# Frozen Stage 1 baseline advance; public sampling remains available for arbitrary reads.
	func advance(delta: float) -> void:
		refresh_contact()
		if not is_finite(delta) or delta <= 0.0 or settings == null \
				or not settings.validation_error().is_empty():
			return
		surface_saturation = 0.0
		if contact_enabled and is_instance_valid(surface) and is_inside_tree() \
				and surface.is_inside_tree() and surface.get_world_2d() == get_world_2d():
			var point: Vector2 = contact_point.global_position \
				if is_instance_valid(contact_point) else global_position
			surface_saturation = surface.saturation_at(point)
		var amount: float = _saturation
		if settings.dry_seconds > 0.0:
			amount = maxf(0.0, amount - delta / settings.dry_seconds)
		if surface_saturation > amount:
			amount = move_toward(amount, surface_saturation, settings.ground_absorption * delta)
		_set_saturation(amount)
		_traction.apply(traction_body, surface if contact_enabled else null, surface_saturation)

func _world() -> Node2D:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	for path: String in ["Layer/Surface", "OtherLayer/Surface"]:
		var surface: TileFluidSurface2D = world.get_node(path)
		surface.settings = surface.settings.duplicate()
	add_child(world)
	return world

func _compare(surface: TileFluidSurface2D, handle: TileFluidPreparedContact, point: Vector2) -> void:
	check(surface._sample_contact(point, handle) == surface.saturation_at(point),
		"Prepared and reference values must match exactly at %s" % point)

func test_live_samples_movement_seams_and_drying() -> void:
	var world := _world()
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface")
	var grid: TileFluidGridSimulation = surface.simulation
	var handle := TileFluidPreparedContact.new()
	for tick: int in range(240):
		var point := Vector2(16 + tick % 65, 16)
		_compare(surface, handle, point)
		grid.deposit(point, 0.023)
		_compare(surface, handle, point) # Same tick, including a previously dry handle.
		grid.deposit(point + Vector2(16, 0), 0.07) # Overlapping ordered deposits.
		_compare(surface, handle, point)
		grid.advance(1.0 / 120.0, 0.8)
		_compare(surface, handle, point)
	for point: Vector2 in [Vector2.ZERO, Vector2(32, 16), Vector2(64, 16), Vector2(-0.001, 16), Vector2(INF, 0)]:
		_compare(surface, handle, point)

func test_settings_transform_replacement_and_slot_reuse() -> void:
	var world := _world()
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface")
	var grid: TileFluidGridSimulation = surface.simulation
	var handle := TileFluidPreparedContact.new()
	var point := Vector2(16, 16)
	surface.deposit(point, 0.7)
	_compare(surface, handle, point)
	for spacing: float in [16.0, 32.0, 8.0]:
		surface.settings.sample_spacing = spacing
		_compare(surface, handle, point)
	surface.settings.dry_seconds = -1
	_compare(surface, handle, point)
	surface.settings.dry_seconds = 72
	_compare(surface, handle, point)
	surface.settings = surface.settings.duplicate()
	_compare(surface, handle, point)
	for pose: Transform2D in [Transform2D(0.3, Vector2(5, 9)), Transform2D.IDENTITY]:
		surface.tile_layer.transform = pose
		_compare(surface, handle, point)
	grid.reset(surface.settings)
	_compare(surface, handle, point)
	surface.refresh_coverage()
	for index: int in range(4):
		var pieces: Dictionary[Vector2i, Array] = {Vector2i.ZERO: []}
		grid.replace_cells(pieces, surface.tile_layer.global_transform, surface.settings)
		_compare(surface, handle, point)
		pieces[Vector2i.ZERO] = [PackedVector2Array([Vector2.ZERO, Vector2(32, 0), Vector2(0, 32)])]
		grid.replace_cells(pieces, surface.tile_layer.global_transform, surface.settings)
		for p: Vector2 in [point, Vector2(15, 15), Vector2(17, 17), Vector2(16.001, 16), Vector2(31, 0)]:
			_compare(surface, handle, p)
		grid.deposit(Vector2(8, 8), 0.2)
		_compare(surface, handle, Vector2(8, 8))
	var old: TileFluidSurfaceSimulation = surface.simulation
	surface.simulation = TileFluidGridSimulation.new()
	surface.add_child(surface.simulation)
	old.free()
	_compare(surface, handle, point)

func test_receiver_tick_signals_contact_marker_reparent_and_settings() -> void:
	var world := _world()
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface")
	var cached := TileFluidWettable2D.new()
	var reference := ReferenceWettable.new()
	var events: Array = []
	var expected: Array = []
	for receiver: TileFluidWettable2D in [cached, reference]:
		world.add_child(receiver)
		receiver.set_physics_process(false)
		receiver.surface = surface
		receiver.position = Vector2(16, 16)
		var marker := Node2D.new()
		receiver.add_child(marker)
		receiver.contact_point = marker
	cached.changed.connect(func(value: float) -> void:
		events.append(["changed", value, surface.saturation_at(cached.global_position)]))
	reference.changed.connect(func(value: float) -> void:
		expected.append(["changed", value, surface.saturation_at(reference.global_position)]))
	cached.contact_changed.connect(func(value: bool) -> void: events.append(["contact", value]))
	reference.contact_changed.connect(func(value: bool) -> void: expected.append(["contact", value]))
	cached.water_added.connect(func(value: float) -> void: events.append(["water", value]))
	reference.water_added.connect(func(value: float) -> void: expected.append(["water", value]))
	for tick: int in range(180):
		surface.deposit(Vector2(16, 16), 0.03)
		for receiver: TileFluidWettable2D in [cached, reference]:
			receiver.contact_enabled = tick % 20 < 15
			receiver.settings.ground_absorption = 0.7 if tick % 3 else 0.1
			receiver.settings.dry_seconds = -1.0 if tick % 30 == 0 else 7.0
			if tick % 11 == 0:
				receiver.add_water(0.021)
			receiver.contact_point.position = Vector2(tick % 40, 0)
			receiver.advance(1.0 / 120.0)
		check(cached.surface_saturation == reference.surface_saturation)
		check(cached.saturation == reference.saturation)
		check(events == expected, "Signal payloads and ordering match every tick")
		surface.simulation.advance(1.0 / 120.0, 72)
	for receiver: TileFluidWettable2D in [cached, reference]:
		receiver.contact_point.free()
		receiver.reparent(surface)
		receiver.surface = world.get_node("OtherLayer/Surface")
		receiver.advance(1.0 / 120.0)
	check(cached.surface_saturation == reference.surface_saturation)
	check(cached.saturation == reference.saturation)

func test_reentrant_reads_after_writes_and_layer_lifetime() -> void:
	var world := _world()
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface")
	var handle := TileFluidPreparedContact.new()
	var point := Vector2(16, 16)
	_compare(surface, handle, point)
	var calls: Array[int] = []
	var read_on_change := func() -> void:
		calls.append(1)
		_compare(surface, handle, point)
	surface.changed.connect(read_on_change)
	# Every write emits synchronously; the callback must see this write immediately.
	for dose: float in [0.1, 0.2, 0.8]:
		surface.deposit(point, dose)
	check(calls.size() == 3)
	surface.changed.disconnect(read_on_change)
	var replacement: TileMapLayer = world.get_node("OtherLayer")
	surface.tile_layer = replacement
	_compare(surface, handle, point)
	var old_layer: Node = world.get_node("Layer")
	# Keep the surface alive while its former layer is freed.
	surface.reparent(world)
	old_layer.free()
	_compare(surface, handle, point)
	surface.tile_layer = null
	_compare(surface, handle, point)

func test_drying_edits_do_not_rebuild_geometry_and_invalid_validation_recovers() -> void:
	var world := _world()
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface")
	var handle := TileFluidPreparedContact.new()
	var point := Vector2(16, 16)
	surface.deposit(point, 0.8)
	_compare(surface, handle, point)
	var revision: int = surface.simulation.geometry_revision
	for seconds: float in [1.0, 0.0, 72.0]:
		surface.settings.dry_seconds = seconds
		_compare(surface, handle, point)
		check(surface.simulation.geometry_revision == revision)
	for invalid: float in [-1.0, INF, NAN]:
		surface.settings.dry_seconds = invalid
		check(not surface.settings.validation_error().is_empty())
		_compare(surface, handle, point)
		surface.settings.dry_seconds = 72.0
		check(surface.settings.validation_error().is_empty())
		_compare(surface, handle, point)
	surface.settings.receives_water_by_default = false
	_compare(surface, handle, point)
	check(surface._sample_contact(point, handle) == 0.0)
	surface.settings.receives_water_by_default = true
	_compare(surface, handle, point)

func test_all_settings_validation_dependencies_and_shared_resource_edits() -> void:
	var settings := TileFluidWettableSettings.new()
	check(settings.validation_error().is_empty())
	for property: String in ["dry_seconds", "ground_absorption"]:
		for value: float in [-1.0, NAN, INF]:
			settings.set(property, value)
			check(not settings.validation_error().is_empty())
			settings.set(property, 1.0)
			check(settings.validation_error().is_empty())
	var floor_settings := TileFluidSurfaceSettings.new()
	check(floor_settings.validation_error().is_empty())
	for change: Array in [["sample_origin", Vector2(INF, 0), Vector2.ZERO],
		["sample_spacing", 0.0, 32.0], ["maximum_cells", 0, 65536]]:
		floor_settings.set(change[0], change[1])
		check(not floor_settings.validation_error().is_empty())
		floor_settings.set(change[0], change[2])
		check(floor_settings.validation_error().is_empty())
	var world := _world()
	var first: TileFluidSurface2D = world.get_node("Layer/Surface")
	var second: TileFluidSurface2D = world.get_node("OtherLayer/Surface")
	second.settings = first.settings
	var a := TileFluidPreparedContact.new()
	var b := TileFluidPreparedContact.new()
	for origin: Vector2 in [Vector2(4, 2), Vector2.ZERO]:
		first.settings.sample_origin = origin
		_compare(first, a, Vector2(16, 16))
		_compare(second, b, Vector2(16, 16))

func test_world_changes_automatic_contact_conditions_and_marker_replacement() -> void:
	var world := _world()
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface")
	surface.contact_scope = world
	surface.deposit(Vector2(16, 16), 0.7)
	var cached := TileFluidWettable2D.new()
	var reference := ReferenceWettable.new()
	for receiver: TileFluidWettable2D in [cached, reference]:
		world.add_child(receiver)
		receiver.set_physics_process(false)
		receiver.position = Vector2(16, 16)
		receiver.automatic_surface = true
		receiver.contact_required_paths = [NodePath(".:visible")]
	for tick: int in range(12):
		for receiver: TileFluidWettable2D in [cached, reference]:
			receiver.visible = tick % 3 != 0
			var marker := Node2D.new()
			receiver.add_child(marker)
			marker.position = Vector2(tick, 0)
			receiver.contact_point = marker
			receiver.advance(1.0 / 120.0)
			marker.free()
		check(cached.contact_enabled == reference.contact_enabled)
		check(cached.surface_saturation == reference.surface_saturation)
		check(cached.saturation == reference.saturation)
	var viewport := SubViewport.new()
	viewport.world_2d = World2D.new()
	world.add_child(viewport)
	for receiver: TileFluidWettable2D in [cached, reference]:
		receiver.automatic_surface = false
		receiver.surface = surface
		receiver.reparent(viewport)
		receiver.advance(1.0 / 120.0)
	check(cached.surface_saturation == 0.0)
	check(cached.surface_saturation == reference.surface_saturation)
	check(cached.saturation == reference.saturation)
	world.get_node("Layer").reparent(viewport)
	for receiver: TileFluidWettable2D in [cached, reference]:
		receiver.advance(1.0 / 120.0)
	check(cached.surface_saturation == reference.surface_saturation)
	check(cached.saturation == reference.saturation)

func test_traction_matches_reference_after_runtime_edits() -> void:
	var world := _world()
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface")
	surface.traction_enabled = true
	surface.deposit(Vector2(16, 16), 0.8)
	var cached := TileFluidWettable2D.new()
	var reference := ReferenceWettable.new()
	for receiver: TileFluidWettable2D in [cached, reference]:
		world.add_child(receiver)
		receiver.set_physics_process(false)
		receiver.surface = surface
		receiver.position = Vector2(16, 16)
		var body := RigidBody2D.new()
		body.freeze = true
		world.add_child(body)
		receiver.traction_body = body
	for tick: int in range(60):
		surface.wet_drag_multiplier = (tick % 10) / 10.0
		surface.traction_affects_rotation = tick % 2 == 0
		for receiver: TileFluidWettable2D in [cached, reference]:
			receiver.traction_body.linear_damp = 4.0
			receiver.traction_body.angular_damp = 2.0
			receiver.contact_enabled = tick % 4 != 0
			receiver.advance(1.0 / 120.0)
		check(cached.traction_body.linear_damp == reference.traction_body.linear_damp)
		check(cached.traction_body.angular_damp == reference.traction_body.angular_damp)

class CustomGrid extends TileFluidGridSimulation:
	func sample(_point: Vector2) -> float:
		return 0.375

func test_stock_grid_prepares_and_custom_grid_overrides_keep_public_sampling() -> void:
	var world := _world()
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface")
	var handle := TileFluidPreparedContact.new()
	var point := Vector2(16, 16)
	_compare(surface, handle, point)
	check(handle.supported)
	check(handle.patch_id != 0)
	surface.simulation.set_script(CustomGrid)
	_compare(surface, handle, point)
	check(not handle.supported)
	check(surface._sample_contact(point, handle) == 0.375)
	surface.simulation.set_script(TileFluidGridSimulation)
	_compare(surface, handle, point)
	_compare(surface, handle, point)
	check(handle.supported)

func test_settings_edits_in_geometry_callback_are_seen_in_the_same_query() -> void:
	var world := _world()
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface")
	var handle := TileFluidPreparedContact.new()
	var point := Vector2(16, 16)
	surface.deposit(point, 0.8)
	_compare(surface, handle, point)
	var edit_settings := func(_cells: Array[Vector2i]) -> void:
		surface.settings.dry_seconds = -1.0
	surface.simulation.geometry_changed.connect(edit_settings)
	surface.invalidate()
	check(surface._sample_contact(point, handle) == 0.0)
	check(surface.saturation_at(point) == 0.0)
	surface.simulation.geometry_changed.disconnect(edit_settings)
	surface.settings.dry_seconds = 72.0
	_compare(surface, handle, point)

func test_resource_replacement_from_geometry_callback_revalidates_coverage() -> void:
	var world := _world()
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface")
	var handle := TileFluidPreparedContact.new()
	var point := Vector2(16, 16)
	surface.deposit(point, 0.8)
	_compare(surface, handle, point)
	var edits: Array[int] = []
	surface.simulation.geometry_changed.connect(func(_cells: Array[Vector2i]) -> void:
		edits.append(1)
		surface.settings = surface.settings.duplicate()
		surface.settings.receives_water_by_default = false, CONNECT_ONE_SHOT)
	surface.invalidate()
	check(surface._sample_contact(point, handle) == 0.0)
	check(surface.saturation_at(point) == 0.0)
	check(edits.size() == 1)

func test_validated_surface_invalidates_when_backend_is_reparented_or_deleted() -> void:
	var world := _world()
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface")
	var handle := TileFluidPreparedContact.new()
	var point := Vector2(16, 16)
	surface.deposit(point, 0.8)
	_compare(surface, handle, point)
	_compare(surface, handle, point)
	var grid: TileFluidGridSimulation = surface.simulation
	grid.reparent(world)
	_compare(surface, handle, point)
	check(surface._sample_contact(point, handle) == 0.0)
	grid.reparent(surface)
	_compare(surface, handle, point)
	check(surface._sample_contact(point, handle) > 0.0)
	grid.free()
	_compare(surface, handle, point)
	check(surface._sample_contact(point, handle) == 0.0)

func test_handles_do_not_retain_replaced_geometry() -> void:
	var world := _world()
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface")
	var grid: TileFluidGridSimulation = surface.simulation
	var handle := TileFluidPreparedContact.new()
	var point := Vector2(16, 16)
	_compare(surface, handle, point)
	_compare(surface, handle, point)
	var old_patch: TileFluidFieldPatch = grid.cell_patches(Vector2i.ZERO)[0]
	var old_geometry: WeakRef = weakref(old_patch)
	old_patch = null
	grid.reset(surface.settings)
	check(old_geometry.get_ref() == null, "A contact must not keep retired geometry alive")
	_compare(surface, handle, point)
	check(handle.corners.is_empty())
