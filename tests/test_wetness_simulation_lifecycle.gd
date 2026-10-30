extends "res://tests/test_case.gd"

const Fixture: PackedScene = preload("res://tests/fixtures/wetness_simulation.tscn")

var _previous_scale: float = 1.0


func before_test() -> void:
	_previous_scale = Engine.time_scale


func after_test() -> void:
	get_tree().paused = false
	Engine.time_scale = _previous_scale


## Automatic processing uses scaled physics time and inherits the host's pause state.
func test_scaled_physics_and_pause_stop_all_simulation() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	world.process_mode = Node.PROCESS_MODE_PAUSABLE
	var emitter: WaterEmitter2D = world.get_node("Emitter") as WaterEmitter2D
	var receiver: Wettable2D = world.get_node("Receiver") as Wettable2D
	var surface: WetSurface2D = emitter.surface
	emitter.settings.rate = 0.4
	emitter.set_active(true)
	emitter.set_physics_process(true)
	var doses: Array[float] = []
	emitter.emitted.connect(func(dose: float) -> void: doses.append(dose))
	Engine.time_scale = 0.5
	for frame: int in range(3):
		await get_tree().physics_frame
	check(absf((doses.back()) - (0.2 / Engine.physics_ticks_per_second)) <=  0.00001)
	Engine.time_scale = 2.0
	for frame: int in range(3):
		await get_tree().physics_frame
	check(absf((doses.back()) - (0.8 / Engine.physics_ticks_per_second)) <=  0.00001)
	surface.settings = surface.settings.duplicate() as WetSurfaceSettings
	surface.settings.dry_seconds = 1.0
	surface.set_physics_process(true)
	receiver.set_contact_enabled(false)
	receiver.set_physics_process(true)
	receiver.settings.dry_seconds = 1.0
	surface.deposit(Vector2(16, 16), 0.8)
	receiver.add_water(0.6)
	get_tree().paused = true
	var floor_before: float = surface.saturation_at(Vector2(16, 16))
	var object_before: float = receiver.saturation
	var count: int = doses.size()
	await frames(3)
	check((doses.size()) == (count))
	check((surface.saturation_at(Vector2(16, 16))) == (floor_before))
	check((receiver.saturation) == (object_before))
	emitter.set_active(false)
	get_tree().paused = false
	for frame: int in range(3):
		await get_tree().physics_frame
	check((doses.size()) == (count))
	check((surface.saturation_at(Vector2(16, 16))) < (floor_before))
	check((receiver.saturation) < (object_before))


## Leaving the tree disconnects dependencies; reentry binds once, and freed dependencies fail closed.
func test_removal_reentry_and_freed_dependencies() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var surface: WetSurface2D = world.get_node("Layer/Surface") as WetSurface2D
	var layer: TileMapLayer = surface.tile_layer
	var notifications: Array[Rect2] = []
	surface.coverage_changed.connect(func(area: Rect2) -> void: notifications.append(area))
	layer.changed.emit()
	check((notifications.size()) == (1))
	layer.remove_child(surface)
	layer.changed.emit()
	check((notifications.size()) == (1))
	layer.add_child(surface)
	layer.changed.emit()
	check((notifications.size()) == (2))
	surface.simulation.free()
	check((surface.validation_error()).contains("Simulation child"))
	check(not (surface.deposit(Vector2(16, 16), 1.0)))
	var emitter: WaterEmitter2D = world.get_node("Emitter") as WaterEmitter2D
	emitter.footprint.free()
	check(not (emitter.emit_dose(1.0)))
	layer.remove_child(surface)
	world.add_child(surface)
	layer.free()
	check((surface.validation_error()).contains("TileMapLayer"))


## Exported receiver/source lists can outlive individual bodies without invalid typed calls.
func test_freed_receiver_and_obstacle_references_are_safe() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var emitter: WaterEmitter2D = world.get_node("Emitter") as WaterEmitter2D
	var receiver: Wettable2D = world.get_node("Receiver") as Wettable2D
	var removed: Wettable2D = Wettable2D.new()
	world.add_child(removed)
	emitter.receivers.append(removed)
	removed.free()
	var body: StaticBody2D = StaticBody2D.new()
	world.add_child(body)
	emitter.source_bodies.append(body)
	receiver.obstacle_body = body
	body.free()
	check(emitter.emit_dose(0.4))
	check((receiver.saturation) == (0.4))
