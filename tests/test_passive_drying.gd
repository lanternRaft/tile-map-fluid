extends "res://tests/test_case.gd"
## Passive records must preserve additive water, clipping edits and CPU/shader agreement.

const Fixture: PackedScene = preload("res://tests/fixtures/wetness_simulation.tscn")


## Reads and clock advances leave sample records untouched, including when completely dry.
func test_partial_rewetting_and_idle_records() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var grid: TileFluidGridSimulation = world.get_node("Layer/Surface/Field") as TileFluidGridSimulation
	var changes: Array[int] = []
	grid.changed.connect(func() -> void: changes.append(1))
	grid.deposit(Vector2(16, 16), 0.5)
	var records: PackedFloat32Array = grid.wetness_records()
	grid.advance(18.0, 72.0)
	check(is_equal_approx(grid.sample(Vector2(16, 16)), 0.25))
	check(changes.size() == 1)
	check(grid.wetness_records() == records)
	grid.deposit(Vector2(16, 16), 0.5)
	check(is_equal_approx(grid.sample(Vector2(16, 16)), 0.75))
	grid.advance(9.0, 0.0)
	grid.advance(NAN, 72.0)
	check(is_equal_approx(grid.sample(Vector2(16, 16)), 0.75))
	grid.advance(0.25, 1.0)
	check(is_equal_approx(grid.sample(Vector2(16, 16)), 0.5))
	grid.deposit(Vector2(16, 16), 0.9)
	check(grid.sample(Vector2(16, 16)) == 1.0)
	records = grid.wetness_records()
	grid.advance(2.0, 1.0)
	check(not grid.has_water())
	check(grid.sample(Vector2(16, 16)) == 0.0)
	check(grid.wetness_records() == records)
	grid.deposit(Vector2(16, 16), 0.2)
	check(is_equal_approx(grid.sample(Vector2(16, 16)), 0.2))
	check(changes.size() == 4)


## Expired corners clamp before interpolation, not after blending a patch's stored values.
func test_corner_clamping_and_snapshot_match_live_reads() -> void:
	var world: Node2D = track(Fixture.instantiate()) as Node2D
	add_child(world)
	var grid: TileFluidGridSimulation = world.get_node("Layer/Surface/Field") as TileFluidGridSimulation
	grid.deposit(Vector2(16, 16), 0.2)
	grid.deposit(Vector2(48, 16), 0.6)
	grid.advance(0.4, 1.0)
	var patch: TileFluidFieldPatch = grid.cell_patches(Vector2i.ZERO)[0]
	check(is_equal_approx(grid.sample(Vector2(16, 16)), 0.2))
	check(patch.water(grid.saturation_buffer()).is_equal_approx(grid.patch_water(patch)))
	var snapshot: PackedFloat32Array = grid.saturation_buffer()
	snapshot.fill(1.0)
	check(is_equal_approx(grid.sample(Vector2(16, 16)), 0.2))


## Geometry snapshots capture current water; removing/reusing the latest slot fixes occupancy.
func test_geometry_edits_after_drying_retain_only_surviving_water() -> void:
	var field: TileFluidFieldStorage = TileFluidFieldStorage.new()
	for x: int in range(2):
		field.add_cell(Vector2i(x, 0), [_rect(x * 64.0)])
	field.end_rebuild()
	var old: TileFluidFieldPatch = field.patches(Vector2i.ZERO)[0]
	for corner: int in old.corners:
		field.set_water(corner, 0.75)
	field.wetness.clock += 0.25
	var clock: float = field.wetness.clock
	field.begin_replace([Vector2i.ZERO])
	field.add_cell(Vector2i.ZERO, [_rect(0)])
	field.end_rebuild()
	check(field.wetness.patch_water(field.patches(Vector2i.ZERO)[0]) == Color(0.5, 0.5, 0.5, 0.5))
	field.begin_rebuild(true)
	check(field.wetness.clock == clock, "Geometry replacement must not rewind shader time")
	field.add_cell(Vector2i.ZERO, [_rect(0)])
	field.add_cell(Vector2i.RIGHT, [_rect(64)])
	field.end_rebuild()
	check(field.wetness.patch_water(field.patches(Vector2i.ZERO)[0]) == Color(0.5, 0.5, 0.5, 0.5))
	check(field.wetness.patch_water(field.patches(Vector2i.RIGHT)[0]) == Color(0, 0, 0, 0))
	field.begin_replace([Vector2i.ZERO])
	field.end_rebuild()
	check(not field.has_water())
	field.add_cell(Vector2i.ZERO, [_rect(0)])
	field.end_rebuild()
	check(not field.has_water())


## Float32 shader timestamps retain small elapsed differences after long continuous operation.
func test_split_clock_precision_and_shader_record_equivalence() -> void:
	var wetness: TileFluidFieldWetness = TileFluidFieldWetness.new()
	wetness.append()
	wetness.clock = 100000.875
	wetness.set_water(0, 0.75)
	var records: PackedFloat32Array = wetness.shader_records()
	wetness.clock += 0.126
	var clock: Vector2 = wetness.shader_clock()
	var elapsed: float = (clock.x - records[1]) + (clock.y - records[2])
	check(absf(maxf(0.0, records[0] - elapsed) - wetness.get_water(0)) < 0.000001)
	check(wetness.shader_records() == records)


func _rect(x: float) -> PackedVector2Array:
	return TileFluidFieldPolygons.rectangle(Rect2(x, 0, 32, 32))
