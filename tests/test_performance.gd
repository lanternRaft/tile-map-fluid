extends "res://tests/test_case.gd"
## Exercise real workloads; retain timings and guard structural costs without machine-specific
## limits.

const RoomScene: PackedScene = preload("res://addons/tile_map_fluid/benchmarks/room.tscn")
const Settings = preload("res://addons/tile_map_fluid/benchmarks/settings.gd")
const Room = preload("res://addons/tile_map_fluid/benchmarks/room.gd")
const Metrics = preload("res://addons/tile_map_fluid/benchmarks/metrics.gd")
const Fixture: PackedScene = preload("res://tests/fixtures/wetness_simulation.tscn")


## Deposits, drying, contacts, geometry and uploads all run at each supported sample density.
func test_workload_timings_and_bounded_steady_storage() -> void:
	var rows: Array[Dictionary] = []
	for spacing: float in [32.0, 16.0, 8.0]:
		var settings: Settings = Settings.new()
		var room: Room = track(RoomScene.instantiate()) as Room
		room.configure(settings, spacing)
		add_child(room)
		await frames(2)
		check(room.surface.validation_error().is_empty())
		var grid: TileFluidGridSimulation = room.surface.simulation as TileFluidGridSimulation
		for workload: String in ["dry_idle", "moving_spray", "game_splash",
				"saturated_drying", "crowded_contacts", "geometry_updates"]:
			room.prepare(workload)
			# Warm initialization, lazy geometry and initial upload stay outside steady timings.
			room.step(workload, 0)
			var samples: int = grid.sample_count
			var revision: int = grid.geometry_revision
			var metrics: Metrics = Metrics.new()
			var ticks: int = 128 if workload == "geometry_updates" else 64
			for tick: int in range(1, ticks + 1):
				var started: int = Time.get_ticks_usec()
				var costs: Dictionary = room.step(workload, tick)
				metrics.record("work_total", Time.get_ticks_usec() - started)
				for key: String in costs:
					metrics.record(key, costs[key])
			var report: Dictionary = metrics.report()
			if workload == "geometry_updates":
				check(
					absi(grid.sample_count - samples) <= 64,
					"One tile edit has bounded storage cost",
				)
				check(grid.geometry_revision > revision, "Tile edit must update geometry")
				check(report.summary_us.geometry_event.n == 1)
			else:
				check(grid.sample_count == samples, workload + " grew contact storage")
				check(grid.geometry_revision == revision, workload + " rebuilt steady geometry")
			check(report.summary_us.work_total.n == ticks)
			check(is_finite(float(report.summary_us.work_total.p95)))
			rows.append({"spacing": spacing, "workload": workload,
				"counts": room.counts.duplicate(), "metrics": report})
		room.free()
	var directory: String = "res://reports/performance"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	var report_file: FileAccess = FileAccess.open(
		directory.path_join("tests.json"),
		FileAccess.WRITE,
	)
	check(report_file != null)
	if report_file != null:
		report_file.store_string(JSON.stringify({"engine": Engine.get_version_info(),
			"processor": OS.get_processor_name(), "display": DisplayServer.get_name(),
			"rows": rows}, "\t"))


## A fully dry field must skip work and notifications, including after its last puddle evaporates.
func test_dry_idle_skips_simulation_and_reuses_geometry() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var surface: TileFluidSurface2D = world.get_node("Layer/Surface") as TileFluidSurface2D
	var grid: TileFluidGridSimulation = surface.simulation as TileFluidGridSimulation
	var changes: Array[int] = []
	grid.changed.connect(func() -> void: changes.append(1))
	var revision: int = grid.geometry_revision
	for tick: int in range(1000):
		grid.advance(1.0 / 120.0, 1.0)
	check(changes.is_empty())
	surface.deposit(Vector2(16, 16), 1.0)
	grid.advance(1.0, 1.0)
	check(surface.saturation_at(Vector2(16, 16)) == 0.0)
	changes.clear()
	for tick: int in range(1000):
		grid.advance(1.0 / 120.0, 1.0)
	check(changes.is_empty())
	check(grid.geometry_revision == revision)
