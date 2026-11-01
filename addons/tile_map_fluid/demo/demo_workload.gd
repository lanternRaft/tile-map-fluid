extends Node2D
## Repeatable addon workload using the same cone-splash path as Grow Stuff's hose.

## Continuous hoses; increase to model simultaneous players watering.
@export_range(1, 4) var hose_count: int = 1
## Wettable solid objects clustered along the walking route, rather than offscreen.
@export_range(0, 256) var receiver_count: int = 64
## Repeated solid barriers exercise spray obstruction in the populated region.
@export_range(0, 16) var obstacle_count: int = 8
## Editable production-default hose profile, including splash spacing and radii.
@export var spray_settings: TileFluidSpraySettings = TileFluidSpraySettings.new()

var _sprays: Array[TileFluidSpray2D] = []
var _objects: Array[Node2D] = []


## Build outside the measured interval; keep runtime water on the shared demo surface.
func prepare(surface: TileFluidSurface2D, scope: Node2D,
		object_template: StaticBody2D, wall_template: StaticBody2D, center: Vector2) -> void:
	clear()
	for index: int in range(receiver_count):
		var body: StaticBody2D = object_template.duplicate() as StaticBody2D
		scope.add_child(body)
		body.global_position = center + Vector2(index % 8 - 3.5, index / 8 - 3.5) * 128.0
		for child: Node in body.get_children():
			if child is TileFluidWettable2D:
				child.surface = surface
				child.obstacle_body = body
		_objects.append(body)
	for index: int in range(obstacle_count):
		var wall: StaticBody2D = wall_template.duplicate() as StaticBody2D
		scope.add_child(wall)
		wall.global_position = center + Vector2.from_angle(index * TAU / obstacle_count) * 650.0
		_objects.append(wall)
	for index: int in range(hose_count):
		var spray: TileFluidSpray2D = TileFluidSpray2D.new()
		spray.surface = surface
		spray.receiver_scope = scope
		spray.settings = spray_settings.duplicate()
		spray.set_physics_process(false)
		add_child(spray)
		spray.active = true
		_sprays.append(spray)


## Emit once per fixed tick, with separate directions for simultaneous hoses.
func advance(delta: float, origin: Vector2, angle: float) -> void:
	for index: int in range(_sprays.size()):
		var spray: TileFluidSpray2D = _sprays[index]
		spray.global_position = origin
		spray.global_rotation = angle + index * TAU / _sprays.size()
		spray.advance(delta)


## Detach immediately so restarting a test cannot retain old physics obstacles.
func clear() -> void:
	for object: Node2D in _objects:
		object.get_parent().remove_child(object)
		object.queue_free()
	_objects.clear()
	for spray: TileFluidSpray2D in _sprays:
		remove_child(spray)
		spray.queue_free()
	_sprays.clear()
