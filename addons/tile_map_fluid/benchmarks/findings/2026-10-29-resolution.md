# Wetness resolution evaluation — 2026-10-29

Keep the production default at **32 local pixels**. A 16px field is the next
candidate to investigate after improving receiver coverage queries and checking
rendered game/Deck performance. No finer resolution or movement tuning was
selected. Eight pixels substantially increases uploads and geometry hitches.
The Steam Deck did not respond to SSH at `192.168.50.150:22` with the configured
key and a five-second connection timeout; hardware evidence and final selection
remain open.

## Workload and evidence

The reusable [benchmark](../README.md) compares the same 554 authored
32px tiles in a 1024×576 envelope, negative coordinates, a hole, a disconnected
island, an angled 12px wall, 100 stationary receiver bodies/artwork, a moving
22px circular landing at 1.25 saturation/second, 120 simulation ticks/second,
72-second floor drying and 20 Hz CPU uploads. Each of six workloads has its own
dry/saturated preparation and warmup. The floor and shader SVGs are rasterized
from addon sources inside the tool because this project's vector importer
cannot supply sampled TileSet/shader textures; game assets are unchanged.

Hardware: macOS, Apple M1 Pro, 10 CPU cores, Compatibility OpenGL over Metal,
Godot **4.7.2** `ed1daf0bf`, Rapier **0.8.40**, 1152×720 viewport, VSync off.
This is an isolated addon workload, not full-game FPS or Deck acceptance.
Raw observations, exact settings/commands, local cache candidate, real-cat probe
and captures remain ignored under `brainstorming/wetness-addon/section-6/`.

The initial `rendered/` trial is **uncapped**: 1,800 measured frames per workload
after 360 warmup frames, representing 15 simulation seconds. `--fixed-fps`
bypasses Godot's frame cap even with `--max-fps`; these intervals measure
capacity, not sustained 15-second wall windows. The tool now paces explicitly
by default, with `--uncapped` available to reproduce capacity trials.

The `sustained/` repeat has the same 18 × 1,800 measured frames and inputs,
with **302.2 measured wall seconds** in total, excluding warmup/preparation.
Each workload ran for 15.4–19.4 measured wall seconds. Timer oversleep makes
paced idle intervals about 9.3 ms; they are not a throughput/FPS claim.
Representative sustained frame tails (p99 / worst, milliseconds):

| Workload | 32px | 16px | 8px |
| --- | ---: | ---: | ---: |
| Dry idle | 9.50 / 9.62 | 9.48 / 9.58 | 9.35 / 9.47 |
| Moving emitter | 9.34 / 9.38 | 9.21 / 9.24 | 12.24 / 13.52 |
| Saturated/drying | 9.47 / 9.52 | 9.41 / 9.46 | 10.56 / 11.81 |
| Crowded contacts | 8.78 / 9.10 | 8.78 / 10.08 | 13.52 / 14.66 |
| Full geometry edit | 9.53 / 21.24 | 9.49 / 54.52 | 11.49 / 193.73 |

These short sequential trials establish local scaling, not sustained thermal
acceptance. The uncapped run shows the same cost ordering without intentional idle.

## Component scaling

Representative means from the uncapped rendered run, milliseconds unless stated:

| Measurement | 32px | 16px | 8px |
| --- | ---: | ---: | ---: |
| Covered field cells | 554 | 2,216 | 8,856 |
| Connected patches | 565 | 2,226 | 8,860 |
| Saturation contacts | 672 | 2,423 | 9,241 |
| Saturation array bytes only | 2,688 | 9,692 | 36,964 |
| Wet drying step | 0.040 | 0.140 | 0.530 |
| Moving emitter dose, including discovery | 0.533 | 0.855 | 2.135 |
| Compatibility soft splash | 0.039 | 0.082 | 0.258 |
| Wet upload event, CPU submission | 0.255 | 1.012 | 4.007 |
| Full coverage edit event | 10.4 | 36.7 | 143.5 |
| Rebuild/upload after edit | 2.8 | 8.9 | 32.8 |

Dry idle takes the constant-time evaporation path. Steady uploads and drying
grow with field size even if queries are cached. Full vanilla-addon coverage
rebuilds run at 1 Hz in the geometry workload; the game has a separate regional
replacement path, so these edit times must not be presented as game door timings.
Inspect conditional event costs and worst frames: 1 Hz events can fall outside
p99 at 120 Hz. Whole-process static/video counters and raw series are retained;
they include assets and accumulated reports, not just the field. The byte count
above is only its float32 water buffer, not total memory.
Dry-idle process static allocation above the pre-room baseline was approximately
5.4/7.2/20.2 MB at 32/16/8px. These sequential deltas include scene/assets and
allocator/cache history; they are not isolated field-memory estimates. Reported
draw calls rose from 47 to 78 to 142 with the same 100 receivers.

## Contact routing and cache experiment

A separate headless probe uses the actual game WetFloor, ObjectWetness and cat,
with an isolated 1024×576 floor, default carrying/locomotion settings and normal
120 Hz Rapier physics. For a wet 22px landing, batches of 200 queries average:

| Actual game API | 32px | 16px | 8px |
| --- | ---: | ---: | ---: |
| Receiver's `surface.saturation_at()` | 3.81 ms | 12.40 ms | 44.97 ms |
| Indexed `WetFloor.wetness_at()` | 0.62 ms | 0.62 ms | 0.63 ms |

The game provider emits coverage polygons per field cell. The generic surface
coverage gate scans those polygons, including on dry queries; its cost grows
with resolution. The indexed field already supports fine interpolation cheaply.
This is a routing/coverage bottleneck, not evidence that traction must be tile-wide.

Only after measuring this bottleneck, a local cache candidate integrated the
bilinear field exactly over clipped polygon triangles, weighting by wettable
area within each 32px tile. Walls/holes return zero; disconnected pieces in the
same tile intentionally share its mean. Fine water, object state and artwork
remain unchanged. Uniform drying agrees with fine samples within 6×10⁻⁸.
Numerical 0.5px integration across six wall-clipped tiles per resolution agrees
within 0.000118 saturation; hole and wall queries return zero.

In the vanilla-tile room, 600 repeated batches of 200 cached reads cost
0.165/0.169/0.170 ms at 32/16/8px, but refreshing the means every physics tick
costs another **0.362/1.194/4.644 ms**. Direct fine backend reads cost about
**0.276 ms** at all spacings. Geometry-weight construction costs
2.1/7.5/29.4 ms. The candidate also dilutes a tiny landing's peak from 1.0 to
0.75 at 16px and 0.28125 at 8px, and spreads that traction across its tile.
No cache or coarser traction policy was promoted. A lower refresh rate would
introduce latency and was not used to claim equivalent performance/behavior.

## Visible detail and actual braking

Matched captures/profiles cover circle radii 3, 12, 22 and 32, the game's 32px
soft splash and occlusion across the angled wall. Fine geometry still clips
the wall at every spacing. A 3px landing produces a visibly oversized soft
patch at 32px and a much smaller patch at 8px: tiny footprints wet intersected
patches, so effective size depends on both the lattice and the stamping policy.
A 32px stamp remains broad at 8px; finer cells alone do not make a narrower hose.
Along the same one-pixel horizontal scan, the 3px landing spans 95/63/31 pixels
above 1% saturation at 32/16/8px. The 32px soft splash spans 95/79/71 pixels.
This supports finer small landings while also exposing footprint policy limits.

With the real cat released at 240 px/s at the same off-lattice landing center,
measured travel over 180 physics ticks is:

| Landing radius | 32px | 16px | 8px |
| --- | ---: | ---: | ---: |
| Dry control | 22.00 px | 22.00 px | 22.00 px |
| 3px | 43.88 px | 39.88 px | 30.48 px |
| 22px | 42.67 px | 39.88 px | 43.11 px |
| 32px | 43.88 px | 51.87 px | 50.97 px |

Small-stamp effects are not monotonic across all radii because stamping uses
intersected patches/projected contacts. These are deterministic handling probes,
not human feel acceptance. Keep the same movement settings when evaluating a
finer candidate; changing resolution already changes where wet traction applies.

Verification: both 18-row trials pass duration/count/finite-timing and wall/hole
checks. Strict native style, formatting and enabled compiler warnings pass for
all five new scripts; scene draw order checks 237 scenes with zero findings, and
the graphical draw-order suite passes all 23 tests. Migration-wide section 7
validation and benchmark export/Deck execution remain separate, unfinished work.
