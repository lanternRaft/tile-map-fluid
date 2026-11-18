# TileMapFluid performance benchmarks

## Live demo

From this repository, run `python3 tools/bench_demo.py` with Godot 4.7.2 on PATH.
The runner imports a fresh checkout if necessary and opens the same scene and
live-test control as a human. Every trial gets a fresh Godot process. The default
uses one hose, 64 workload receivers plus the three original objects, eight barriers,
a 128×128 floor, seed 13463 and a 240-physics-tick warmup.

```sh
# Whole-loop capacity, fixed delta, identical input for every implementation
python3 tools/bench_demo.py --ticks 3600 --repeat 3 --edit-probe

# Estimate the share of time spent spraying and advancing receivers
python3 tools/bench_demo.py --cases live no-spray no-contact-ticks neither

# Stress four simultaneous hoses or change the population
python3 tools/bench_demo.py --hoses 4 --receivers 64 --barriers 8

# Actual windowed FPS, frame tails and achieved tick rate, measured for 30 wall seconds
python3 tools/bench_demo.py --mode rendered --speed 8 --seconds 30 --repeat 1
```

Throughput mode uses a headless fixed 120 FPS clock. Its reported µs/tick includes
the whole engine loop, physics, presentation submission and demo overhead. Rendered
mode disables VSync and the frame cap and uses the normal engine clock. Use a
drawable desktop window and leave the controls alone during the trial. Compare
the same mode, source, hardware and workload when estimating variance, then change
one variable for a performance comparison.

The diagnostic cases retain the bodies, collision geometry, proxies, route, HUD and
visual effects. **no-spray** disables hose doses. **no-contact-ticks** disables
receiver physics updates (sampling, drying, absorption and traction) while direct
hits remain active. **neither** combines both switches. These are reduced workloads
for estimating headroom. Each repeat reverses the previous case order.

The optional edit probe runs after timing the live route. It opens and closes a
28×52-pixel stock-physics blocker in a 64×64-pixel region. After one warmup refresh
it measures 20 synchronous regional refreshes, verifies the center is covered or
clipped on every transition, and records a post-refresh field checksum.
The next presentation refresh falls outside the measurement.

Use `--output DIR` for an empty destination or let the tool choose a timestamped
directory under `reports/benchmarks/live-demo/`. Each trial saves its effective
inputs, engine log, raw intervals, nearest-rank p50/p95/p99, counts, field hash,
memory counters, engine and hardware. The summary includes the source fingerprint,
per-case medians and trial filenames. A script error, timeout, missing report,
incorrect emission/population count or divergent repeated fixed-tick field
hash fails the run. Keep run reports under the Git-ignored `reports/` directory.

## Resolution study

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

Each workload's `presentation` entry records combined mesh, material, texture,
storage and actual upload counts separately from simulation coverage counts.
These are renderer resources, not process-wide memory or isolated GPU timings.

`results.json` retains raw microsecond series, nearest-rank summaries, engine,
hardware, renderer, arguments, counts and process-wide memory counters.
`settings.tres` preserves the actual workload. Graphical runs also save captures.
Each workload starts with a fresh dry or fully saturated field; preparation
is timed separately and excluded from steady frames. Crowded contacts advance
100 receivers and read another 100 movement samples; other workloads read four.
The moving emitter includes receiver discovery/direct hits. `game_splash`
isolates the addon's compatibility splash; it is one landing, not the game's
multi-stamp hose cone. Receivers are stationary and are hidden only for captures.

Presentation is refreshed at 20 Hz; reported refresh times measure CPU submission,
not isolated GPU duration. Passive drying updates only the clock uniform, so an
`upload_event` timer does not imply a texture upload. The presentation's `uploads`
counter records actual sample-record uploads after deposits or geometry changes.
Frame intervals include rendering, engine overhead and explicit pacing. Headless
times cannot establish rendered performance. Memory counters cover the whole
process, including retained reports/assets; the water-buffer byte count is only
the diagnostic float32 saturation snapshot, not total field memory. Passive storage
also keeps write timestamps and cached four-component GPU records. Geometry events are full
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
actual hardware, renderer, and display mode. Validate export and launch on the
Deck before using its results to choose a production default.

Keep 32 local pixels as the production default. Evaluate 16 pixels next on
representative rendered hardware with movement settings held fixed. Finer cells
can localize small landings, but they multiply sample storage, upload work, and
geometry edit costs. Time edits separately so infrequent hitches show up.
Prefer indexed reads of the live field for traction. Tile averages can flatten
small wet patches and introduce refresh work.
