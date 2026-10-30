extends "res://tests/test_case.gd"

const Fixture: PackedScene = preload("res://tests/fixtures/wetness_simulation.tscn")
const WallFixture: PackedScene = preload("res://tests/fixtures/wetness_simulation_wall.tscn")


## Rates mean saturation/second per contact/receiver, independent of time partition and density.
func test_rates_and_receiver_doses_are_invariant() -> void:
	for spacing: float in [32.0, 16.0, 8.0]:
		for steps: int in [30, 120]:
			var world: Node2D = track(Fixture.instantiate()) as Node2D
			add_child(world)
			var emitter: WaterEmitter2D = world.get_node("Emitter") as WaterEmitter2D
			var receiver: Wettable2D = world.get_node("Receiver") as Wettable2D
			emitter.surface.settings = emitter.surface.settings.duplicate() as WetSurfaceSettings
			emitter.surface.settings.sample_spacing = spacing
			emitter.surface.refresh_coverage()
			emitter.settings.rate = 0.4
			emitter.set_active(true)
			var doses: Array[float] = []
			receiver.water_added.connect(func(dose: float) -> void: doses.append(dose))
			for tick: int in range(steps):
				emitter.advance(1.0 / float(steps))
			emitter.set_active(false)
			emitter.advance(10.0)
			check((doses.size()) == (steps))
			check(absf((receiver.saturation) - (0.4)) <=  0.0001)
			check(absf(emitter.surface.saturation_at(receiver.global_position) - 0.4) <= 0.0001)


## Tiny circles, rectangles and cones between grid contacts can wet their actual floor patch.
func test_subcell_footprints_and_overlapping_shapes() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var emitter: WaterEmitter2D = world.get_node("Emitter") as WaterEmitter2D
	var circle: CollisionShape2D = emitter.footprint.get_node("Circle") as CollisionShape2D
	var rectangle: CollisionShape2D = emitter.footprint.get_node("Rectangle") as CollisionShape2D
	var circle_shape: CircleShape2D = circle.shape.duplicate() as CircleShape2D
	circle.shape = circle_shape
	circle_shape.radius = 1.0
	rectangle.disabled = true
	emitter.emit_dose(0.2)
	check(absf((emitter.surface.saturation_at(Vector2(16, 16))) - (0.2)) <=  0.0001)
	circle.disabled = true
	rectangle.disabled = false
	var rectangle_shape: RectangleShape2D = rectangle.shape.duplicate() as RectangleShape2D
	rectangle.shape = rectangle_shape
	rectangle_shape.size = Vector2(2, 2)
	emitter.emit_dose(0.2)
	check(absf((emitter.surface.saturation_at(Vector2(16, 16))) - (0.4)) <=  0.0001)
	var cone: CollisionPolygon2D = CollisionPolygon2D.new()
	cone.polygon = PackedVector2Array([Vector2(-1, -1), Vector2(2, 0), Vector2(-1, 1)])
	emitter.footprint.add_child(cone)
	emitter.emit_dose(0.2)
	check(absf((emitter.surface.saturation_at(Vector2(16, 16))) - (0.6)) <=  0.0001)
	var receiver: Wettable2D = world.get_node("Receiver") as Wettable2D
	check(absf((receiver.saturation) - (0.6)) <=  0.0001)


## A 2-pixel wall splits a cell; neither stamping nor bilinear interpolation crosses it.
func test_physics_wall_clipping_and_visibility() -> void:
	for pose: Transform2D in [Transform2D.IDENTITY,
			Transform2D(0.3, Vector2(2, 1.5), 0.0, Vector2(-200, 90))]:
		var world: Node2D = track(WallFixture.instantiate()) as Node2D
		world.transform = pose
		add_child(world)
		await get_tree().physics_frame
		await get_tree().physics_frame
		var emitter: WaterEmitter2D = world.get_node("Emitter") as WaterEmitter2D
		var receiver: Wettable2D = world.get_node("Receiver") as Wettable2D
		emitter.surface.refresh_coverage()
		emitter.position = Vector2(8, 16)
		receiver.position = Vector2(24, 16)
		check(WaterVisibility2D.reaches(world.get_world_2d(), emitter.global_position,
			world.to_global(Vector2(12, 16)), 1))
		check(not (WaterVisibility2D.reaches(world.get_world_2d(), emitter.global_position,
			world.to_global(Vector2(20, 16)), 1)))
		emitter.emit_dose(1.0)
		check(absf(emitter.surface.saturation_at(world.to_global(Vector2(8, 16))) - 1.0) <= 0.001)
		check((emitter.surface.saturation_at(world.to_global(Vector2(12, 16)))) > (0.0))
		check((emitter.surface.saturation_at(world.to_global(Vector2(15, 16)))) == (0.0))
		check((emitter.surface.saturation_at(world.to_global(Vector2(24, 16)))) == (0.0))
		check((receiver.saturation) == (0.0))


## Contact and direct markers are explicit; lifting stops absorption but not direct hits/drying.
func test_ground_contact_and_direct_hit_are_independent() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var emitter: WaterEmitter2D = world.get_node("Emitter") as WaterEmitter2D
	var receiver: Wettable2D = world.get_node("Receiver") as Wettable2D
	var contact: Marker2D = Marker2D.new()
	contact.position = Vector2(48, 16)
	world.add_child(contact)
	receiver.contact_point = contact
	receiver.settings.dry_seconds = 0.0
	receiver.settings.ground_absorption = 1.0
	emitter.surface.deposit(contact.position, 1.0)
	receiver.advance(0.5)
	check((receiver.saturation) == (0.5))
	receiver.set_contact_enabled(false)
	check((receiver.surface_saturation) == (0.0))
	emitter.emit_dose(0.25)
	check((receiver.saturation) == (0.75))
	receiver.settings.dry_seconds = 1.0
	receiver.advance(0.5)
	check((receiver.saturation) == (0.25))
	check((emitter.surface.saturation_at(contact.position)) == (1.0))
