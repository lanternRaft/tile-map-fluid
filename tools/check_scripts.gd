extends SceneTree
## Compile addon, tests and tools with enabled warnings promoted to errors, without changing settings.

var _failed: int = 0
var _checked: int = 0


func _initialize() -> void:
	for property: Dictionary in ProjectSettings.get_property_list():
		var setting: String = property.name
		if setting.begins_with("debug/gdscript/warnings/"):
			var value: Variant = ProjectSettings.get_setting(setting)
			if typeof(value) == TYPE_INT and value == 1:
				ProjectSettings.set_setting(setting, 2)
	ProjectSettings.settings_changed.emit()
	for directory: String in ["res://addons", "res://tests", "res://tools"]:
		_check(directory)
	print("TileMapFluid compiler: %d checked, %d failed" % [_checked, _failed])
	quit(1 if _failed else 0)


func _check(directory: String) -> void:
	for filename: String in DirAccess.get_files_at(directory):
		var path: String = directory.path_join(filename)
		# Reloading an executing GDScript invalidates its active bytecode.
		if not filename.ends_with(".gd") or path == (get_script() as Script).resource_path:
			continue
		_checked += 1
		var script: GDScript = ResourceLoader.load(path, "GDScript",
			ResourceLoader.CACHE_MODE_IGNORE) as GDScript
		if script == null or not script.can_instantiate():
			_failed += 1
	for child: String in DirAccess.get_directories_at(directory):
		_check(directory.path_join(child))
