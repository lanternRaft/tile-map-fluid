@icon("res://addons/tile_map_fluid/assets/icons/presentation.svg")
class_name WettableTint2D
extends Node2D
## Optional dedicated artwork wrapper. Other effects belong on parents or children of this node.
## Owns only this wrapper's modulate; shared materials and descendant colors stay untouched.

## Signal-only Wettable2D remains useful without this optional wrapper.
@export var receiver: Wettable2D
## Multiplier at full saturation, blended from the wrapper's authored modulate.
@export var wet_multiplier: Color = Color(0.68, 0.78, 0.84, 1.0)

var _authored: Color = Color.WHITE
var _bound: Wettable2D


func _enter_tree() -> void:
	_authored = modulate


func _ready() -> void:
	refresh()


func _process(_delta: float) -> void:
	# Also handle live reassignment/removal of an exported receiver.
	if receiver != _bound or not is_instance_valid(receiver):
		refresh()


func _exit_tree() -> void:
	_disconnect()
	modulate = _authored


## Rebind after configuration changes; the dry state restores the authored appearance exactly.
func refresh() -> void:
	if receiver != _bound:
		_disconnect()
		_bound = receiver
		if is_instance_valid(_bound):
			_bound.changed.connect(_apply)
	_apply(_bound.saturation if is_instance_valid(_bound) else 0.0)


func _apply(saturation: float) -> void:
	modulate = _authored * Color.WHITE.lerp(wet_multiplier, saturation)


func _disconnect() -> void:
	if is_instance_valid(_bound) and _bound.changed.is_connected(_apply):
		_bound.changed.disconnect(_apply)
	_bound = null
