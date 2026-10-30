extends RefCounted
## Pixel comparisons use opaque overlap, avoiding antialiased edges and whole-image goldens.

const DIRECTORY: String = "res://reports/draw-order/images"


## Waits for the real renderer and returns a transparent viewport's current pixels.
static func capture(view: SubViewport) -> Image:
	# macOS can stop automatic draws for an occluded test window. Drive the real renderer
	# after scene changes settle rather than waiting forever for a frame that never starts.
	await view.get_tree().process_frame
	# process_frame precedes node _process; allow dynamic masks to consume the new scene state.
	await view.get_tree().process_frame
	RenderingServer.force_draw()
	return view.get_texture().get_image()


## Returns overlap coverage and mismatches; failure captures are uploaded with CI reports.
static func overlap(back: Image, front: Image, actual: Image, label: String) -> Dictionary:
	var result: Dictionary = { "checked": 0, "mismatches": 0 }
	for y: int in range(actual.get_height()):
		for x: int in range(actual.get_width()):
			if back.get_pixel(x, y).a < 0.05 or front.get_pixel(x, y).a < 0.9999:
				continue
			result.checked += 1
			var expected: Color = front.get_pixel(x, y)
			var observed: Color = actual.get_pixel(x, y)
			if maxf(absf(observed.r - expected.r), maxf(absf(observed.g - expected.g),
					absf(observed.b - expected.b))) > 0.015:
				result.mismatches += 1
	if result.mismatches > 0 or result.checked == 0:
		DirAccess.make_dir_recursive_absolute(DIRECTORY)
		back.save_png(DIRECTORY.path_join(label + "-back.png"))
		front.save_png(DIRECTORY.path_join(label + "-front.png"))
		actual.save_png(DIRECTORY.path_join(label + "-actual.png"))
	return result
