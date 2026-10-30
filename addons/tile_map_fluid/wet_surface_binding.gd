class_name WetSurfaceBinding
extends RefCounted
## Signal wiring, separate from public water operations.

var _layer: TileMapLayer
var _simulation: WetSurfaceSimulation


## Rebind changed dependencies and report whether the coverage snapshot is stale.
func synchronize(surface: WetSurface2D) -> bool:
	if _layer != surface.tile_layer or _simulation != surface.simulation:
		disconnect_from(surface)
		_layer = surface.tile_layer
		_simulation = surface.simulation
		if is_instance_valid(_layer):
			_layer.changed.connect(surface.invalidate)
		if is_instance_valid(_simulation):
			_simulation.changed.connect(surface.notify_changed)
		return true
	return false


## Release signal ownership before replacing dependencies or leaving the scene tree.
func disconnect_from(surface: WetSurface2D) -> void:
	if is_instance_valid(_layer) and _layer.changed.is_connected(surface.invalidate):
		_layer.changed.disconnect(surface.invalidate)
	if is_instance_valid(_simulation) and _simulation.changed.is_connected(surface.notify_changed):
		_simulation.changed.disconnect(surface.notify_changed)
	_layer = null
	_simulation = null
