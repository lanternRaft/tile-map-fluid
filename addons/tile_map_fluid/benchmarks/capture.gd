extends RefCounted
## Optional benchmark screenshots, independent of host tooling or third-party plugins.


## Wait for rendered pixels; headless runs retain numerical profiles without screenshots.
static func viewport(view: Viewport, stem: String, directory: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	await RenderingServer.frame_post_draw
	var image: Image = view.get_texture().get_image()
	var absolute: String = ProjectSettings.globalize_path(directory)
	DirAccess.make_dir_recursive_absolute(absolute)
	var ignore_file: FileAccess = FileAccess.open(absolute.path_join(".gdignore"), FileAccess.WRITE)
	if ignore_file != null:
		ignore_file.close()
	var error: Error = image.save_png(absolute.path_join(stem + ".png"))
	if error != OK:
		push_error("Cannot save wetness benchmark capture: " + error_string(error))
