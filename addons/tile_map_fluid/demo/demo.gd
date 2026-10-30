extends Node2D
## Standalone hose demo; host controls and effects stay outside the reusable water components.

@export var emitter: WaterEmitter2D
@export var footprint: WaterFootprint2D
@export var receiver: Wettable2D
@export var status: Label
@export var aim_bounds: Rect2 = Rect2(64, 128, 768, 384)

const FLIGHT_SECONDS: float = 0.32
const HOSE_RANGE: float = 144.0
var mushroom: Wettable2D
var crate: Wettable2D
var sprayer: Node2D
var droplets: Array[Dictionary] = []
var effect: Node2D
var performance_active: bool = false
var elapsed: float = 0.0
var frames: int = 0
var worst_frame: float = 0.0
var spawn_accumulator: float = 0.0
var dry_seconds: float


func _ready() -> void:
	emitter.set_active(false)
	emitter.source_bodies.assign([$Receiver])
	dry_seconds = emitter.surface.settings.dry_seconds
	# Keep shared settings resources untouched by the demo's benchmark toggle.
	emitter.surface.settings = emitter.surface.settings.duplicate()
	_make_mushroom()
	_make_crate()
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


func _make_mushroom() -> void:
	var host := StaticBody2D.new()
	host.name = "Mushroom"
	host.position = Vector2(620, 332)
	var body_shape := CollisionShape2D.new()
	var body_rectangle := RectangleShape2D.new()
	body_rectangle.size = Vector2(28, 20)
	body_shape.shape = body_rectangle
	host.set_meta(&"water_underpaint", true)
	host.add_child(body_shape)
	add_child(host)
	var sprite := Sprite2D.new()
	sprite.texture = load("res://addons/tile_map_fluid/demo/mushroom.svg")
	sprite.position.y = -28.0
	host.add_child(sprite)
	mushroom = Wettable2D.new()
	mushroom.surface = emitter.surface
	mushroom.obstacle_body = host
	mushroom.settings.dry_seconds = 7.0
	mushroom.artwork = sprite
	mushroom.collision_layer = 4
	mushroom.collision_mask = 0
	var shape := CollisionShape2D.new()
	var circle := CircleShape2D.new()
	circle.radius = 24.0
	shape.shape = circle
	mushroom.add_child(shape)
	host.add_child(mushroom)
	emitter.receivers.append(mushroom)


func _make_crate() -> void:
	var body := RigidBody2D.new()
	body.name = "PushableCrate"
	body.set_meta(&"water_underpaint", true)
	body.position = Vector2(380, 300)
	body.gravity_scale = 0.0
	body.mass = 0.65
	body.linear_damp = 5.0
	body.angular_damp = 5.0
	body.collision_layer = 1
	body.collision_mask = 3
	var collision := CollisionShape2D.new()
	var rectangle := RectangleShape2D.new()
	rectangle.size = Vector2(36, 36)
	collision.shape = rectangle
	body.add_child(collision)
	var art := Polygon2D.new()
	art.polygon = PackedVector2Array([Vector2(-18, -18), Vector2(18, -18),
		Vector2(18, 18), Vector2(-18, 18)])
	art.color = Color("bd824c")
	body.add_child(art)
	var brace := Line2D.new()
	brace.points = PackedVector2Array([Vector2(-15, -15), Vector2(15, 15),
		Vector2(15, -15), Vector2(-15, 15), Vector2(-15, -15)])
	brace.width = 3.0
	brace.default_color = Color("ffe0a0")
	art.add_child(brace)
	crate = Wettable2D.new()
	crate.surface = emitter.surface
	crate.obstacle_body = body
	crate.artwork = art
	crate.settings.dry_seconds = 7.0
	crate.collision_layer = 4
	crate.collision_mask = 0
	body.add_child(crate)
	add_child(body)
	emitter.receivers.append(crate)


func _physics_process(delta: float) -> void:
	var hand: Vector2 = sprayer.global_position
	var direction: Vector2 = hand.direction_to(get_global_mouse_position())
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


func _process(delta: float) -> void:
	elapsed += delta
	frames += 1
	worst_frame = maxf(worst_frame, delta)
	status.text = "Floor at character: %d%%    Character: %d%%    Mushroom: %d%%    Crate: %d%%    Contact: %s" % [
		roundi(emitter.surface.saturation_at(receiver.global_position) * 100.0),
		roundi(receiver.saturation * 100.0), roundi(mushroom.saturation * 100.0), roundi(crate.saturation * 100.0),
		"grounded" if receiver.contact_enabled else "lifted"]
	$Instructions/FPS.text = "FPS: %d    Frame: %.2f ms    %s average: %.1f FPS    Worst: %.2f ms    Draw calls: %d" % [
		Engine.get_frames_per_second(), delta * 1000.0,
		"All-wet" if performance_active else "Session", frames / maxf(elapsed, 0.001),
		worst_frame * 1000.0, Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)]


func _toggle_performance(enabled: bool) -> void:
	performance_active = enabled
	for object: Wettable2D in [receiver, mushroom, crate]:
		object.settings.dry_seconds = 0.0 if enabled else 7.0
	emitter.surface.settings.dry_seconds = 0.0 if enabled else dry_seconds
	$Instructions/Performance.text = "Stop all-wet test" if enabled else "Performance test · all wet"
	if enabled:
		var area := WaterFootprint2D.new()
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
