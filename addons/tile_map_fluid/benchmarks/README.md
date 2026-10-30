# TileMapFluid performance benchmarks

This permanent suite ships with the addon, including its scenes, Resources,
capture helper and regression comparer. Copying only `addons/tile_map_fluid/` into a
clean project is sufficient; no Grow Stuff tooling or physics plugin is required.
Run from that project's root with Godot 4.7.2. The default compares 32, 16 and
8 local pixels with identical tiles, wall, holes, island, 100 receivers, input
trajectory, saturation rate and duration. Production settings are never edited.

```sh
godot --rendering-method gl_compatibility --disable-vsync --fixed-fps 120 \
  --path . --script addons/tile_map_fluid/benchmarks/run.gd -- \
  --output=res://reports/benchmarks/run-1
```

The default explicitly paces 30 measured wall/simulation seconds per workload,
after three seconds of warmup. Slow frames can extend the wall duration.
`--fixed-fps` alone bypasses Godot's frame cap; the tool supplies its own pacing.
Use `--uncapped` to measure throughput instead, retaining the same input ticks.
Repeat with a new output directory; use `--spacing=16`, `--seconds=15`,
`--warmup=2` or `--workload=moving_spray` to narrow a run. `--probe-only`
generates landings, saturation profiles and wall captures without timing trials.

Edit [default.tres](default.tres) in the editor and pass
`--settings=res://addons/tile_map_fluid/benchmarks/default.tres` for alternate workload sizes.
The [room scene](room.tscn) exposes the TileMapLayer, surface, presentation,
footprint, emitter, wall and UI. Its script creates the configured tile coverage
and receiver instances before entry. Launch it through the runner.

`results.json` retains raw microsecond series, nearest-rank summaries, engine,
hardware, renderer, arguments, counts and process-wide memory counters.
`settings.tres` preserves the actual workload. Graphical runs also save captures.
Each workload starts with a fresh dry or fully saturated field; preparation
is timed separately and excluded from steady frames. Crowded contacts advance
100 receivers and read another 100 movement samples; other workloads read four.
The moving emitter includes receiver discovery/direct hits. `game_splash`
isolates the addon's compatibility splash; it is one landing, not the game's
multi-stamp hose cone. Receivers are stationary and are hidden only for captures.

Upload times measure CPU command submission at 20 Hz, not isolated GPU duration.
Frame intervals include rendering, engine overhead and explicit pacing. Headless
times cannot establish rendered performance. Memory counters cover the whole
process, including retained reports/assets; the water-buffer byte count is only
the float32 saturation array, not total field memory. Geometry events are full
vanilla-addon coverage rebuilds, not the game's regional dirty-cell adapter.
Inspect conditional geometry/rebuild timings and worst frames: a 1 Hz hitch can
fall outside p99 at 120 Hz. Fixed-order trials are diagnostics, not thermal or
hardware acceptance. Use a representative game run before selecting a default.

## Regression checks

Archive a baseline and repeat the same workload on the same machine, renderer,
engine version and power settings. Compare the reports with:

```sh
godot --headless --path . --script addons/tile_map_fluid/benchmarks/compare.gd -- \
  --baseline=res://reports/benchmarks/baseline/results.json \
  --current=res://reports/benchmarks/current/results.json
```

The comparer exits 0 on pass, 1 for a measured regression and 2 for incompatible
reports. It checks p50/p95 operation times with a default 25% relative allowance
and a 50µs absolute noise allowance (the larger applies). Adjust with
`--tolerance=0.15 --noise-us=50`. Hardware, engine, exported workload settings,
case coverage, geometry counts and timer sample counts must match. Paced frame
intervals are excluded; use `--uncapped` runs to compare rendering capacity too.
Keep repeated baselines per controlled machine rather than committing universal
millisecond limits. An opt-in CI job can run the same commands on a stable worker;
this change does not wire a timing gate into Grow Stuff's shared CI runners.
Schema-1 study reports remain historical evidence; capture a schema-2 baseline
for comparisons because it records all exported workload settings.

The vanilla behavior and performance tests run with
`godot --headless --path . --script tools/run_tests.gd` from the TileMapFluid
repository. They require no testing addon. CI records all six workloads at all
three resolutions; shared-runner timings are diagnostic, not a hardware gate.

## Hardware evidence

On the Deck, use the repository SSH/export instructions with matching templates.
An exported benchmark must include this directory/runner, preserve the two SVG
source files as readable files, and launch with
`--script res://addons/tile_map_fluid/benchmarks/run.gd --` plus these same user options.
Keep raw output under the exported project's `reports/` directory. Record
actual hardware/renderer and display mode; desktop/headless runs cannot substitute
for Deck evidence. Benchmark export/launch has not been verified on the unavailable
Deck. The [dated findings](findings/2026-10-29-resolution.md) track missing hardware
and open selection; raw studies remain outside addon source.
