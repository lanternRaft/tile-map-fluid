extends "res://tests/test_case.gd"

const Fixture: PackedScene = preload("res://tests/fixtures/wetness_simulation.tscn")


## Enlarging a landing wets more floor without multiplying the dose to an object inside it.
func test_footprint_area_does_not_multiply_receiver_or_floor_dose() -> void:
	for radius: float in [2.0, 80.0]:
		var world: Node2D = track(Fixture.instantiate()) as Node2D
		add_child(world)
		var emitter: WaterEmitter2D = world.get_node("Emitter") as WaterEmitter2D
		var receiver: Wettable2D = world.get_node("Receiver") as Wettable2D
		var circle: CollisionShape2D = emitter.footprint.get_node("Circle") as CollisionShape2D
		var shape: CircleShape2D = circle.shape.duplicate() as CircleShape2D
		shape.radius = radius
		circle.shape = shape
		(emitter.footprint.get_node("Rectangle") as CollisionShape2D).disabled = true
		var doses: Array[float] = []
		receiver.water_added.connect(func(dose: float) -> void: doses.append(dose))
		check(emitter.emit_dose(0.25))
		check((doses) == ([0.25]))
		check(absf((receiver.saturation) - (0.25)) <=  0.0001)
		check(absf((emitter.surface.saturation_at(receiver.global_position)) - (0.25)) <=  0.0001)


## Signal consumers distinguish a valid dose from a state change, including at saturation.
func test_signal_only_receiver_reports_doses_and_actual_state_changes() -> void:
	var receiver: Wettable2D = track(Wettable2D.new()) as Wettable2D
	receiver.settings.dry_seconds = 2.0
	var doses: Array[float] = []
	var changes: Array[float] = []
	var contacts: Array[bool] = []
	receiver.water_added.connect(func(dose: float) -> void: doses.append(dose))
	receiver.changed.connect(func(value: float) -> void: changes.append(value))
	receiver.contact_changed.connect(func(enabled: bool) -> void: contacts.append(enabled))
	receiver.set_contact_enabled(false)
	receiver.set_contact_enabled(false)
	check(receiver.add_water(2.0))
	check(receiver.add_water(0.25))
	for invalid: float in [NAN, INF, -1.0, 0.0]:
		check(not (receiver.add_water(invalid)))
	receiver.advance(1.0)
	receiver.advance(1.0)
	receiver.advance(1.0)
	check((doses) == ([2.0, 0.25]))
	check((changes) == ([1.0, 0.5, 0.0]))
	check((contacts) == ([false]))


## Equal elapsed drying time gives equal floor/object results across host clock partitions.
func test_evaporation_is_partition_invariant_and_does_not_edit_shared_tile_data() -> void:
	for steps: int in [1, 120]:
		var world: Node2D = track(Fixture.instantiate()) as Node2D
		add_child(world)
		var surface: WetSurface2D = world.get_node("Layer/Surface") as WetSurface2D
		var receiver: Wettable2D = world.get_node("Receiver") as Wettable2D
		var tile: TileData = surface.tile_layer.get_cell_tile_data(Vector2i.ZERO)
		var authored_color: Color = tile.modulate
		receiver.settings.dry_seconds = 2.0
		receiver.set_contact_enabled(false)
		surface.deposit(receiver.global_position, 1.0)
		receiver.add_water(1.0)
		for tick: int in range(steps):
			surface.simulation.advance(1.0 / float(steps), 2.0)
			receiver.advance(1.0 / float(steps))
		check(absf((surface.saturation_at(receiver.global_position)) - (0.5)) <=  0.0001)
		check(absf((receiver.saturation) - (0.5)) <=  0.0001)
		check(tile.modulate.is_equal_approx(authored_color))
