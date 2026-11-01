# TileMapFluid behavior-preserving performance plan

## Objective

Reduce the addon's CPU cost enough to leave substantial headroom for a real game.
The demo's 8× mode is a stress test, not a production update-rate recommendation.
Preserve 120 simulated physics ticks per second and the existing per-tick water
behavior. At 8×, execute all 960 ticks per wall-clock second while targeting
120 rendered FPS.

An initial engineering budget is **0.2 ms of addon CPU work per simulated tick**
on the reference machine: approximately 1.6 ms across eight ticks in an 8.33 ms
rendered frame. This is a proposed budget, not a measured achievement or a
low-end hardware guarantee. Record total CPU consumption as well as main-thread
time so moving work onto other cores does not hide costs imposed on the game.

## Rules that apply to every stage

- Preserve tick frequency, dose timing, simulation step size, spray spacing,
  map size, receiver count, obstacle behavior, and drying configuration.
- Preserve immediate public reads, per-splash clamping, additive overlap between
  splashes, strongest contribution within a splash, and saturation-dependent
  splash radii. Later splashes must observe preceding writes in the same order.
- Preserve contact, traction, direct-hit eligibility, and observable signal
  payloads and ordering, including reentrant callbacks. Do not silently defer
  effects to the next frame or batch across an observable dependency.
- Cache geometry and validated dependencies, not stale wetness. Use explicit
  invalidation for every dependency, including runtime Resource edits.
- Keep the current implementation available as a behavioral reference. Compare
  every tick, not just final saturation. Discrete results and event ordering must
  match exactly; define and justify numeric tolerances before optimizing, and do
  not widen tolerances to hide a regression. Preserve operation order and numeric
  precision where required.
- Preserve existing user changes. This checkout already contains substantial
  uncommitted work. Inventory it before editing; do not reset or overwrite it.
- Complete one stage at a time. Update its evidence record and checkboxes before
  starting another stage. Failed experiments may be discarded; do not retain a
  complexity increase without demonstrated benefit.

## Shared measurement and acceptance protocol

- [ ] Establish a reproducible runner for the **actual demo live-cone workload**:
  128×128 tiles, one hose, 64 workload receivers, eight workload barriers, and
  72-second floor drying. Include the existing character and other demo objects.
  The all-wet preview and single-splash benchmark are not substitutes.
- [ ] Record engine/build, OS, CPU/GPU, renderer, viewport, power mode, arguments,
  seed, workload settings, source revision, and a patch/content manifest for the
  dirty checkout. Keep baseline and candidate source states reproducible.
- [ ] Use identical seeded input trajectories and fixed tick counts for CPU and
  behavior comparisons. Faster variants must not receive a different simulation
  history merely because they complete more ticks during a wall-clock window.
- [ ] Separately run real-time rendered acceptance at 1× and 8×. Use a wall-clock
  deadline, an unlocked/visible desktop, matching viewport, disabled VSync, and
  no frame cap. Do not use `--fixed-fps` to claim real-time FPS or physics rate.
- [ ] Exclude setup and an explicit warmup from steady-state measurements, but
  record startup and geometry-edit costs separately. Use at least three paired
  baseline/candidate trials, alternate order, and avoid concurrent benchmarks.
  Use at least 30 seconds of steady rendered measurement per trial; extend final
  acceptance to sustained runs covering several route/drying cycles.
- [ ] Record raw frame intervals, p50/p95/p99, worst frame, fraction over 8.33 ms,
  achieved physics ticks/s, simulated time versus wall time, and dropped/backlog
  indicators. Record operation timings, total addon CPU/tick, worker CPU time,
  waits, scratch allocations, memory, rays, and uploads where measurable.
- [ ] Keep diagnostic instrumentation equivalent in both variants. Measure its
  overhead and confirm final throughput with instrumentation disabled. Never
  compare an instrumented candidate against an uninstrumented baseline.
- [ ] Require a repeatable improvement beyond measured run-to-run noise in the
  stage's target metric, plus no material regression in aggregate addon CPU,
  frame-time tails, or memory. Predeclare the threshold after repeated baseline
  trials; report absolute time saved and percentage change. A regression check
  passing is not evidence of an improvement.
- [ ] Run behavior tests and deterministic reference replays. Include moving and
  stationary receivers, multiple overlapping hoses, changing obstacles, partial
  tiles, seams, transformed layers, direct hits, contact toggles, drying, and
  geometry replacement. Add cases specific to each new invalidation path.
- [ ] Store raw results under `reports/benchmarks/architecture/<stage>/<variant>/`.
  This directory is ignored by Git. Put a concise, durable findings document
  under `addons/tile_map_fluid/benchmarks/findings/` with source identification,
  commands, settings, result tables, limitations, and raw artifact locations.

Existing infrastructure:

- `addons/tile_map_fluid/benchmarks/README.md`, `run.gd`, and `compare.gd` provide
  timing and regression infrastructure. Reuse it where appropriate; the demo
  workload needs explicit coverage and an improvement gate.
- `godot --headless --path . --script tools/run_tests.gd` runs behavior tests.
- `godot --headless --path . --script tools/check_scripts.gd` checks scripts.
- `godot --path . --script tools/run_tests.gd -- --rendered-only` runs rendered
  regressions on a machine with a display.
- Historical diagnostics are in `reports/demo-profile-2026-10-31.json`, when
  available. They are short, instrumented experiments, not acceptance baselines.
  They measured about 0.56 ms/tick for wettable updates and 0.26 ms/tick for floor
  spraying. Hiding water rendering did not materially improve throughput.
  The 30 Hz experiment changes behavior and must not be used as the candidate.

## Stage 1 — Prepared receiver contacts and validated sampling

**Goal:** Reduce repeated validation, transform conversion, coverage checks, and
polygon lookup while evaluating the same current samples every tick.

- [ ] Establish the shared baseline and replay harness before changing behavior
  paths. Keep this work focused on what is needed to evaluate this stage.
- [ ] Profile wettable updates more finely: contact refresh, surface validation,
  coverage lookup, interpolation, tint/signals, and traction. Confirm which
  operations account for the measured aggregate cost.
- [ ] Add an internal prepared-contact handle containing patch/sample identities,
  interpolation weights, resolved coverage eligibility, and dependency revisions.
  Retain the fully validated public sampling path for uncached/arbitrary queries.
- [ ] Reuse the handle only while receiver/contact-marker and layer transforms,
  surface assignment, world, contact configuration, settings, and geometry remain
  valid. Cover direct property/Resource edits, reparenting, deletion, slot reuse,
  partial geometry replacement, and movement along/outside polygon boundaries.
- [ ] Read all four live sample values at the current drying clock each tick;
  preserve corner clamping before interpolation and current absorption/traction
  ordering. Do not cache final saturation or reduce callback/update cadence.
- [ ] Avoid repeated settings validation within a verified internal operation.
  Add setters/revisions or another explicit invalidation mechanism where needed;
  do not assume a mutable shared Resource stays unchanged.
- [ ] Add differential tests for same-tick deposits, drying, movement, seams,
  contact changes, runtime settings changes, and geometry edits. Compare cached
  sampling with the reference path after each operation.
- [ ] **Performance gate:** Show reduced wettable-update and total addon CPU/tick
  beyond noise on the live workload and stationary/moving receiver cases. Rerun
  rendered 1×/8× trials and reject a cache that improves only stationary objects
  while materially regressing moving objects or invalidation hitches.
- [ ] Save findings, fill in the evidence record, and mark completion only after
  correctness and improvement gates pass.

## Stage 2 — Native numerical core with compact storage

**Goal:** Execute the same calculations with fewer allocations and script calls.

- [ ] Use Stage 1's accepted implementation as this stage's baseline.
- [ ] Define the smallest native CPU kernel for sample evaluation and splash
  accumulation. Keep existing Godot node APIs and synchronous read/write behavior.
  The kernel can initially be owned by `TileFluidGridSimulation`; avoid assuming
  a backend swap alone works, since spray and presentation currently depend on
  the concrete grid implementation.
- [ ] Store hot sample values, timestamps, indices, and interpolation data in
  contiguous buffers. Keep polygon topology separate and immutable between edits.
  Preserve shared contacts and disconnected patches around obstacles.
- [ ] Add an exact regular-cell fast path, retaining the existing geometric path
  for clipped or exceptional cells. Preallocate/reuse accumulation scratch space;
  replace per-splash dictionary allocation where equivalence is demonstrated.
- [ ] Implement the kernel in a C++ GDExtension with documented reproducible
  builds for supported targets. Retain the reference implementation for testing
  and as a fallback where native binaries are unavailable.
- [ ] Keep the numerical operation order and storage precision compatible with
  the reference; avoid fast-math or reassociation that changes tested results.
  Keep scene/Resource access, physics queries, and signals outside pure kernels.
- [ ] Test both the native and fallback paths, lifetime/cleanup, regional rebuilds,
  transformed fields, shared samples, and reference replay equivalence.
- [ ] **Performance gate:** Compare native versus the accepted scripted baseline
  with identical compiler/build modes and workloads. Show a repeatable reduction
  in total addon CPU/tick and hot-path allocations, including native-call overhead.
  Verify p95/p99 frame times and startup/edit costs have not materially regressed.
- [ ] Save findings and complete the evidence record. If native work does not
  provide a meaningful aggregate win, revise its boundaries before retaining it.

## Stage 3 — Ordered spray execution and exact visibility fast paths

**Goal:** Eliminate repeated spray setup and redundant geometric work while
preserving every splash and its order-dependent result.

- [ ] Baseline the accepted previous stage; measure rays, candidate patches,
  geometry tests, temporary allocations, and time per hose tick.
- [ ] Precompute the local cone sample pattern when hose settings change. Transform
  that pattern at emission time; preserve sample order and finite-cone inclusion.
- [ ] Reuse query objects and candidate/scratch buffers with explicit reset rules.
  Avoid scene/API crossings inside numerical inner loops where possible.
- [ ] Introduce conservative obstacle candidate bounds. Skip exact visibility
  checks only when the entire relevant segment/region is proven free of blockers.
  Near candidate blockers, retain exact Godot query behavior, exclusions, target
  body rules, underpaint behavior, and dynamic-obstacle handling.
- [ ] Process dependent splashes sequentially: sample current center saturation,
  calculate radius, apply the splash, then evaluate the next splash. Do not replace
  the hose with a union stamp or sum overlapping commands from one stale snapshot.
- [ ] Coalesce internal rendering dirty bookkeeping where possible without
  removing or reordering externally observable water/change notifications.
- [ ] Test overlap order, saturation-dependent radii, several hoses, narrow walls,
  moving/rotating obstacles, masks/exclusions, underpaint, boundary rays, and
  signal callbacks that read or modify water during an emission.
- [ ] **Performance gate:** Demonstrate lower floor-spray and aggregate CPU/tick
  on the live scene, plus open-floor and obstacle-dense cases. Report query-count
  reductions and invalidate/rebuild costs. Reject shortcuts with behavioral drift
  or gains confined to an unrepresentative obstacle-free scene.
- [ ] Save findings and complete the evidence record.

## Stage 4 — Coarse-grained parallel CPU execution

**Goal:** Reduce latency using spare cores without consuming disproportionate
total CPU or changing when gameplay observes results.

- [ ] Baseline the accepted serial implementation. Identify independent work and
  measure batch sizes before adding scheduling overhead.
- [ ] Define dependencies explicitly: independent surfaces/regions and receiver
  sampling against a stable state may run concurrently; overlapping writes,
  saturation-dependent spray steps, and reentrant callbacks retain ordered paths.
- [ ] Give workers immutable numerical inputs and private output/scratch buffers.
  Keep active scene-tree access, physics queries, and signal delivery on supported
  threads at the existing observable execution points.
- [ ] Use persistent workers or `WorkerThreadPool` with a configurable worker cap,
  minimum useful batch size, and serial fallback. Avoid per-receiver/per-splash
  tasks and avoid monopolizing cores needed by the host game.
- [ ] Synchronize before the same reads/callbacks that observe results today.
  Do not introduce frame-delayed snapshots. Preserve operation/event ordering;
  use synchronous fallback when dependencies cannot be proven independent.
- [ ] Test deterministic replays at multiple worker counts, teardown and edits
  during queued work, repeated runs for races, and serial/parallel equivalence.
- [ ] **Performance gate:** Measure worker execution, enqueue/merge time, waits,
  main-thread critical path, and summed CPU. Compare one-hose, many-hose, small,
  and large scenes under both idle and representative competing CPU load. Enable
  threading only where it wins beyond noise without unacceptable total-CPU or
  p99 regressions. Keep small workloads serial if that is faster.
- [ ] Save findings and complete the evidence record. A measured decision to keep
  a workload serial is valid; an unproven parallel implementation is not a win.

## Stage 5 — Optional compute backend, only if justified by remaining costs

**Goal:** Evaluate GPU compute against the optimized CPU implementation without
changing authoritative gameplay behavior or supported baseline platforms.

- [ ] Proceed only if profiling still identifies enough parallel numerical work
  to justify dispatch, transfer, synchronization, and maintenance costs.
- [ ] Document the renderer constraint: compute requires Godot Mobile/Forward+;
  Compatibility remains supported by the CPU path. Compare CPU and GPU kernels
  within the same renderer, and separately report the cost of changing renderer.
- [ ] Prototype a bounded numerical kernel with identical input/order semantics.
  Include CPU visibility work, transfers, barriers, and required readbacks in its
  timings. Do not compare isolated shader duration against end-to-end CPU cost.
- [ ] Resolve immediate CPU gameplay reads without stale data. If synchronization
  removes the benefit, reject this backend for authoritative simulation. Visual
  effects alone do not count as meeting the simulation optimization goal.
- [ ] Validate numeric behavior, overlap ordering, same-tick reads, and fallback
  parity across target GPUs. Preserve all CPU reference contracts.
- [ ] **Performance gate:** Demonstrate an end-to-end improvement over the accepted
  CPU backend, including frame-time tails, CPU/GPU contention with a representative
  game, and low-end supported devices. Retain the GPU path only for workloads where
  it measurably wins; otherwise record a no-go finding and retain CPU execution.
- [ ] Save findings and the adoption/no-go decision. Do not mark an experiment as
  a performance improvement merely because it moved work to the GPU.

## Final acceptance

- [ ] Re-run the original full-fidelity demo workload at 1× and 8×, with every
  simulation tick, dose, receiver, and obstacle present.
- [ ] Demonstrate sustained 120 FPS and 960 physics ticks/s at 8×; inspect p95/p99,
  worst frames, and deadline misses rather than declaring success from average FPS.
  Report remaining misses and causes explicitly.
- [ ] Confirm low normal-speed addon CPU cost in the real game, including its
  physics backend and other systems. Stock demo physics is not a substitute for
  validating the game's integration.
- [ ] Validate on named low-end target hardware and record its specifications.
  M1 Pro results establish only M1 Pro performance; unavailable hardware remains
  an explicitly unverified acceptance item.
- [ ] Check export/native-library packaging, fallback behavior, memory stability,
  multiple surfaces, sustained play, and geometry-edit hitches.

## Evidence record — fill in for every stage

| Item | Result |
| --- | --- |
| Stage and implementation/source identifiers | Pending |
| Baseline and candidate commands/settings | Pending |
| Hardware, renderer, build, trial count | Pending |
| Behavior replay and regression tests | Pending |
| Target operation p50/p95 and absolute savings | Pending |
| Total addon CPU/tick and worker CPU | Pending |
| 1×/8× FPS, achieved ticks/s, p95/p99, worst, deadline misses | Pending |
| Allocations, memory, startup/edit costs | Pending |
| Noise threshold and repeatability | Pending |
| Findings document and raw reports | Pending |
| Decision: accepted / revise / rejected / unverified | Pending |

## Engine references

- [Godot 4.7 thread-safe APIs](https://docs.godotengine.org/en/4.7/tutorials/performance/thread_safe_apis.html)
- [WorkerThreadPool and task overhead](https://docs.godotengine.org/en/4.7/classes/class_workerthreadpool.html)
- [Compute shaders, renderer support, and synchronization](https://docs.godotengine.org/en/4.7/tutorials/shaders/compute_shaders.html)
