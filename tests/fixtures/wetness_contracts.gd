extends Node2D
## Minimal stock-physics composition; two surfaces intentionally share TileSet and settings.


func _enter_tree() -> void:
	for layer: TileMapLayer in [$Layer, $OtherLayer]:
		layer.set_cell(Vector2i.ZERO, 0, Vector2i.ZERO)
		layer.set_cell(Vector2i(1, 0), 0, Vector2i.ZERO)


func _ready() -> void:
	# Tests advance time explicitly; Area overlap detection still runs in the physics server.
	for node: Node in [$Layer/Surface, $OtherLayer/Surface, $Receiver, $OtherReceiver, $Emitter]:
		node.set_physics_process(false)
