class_name WetSurfaceBinding
extends RefCounted
## Signal wiring and source poses, separate from public water operations.

var _layer: TileMapLayer
var _layers: Array[TileMapLayer] = []
var _poses: Array[Transform2D] = []
var _provider: WetCoverageProvider2D
var _simulation: WetSurfaceSimulation


## Rebind changed dependencies and report whether the coverage snapshot is stale.
func synchronize(surface: WetSurface2D) -> bool:
	var sources: Array[TileMapLayer] = surface.coverage_layers
	if sources.is_empty() and is_instance_valid(surface.tile_layer):
		sources = [surface.tile_layer]
	if _layer != surface.tile_layer or _layers != sources \
			or _provider != surface.coverage_provider or _simulation != surface.simulation:
		disconnect_from(surface)
		_layer = surface.tile_layer
		_layers = sources.duplicate()
		_provider = surface.coverage_provider
		_simulation = surface.simulation
		for layer: TileMapLayer in _layers:
			if is_instance_valid(layer) and not layer.changed.is_connected(surface.invalidate):
				layer.changed.connect(surface.invalidate)
		if is_instance_valid(_provider):
			_provider.coverage_changed.connect(surface.invalidate)
		if is_instance_valid(_simulation):
			_simulation.changed.connect(surface.notify_changed)
		return true
	return false


## Tile transforms affect composed coverage even without TileMapLayer.changed.
func poses_changed() -> bool:
	var poses: Array[Transform2D] = []
	for layer: TileMapLayer in _layers:
		if not is_instance_valid(layer):
			return true
		poses.append(layer.global_transform)
	if is_instance_valid(_provider):
		poses.append(_provider.global_transform)
	if poses == _poses:
		return false
	_poses = poses
	return true


## Release signal ownership before replacing dependencies or leaving the scene tree.
func disconnect_from(surface: WetSurface2D) -> void:
	for layer: TileMapLayer in _layers:
		if is_instance_valid(layer) and layer.changed.is_connected(surface.invalidate):
			layer.changed.disconnect(surface.invalidate)
	if is_instance_valid(_provider) and _provider.coverage_changed.is_connected(surface.invalidate):
		_provider.coverage_changed.disconnect(surface.invalidate)
	if is_instance_valid(_simulation) and _simulation.changed.is_connected(surface.notify_changed):
		_simulation.changed.disconnect(surface.notify_changed)
	_layers.clear()
	_poses.clear()
	_layer = null
	_provider = null
	_simulation = null
