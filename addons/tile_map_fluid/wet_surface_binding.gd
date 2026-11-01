class_name TileFluidSurfaceBinding
extends RefCounted
## Signal wiring, separate from public water operations.

var _layer: TileMapLayer
var _settings_revision: int = -1
var _settings: TileFluidSurfaceSettings
var _simulation: TileFluidSurfaceSimulation


## Rebind changed dependencies and report whether the coverage snapshot is stale.
func synchronize(surface: TileFluidSurface2D) -> bool:
	if _layer != surface.tile_layer or _simulation != surface.simulation \
			or _settings != surface.settings:
		disconnect_from(surface)
		_settings = surface.settings
		_settings_revision = _settings.geometry_revision if _settings != null else -1
		if _settings != null:
			_settings.changed.connect(surface._settings_changed)
		_layer = surface.tile_layer
		_simulation = surface.simulation
		if is_instance_valid(_layer):
			_layer.changed.connect(surface.invalidate)
			_layer.tree_exiting.connect(surface._invalidate_sampling)
		if is_instance_valid(_simulation):
			_simulation.changed.connect(surface.notify_changed)
			_simulation.script_changed.connect(surface.invalidate)
			_simulation.tree_exiting.connect(surface._invalidate_sampling)
		return true
	return false


## Resource setters publish revisions synchronously; ordinary queries need no revision polling.
func settings_changed(surface: TileFluidSurface2D) -> void:
	if _settings != null and _settings_revision != _settings.geometry_revision:
		_settings_revision = _settings.geometry_revision
		surface.invalidate()


## Release signal ownership before replacing dependencies or leaving the scene tree.
func disconnect_from(surface: TileFluidSurface2D) -> void:
	if is_instance_valid(_layer) and _layer.changed.is_connected(surface.invalidate):
		_layer.changed.disconnect(surface.invalidate)
	if is_instance_valid(_simulation) and _simulation.changed.is_connected(surface.notify_changed):
		_simulation.changed.disconnect(surface.notify_changed)
	if _settings != null and _settings.changed.is_connected(surface._settings_changed):
		_settings.changed.disconnect(surface._settings_changed)
	if is_instance_valid(_simulation) and _simulation.script_changed.is_connected(surface.invalidate):
		_simulation.script_changed.disconnect(surface.invalidate)
	if is_instance_valid(_layer) and _layer.tree_exiting.is_connected(surface._invalidate_sampling):
		_layer.tree_exiting.disconnect(surface._invalidate_sampling)
	if is_instance_valid(_simulation) and _simulation.tree_exiting.is_connected(surface._invalidate_sampling):
		_simulation.tree_exiting.disconnect(surface._invalidate_sampling)
	_settings = null
	_layer = null
	_simulation = null
