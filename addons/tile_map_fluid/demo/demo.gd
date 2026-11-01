extends Node2D
## Standalone hose demo; host controls and effects stay outside the reusable water components.

@export var emitter: TileFluidEmitter2D
@export var footprint: TileFluidFootprint2D
@export var receiver: TileFluidWettable2D
@export var status: Label
@export var aim_bounds: Rect2 = Rect2(64, 128, 768, 384)
## Game-equivalent spray workload; node owns the populated benchmark region.
@export var workload: Node2D

const FLIGHT_SECONDS: float = 0.32
const HOSE_RANGE: float = 144.0
var mushroom: TileFluidWettable2D
var crate: TileFluidWettable2D
var sprayer: Node2D
var droplets: Array[Dictionary] = []
var effect: Node2D
var performance_active: bool = false
var elapsed: float = 0.0
var frames: int = 0
var worst_frame: float = 0.0
var spawn_accumulator: float = 0.0
var stress_active: bool = false
var route_time: float = 0.0
var camera: Camera2D
var original_tiles: PackedByteArray
var saved_time_scale: float
var saved_ticks: int
var saved_steps: int
var saved_fps: int
var saved_vsync: int
var sample_start: int
var previous_frame_usec: int = 0
var sample_frames: int = 0
var sample_ticks: int = 0
var slow_frames: int = 0
var sample_worst_ms: float = 0.0
var stress_report: String = ""
var dry_seconds: float
var session_previous_usec: int = 0


func _ready() -> void:
	original_tiles = $Floor.tile_map_data
	saved_time_scale = Engine.time_scale
	saved_ticks = Engine.physics_ticks_per_second
	saved_steps = Engine.max_physics_steps_per_frame
	saved_fps = Engine.max_fps
	saved_vsync = DisplayServer.window_get_vsync_mode()
	emitter.set_active(false)
	emitter.source_bodies.assign([$Receiver])
	dry_seconds = emitter.surface.settings.dry_seconds
	# Keep shared settings resources untouched by the demo's benchmark toggle.
	emitter.surface.settings = emitter.surface.settings.duplicate()
	$Props._make_mushroom()
	$Props._make_crate()
	mushroom = $Props.mushroom
	crate = $Props.crate
	sprayer = Node2D.new()
	$Receiver/Artwork.add_child(sprayer)
	sprayer.position = Vector2(0, -20)
	var tank := Polygon2D.new()
	tank.polygon = PackedVector2Array([Vector2(8, -5), Vector2(24, -5),
		Vector2(24, 5), Vector2(8, 5)])
	tank.color = Color("387c77")
	sprayer.add_child(tank)
	var nozzle := Polygon2D.new()
	nozzle.polygon = PackedVector2Array([Vector2(20, -3), Vector2(34, -3),
		Vector2(34, 3), Vector2(20, 3)])
	nozzle.color = Color("e6b86d")
	sprayer.add_child(nozzle)
	effect = Node2D.new()
	effect.z_index = 2
	add_child(effect)
	effect.draw.connect(_draw_droplets)
	$Instructions/Performance.toggled.connect(_toggle_performance)
	$Instructions/Stress.toggled.connect(_toggle_stress)
	$Instructions/Speed.item_selected.connect(_select_speed)
	if OS.get_cmdline_user_args().has("--stress"):
		$Instructions/Stress.set_pressed(true)


func _physics_process(delta: float) -> void:
	if stress_active:
		sample_ticks += 1
		route_time += delta
		var target := aim_bounds.get_center() + Vector2(
			sin(route_time * 0.18) * 450.0, sin(route_time * 0.36) * 450.0)
		$Receiver.automatic_direction = $Receiver.global_position.direction_to(target)
	var hand: Vector2 = sprayer.global_position
	var direction: Vector2 = hand.direction_to(get_global_mouse_position())
	if stress_active:
		direction = Vector2.from_angle(route_time * 1.7)
		workload.advance(delta, $Receiver.global_position, direction.angle())
	if direction.is_zero_approx():
		direction = Vector2.RIGHT
	sprayer.global_rotation = direction.angle()
	var origin: Vector2 = hand + direction * 34.0
	var landing: Vector2 = ($Receiver.global_position + direction * HOSE_RANGE).clamp(
		aim_bounds.position, aim_bounds.end)
	# Stop both the visible stream and its deposit at the first wall.
	var query := PhysicsRayQueryParameters2D.create(hand, landing, 1,
		[$Receiver.get_rid()])
	var hit: Dictionary = get_world_2d().direct_space_state.intersect_ray(query)
	if not hit.is_empty():
		landing = hit.position - direction * 3.0
	emitter.global_position = hand
	footprint.global_position = landing
	var spraying: bool = Input.is_physical_key_pressed(KEY_SPACE) or (
		Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		and get_viewport().gui_get_hovered_control() == null)
	spraying = spraying or stress_active
	spawn_accumulator += delta if spraying else 0.0
	while spawn_accumulator >= 1.0 / 90.0:
		spawn_accumulator -= 1.0 / 90.0
		droplets.append({"start": origin, "end": landing + Vector2(
			randf_range(-9, 9), randf_range(-6, 6)), "age": 0.0,
			"source": hand, "landed": false})
	for index: int in range(droplets.size() - 1, -1, -1):
		var drop: Dictionary = droplets[index]
		drop.age += delta
		if drop.age >= FLIGHT_SECONDS and not drop.landed:
			drop.landed = true
			# Water arrives with the particles, including after the trigger is released.
			emitter.global_position = drop.source
			footprint.global_position = drop.end
			if not stress_active:
				emitter.emit_dose(0.8 / 90.0)
		if drop.age > FLIGHT_SECONDS + 0.16:
			droplets.remove_at(index)
	emitter.global_position = hand
	footprint.global_position = landing
	effect.queue_redraw()


func _draw_droplets() -> void:
	for drop: Dictionary in droplets:
		var t: float = minf(drop.age / FLIGHT_SECONDS, 1.0)
		var point: Vector2 = drop.start.lerp(drop.end, t)
		point.y -= sin(t * PI) * 25.0
		if drop.landed:
			var fade: float = 1.0 - (drop.age - FLIGHT_SECONDS) / 0.16
			effect.draw_arc(point, 3.0 + (1.0 - fade) * 6.0, 0, TAU, 10,
				Color(0.65, 0.93, 1.0, fade), 1.0)
		else:
			effect.draw_circle(point, 2.0, Color(0.65, 0.93, 1.0, 0.85))


func _process(_delta: float) -> void:
	$StressController.update_hud()


func _toggle_performance(enabled: bool) -> void:
	performance_active = enabled
	for object: TileFluidWettable2D in [receiver, mushroom, crate]:
		object.settings.dry_seconds = 0.0 if enabled else 7.0
	emitter.surface.settings.dry_seconds = 0.0 if enabled else dry_seconds
	$Instructions/Performance.text = "Stop all-wet preview" if enabled else "All-wet render preview"
	if enabled:
		var area := TileFluidFootprint2D.new()
		var collision := CollisionShape2D.new()
		var rectangle := RectangleShape2D.new()
		rectangle.size = aim_bounds.size + Vector2(64, 64)
		collision.shape = rectangle
		area.add_child(collision)
		area.collision_layer = 0
		area.collision_mask = 0
		add_child(area)
		area.global_position = aim_bounds.get_center()
		emitter.surface.stamp(area, 1.0, aim_bounds.get_center(), 0)
		area.queue_free()
		receiver.add_water(1.0)
		mushroom.add_water(1.0)
		crate.add_water(1.0)
	# Exclude the setup stamp from the sustained rendering measurement.
	elapsed = 0.0
	frames = 0
	worst_frame = 0.0
	session_previous_usec = 0


func _select_speed(index: int) -> void:
	$StressController._select_speed(index)


func _toggle_stress(enabled: bool) -> void:
	$StressController._toggle_stress(enabled)


func _sample_stress() -> void:
	$StressController._sample_stress()
