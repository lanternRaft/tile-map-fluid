# TileMapFluid

Godot 4.7 components for TileMapLayer water saturation, emitters, wettable objects,
drying, and optional floor/object presentation. Uses stock Godot physics with no
autoloads or third-party dependencies. Extracted from Grow Stuff; existing
`WetSurface2D`, `WetGridSimulation`, `WaterEmitter2D`, and `Wettable2D` APIs remain
compatible.

Copy or symlink `addons/tile_map_fluid` into your project's `addons/` directory,
then import the project. Enabling the editor plugin is optional. Open this
repository in Godot to run the included demo: aim with the mouse, water with
left mouse/Space, move the receiver with WASD/arrows, and toggle contact with L.

See the [component guide](addons/tile_map_fluid/README.md) for composition,
coordinate conventions, coverage providers, signals, and rendering integration.

Run vanilla behavior and performance tests with Godot 4.7.2:

```sh
godot --headless --editor --path . --quit
godot --headless --path . --script tools/run_tests.gd
godot --headless --path . --script tools/run_benchmarks.gd
godot --headless --path . --script tools/check_scripts.gd
```

Tests cover emissions, independent instances, coverage changes, obstruction,
drying, lifecycle, presentation, and bounded performance costs. Reports are
written under `reports/`. Runtime and parse errors fail the supervised test run.
See [performance benchmarks](addons/tile_map_fluid/benchmarks/README.md) for
full workloads, rendered captures, and matched-machine regression comparisons.
Run pixel regressions with
`godot --path . --script tools/run_tests.gd -- --rendered-only` (requires a display).

Grow Stuff links this folder through its ignored dependency checkout. Its test
bootstrap uses this local repository when present; CI checks out
`lanternRaft/tile-map-fluid` before importing the game.
