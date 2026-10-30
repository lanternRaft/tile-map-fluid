extends RefCounted
## Identical small landings, broad splashes and wall contacts expose footprint/grid limits.

const Room = preload("res://addons/tile_map_fluid/benchmarks/room.gd")
const Capture = preload("res://addons/tile_map_fluid/benchmarks/capture.gd")


## Profiles use world pixels, without production traction tuning or resolution changes.
static func run(room: Room, output: String) -> Dictionary:
	room.show_receivers(false)
	var spacing: int = roundi(room.surface.settings.sample_spacing)
	var result: Dictionary = { "spacing": spacing, "cases": [] }
	var grid: WetGridSimulation = room.surface.simulation as WetGridSimulation
	var original_radius: float = room.circle.radius
	for radius: float in [3.0, 12.0, 22.0, 32.0]:
		room.prepare("dry_idle")
		room.circle.radius = radius
		# Off-lattice landings expose tiny-footprint expansion instead of hiding it at tile centers.
		room.footprint.global_position = Vector2(371, 289)
		room.surface.stamp(room.footprint, 1.0, room.footprint.global_position, 1)
		var profile: Array[float] = []
		for x: int in range(300, 441):
			profile.append(room.surface.saturation_at(Vector2(x, 289)))
		var row: Dictionary = { "kind": "circle_union", "radius": radius,
			"profile_x_start": 300, "profile_y": 289, "saturation": profile }
		result.cases.append(row)
		room.status.text = "%s px · circle radius %s · identical dose 1" % [result.spacing, radius]
		room.presentation.refresh()
		await room.get_tree().process_frame
		await Capture.viewport(room.get_viewport(), "%dpx-circle-%d" % [spacing, roundi(radius)],
			output.path_join("captures"))
	room.circle.radius = original_radius
	room.prepare("dry_idle")
	grid.splash(room.layer.to_local(Vector2(371, 289)), 1.0, 32.0, 1)
	room.presentation.refresh()
	room.status.text = "%s px · game soft splash radius 32" % result.spacing
	await room.get_tree().process_frame
	await Capture.viewport(room.get_viewport(), "%dpx-soft-splash" % spacing,
		output.path_join("captures"))
	var soft_profile: Array[float] = []
	for x: int in range(300, 441):
		soft_profile.append(room.surface.saturation_at(Vector2(x, 289)))
	result.cases.append({ "kind": "soft_splash", "radius": 32,
		"profile_x_start": 300, "profile_y": 289, "saturation": soft_profile })
	room.prepare("dry_idle")
	room.circle.radius = 48.0
	room.footprint.global_position = Vector2(650, 320)
	room.surface.stamp(room.footprint, 1.0, Vector2(590, 320), 1)
	room.presentation.refresh()
	room.status.text = "%s px · spray crosses angled wall · source on left" % result.spacing
	var blocked: float = room.surface.saturation_at(Vector2(672, 320))
	result.wall_shadow_saturation = blocked
	result.hole_saturation = room.surface.saturation_at(Vector2(280, 250))
	await room.get_tree().process_frame
	await Capture.viewport(room.get_viewport(), "%dpx-wall" % spacing,
		output.path_join("captures"))
	room.circle.radius = original_radius
	return result
