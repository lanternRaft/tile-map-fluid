extends CharacterBody2D
## Demo-only movement host. Wetness does not impose controls or a traction policy.

## Independent receiver; use L to toggle floor contact while keeping direct hits enabled.
@export var receiver: Wettable2D
## Visual lift leaves the world sorting anchor on the ground.
@export var artwork: Node2D
## Dry movement speed in world pixels/second. Wet ground reduces acceleration and braking.
@export_range(20.0, 400.0, 10.0) var move_speed: float = 180.0
## Keeps the receiver inside the authored demonstration floor.
@export var movement_bounds: Rect2 = Rect2(84, 148, 728, 344)


func _physics_process(delta: float) -> void:
	var direction: Vector2 = Vector2(
		float(_held(KEY_D, KEY_RIGHT)) - float(_held(KEY_A, KEY_LEFT)),
		float(_held(KEY_S, KEY_DOWN)) - float(_held(KEY_W, KEY_UP)))
	var wetness: float = receiver.surface.saturation_at(global_position) \
		if is_instance_valid(receiver.surface) and receiver.contact_enabled else 0.0
	var traction: float = lerpf(1600.0, 100.0, wetness)
	velocity = velocity.move_toward(direction.normalized() * move_speed, traction * delta)
	move_and_slide()
	for index: int in range(get_slide_collision_count()):
		var collision: KinematicCollision2D = get_slide_collision(index)
		var body: RigidBody2D = collision.get_collider() as RigidBody2D
		if body != null:
			body.apply_central_impulse(-collision.get_normal() * 180.0 * delta)
	global_position = global_position.clamp(movement_bounds.position, movement_bounds.end)


func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_L:
		receiver.set_contact_enabled(not receiver.contact_enabled)
		artwork.position.y = 0.0 if receiver.contact_enabled else -24.0


func _held(letter: Key, arrow: Key) -> bool:
	return Input.is_physical_key_pressed(letter) or Input.is_physical_key_pressed(arrow)
