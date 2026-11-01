extends Node2D
## Owns the demo's independent solid wettable props.

## Destination shared with the demo's water components.
@export var emitter: TileFluidEmitter2D
var mushroom: TileFluidWettable2D
var crate: TileFluidWettable2D


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
	get_parent().add_child(host)
	var sprite := Sprite2D.new()
	sprite.texture = load("res://addons/tile_map_fluid/demo/mushroom.svg")
	sprite.position.y = -28.0
	host.add_child(sprite)
	mushroom = TileFluidWettable2D.new()
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
	crate = TileFluidWettable2D.new()
	crate.surface = emitter.surface
	crate.obstacle_body = body
	crate.artwork = art
	crate.settings.dry_seconds = 7.0
	crate.collision_layer = 4
	crate.collision_mask = 0
	body.add_child(crate)
	get_parent().add_child(body)


