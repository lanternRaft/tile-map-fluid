# TileMapFluid

Godot 4.7 components for TileMapLayer water saturation, emitters, wettable objects,
drying, floor water rendering, and object wetness tinting. Uses stock Godot physics with no
autoloads or third-party dependencies. Extracted from Grow Stuff. All addon classes
use the `TileFluid` prefix so their ownership is visible in the profiler and editor.

Copy or symlink `addons/tile_map_fluid` into your project's `addons/` directory,
then import the project. Enabling the editor plugin is optional.

## Try the demo

Run `godot --path .` or press F6 on the demo scene. Move with WASD or arrows,
aim with the mouse, and hold left mouse or Space to spray. L lifts or grounds the character.
Hover a puddle to read its saturation alongside the floor underfoot and each object's water level.

| Control | What to test |
| --- | --- |
| **Landing hose** | Release the trigger while drops are in flight. Water arrives when they land. |
| **Cone hose** | Aim along the wall and then around its opening. The outlined cone uses the same immediate, overlapping splashes and direct-hit logic as the live test. |
| **All-wet render preview** | Inspect wet artwork, draw order and braking on a saturated floor. Drying resumes when you stop the preview. |
| **Reset room (R)** | Start again with a dry floor, grounded character and props in their original positions. |
| **Start live test** | Choose 1–4 hoses and 1× or 8× physics, then watch the autopilot on a 128×128 floor with 64 receivers and eight barriers. Change speed during a run to restart its timing window. |

Each live hose emits once per fixed 1/120-second simulation tick. At 8× the
target is 960 ticks per wall second and 120 rendered FPS. The HUD counts frames
over 8.33 ms and the worst interval after a two-second warmup. The demo restores
VSync, frame cap and physics timing on exit. Use `godot --path . -- --stress`
to open directly in the live test. The Workload node exposes population and spray settings.

## Benchmark the live demo

```sh
python3 tools/bench_demo.py
python3 tools/bench_demo.py --mode rendered --speed 8 --seconds 30 --repeat 1
```

The first command repeats a seeded 3,600-tick route three times. The second
measures actual frame and physics rates in a window. Both write raw trials and
a JSON summary under `reports/benchmarks/live-demo/`. See the
[benchmark controls](addons/tile_map_fluid/benchmarks/README.md#live-demo) and
[performance plan](PERFORMANCE_PLAN.md).

See the [component guide](addons/tile_map_fluid/README.md) for composition,
coordinate conventions, tile coverage, signals, and rendering integration.

In the demo scene, expand `Floor` to find `Surface` (`TileFluidSurface2D`) and its
`Simulation` child. They are authored directly in the demo scene. `Surface`
stores and coordinates floor wetness and automatically owns its renderer. The emitter and wettable objects reference `Floor/Surface`.

Add `TileFluidSurface2D` and assign its `tile_layer` and coverage. Surface automatically
creates its simulation and renderer; configure water visuals through its
`appearance` resource. No separate Presentation node or renderer wiring is needed.
Water mesh rows are placed automatically in the nearest ancestor's Y-sorted world
band so the dry floor's draw order does not affect water/object sorting.

The precomposed `addons/tile_map_fluid/wet_surface.tscn` also includes Lifecycle
for staged initialization and batched obstacle refreshes. Existing scenes with
explicit simulation or renderer assignments remain supported.

`TileFluidSurface2D` now uses the same editor icon as `TileFluidSurfacePresentation`.
`TileFluidSurfaceRow` uses that icon too; the former `surface.svg` icon has been removed.

## Included nodes and scene layout

These are the addon's scene nodes. Parent locations below are recommended unless
marked required; assign host references in the Inspector. Surface supplies its
simulation and renderer automatically when they are not already configured.

| Node (Godot base type) | Purpose | Where it belongs |
| --- | --- | --- |
| `TileFluidSurface2D` (`Node2D`) | Connects floor coverage, saturation queries, deposits, drying, receivers, and optional traction. | Under the floor `TileMapLayer`, or under the room when composing several layers. Assign `tile_layer` for coordinates. |
| `TileFluidGridSimulation` (`TileFluidSurfaceSimulation` → `Node`) | Stores and simulates the floor's saturation grid. | Created automatically as a direct child of `TileFluidSurface2D`. Explicit custom backends must also be direct children. |
| `TileFluidSurfacePresentation` (`Node2D`) | Internal renderer owned automatically by Surface. | No manual placement required; configure `TileFluidSurface2D.appearance`. |
| `TileFluidSurfaceLifecycle` (`Node`) | Prepares startup coverage, supports staged initialization, and batches obstacle updates after physics registration. | Usually under `TileFluidSurface2D`; assign `surface`, optional `presentation`, and the surface's `lifecycle`. |
| `TileFluidEmitter2D` (`Node2D`) | Applies a uniform dose over a footprint, continuously while active or through `emit_dose()`. | Under the watering tool or source; assign one destination `surface` and its `footprint`. |
| `TileFluidFootprint2D` (`Area2D`) | Defines the emitter's shape union and discovers wettable objects. | Usually under `TileFluidEmitter2D`; its `CollisionShape2D` / filled `CollisionPolygon2D` shapes **must be direct children**. |
| `TileFluidSpray2D` (`Node2D`) | Emits overlapping soft splashes in a hose cone, with obstacle checks and receiver wetting. An alternative to footprint emission. | Under the watering tool, at its floor-space outlet, with positive X pointing along the spray; assign `surface` and `receiver_scope` or explicit `receivers`. |
| `TileFluidWettable2D` (`Area2D`) | Gives an object retained wetness, ground absorption, drying, direct-water signals, optional artwork tinting, and rigid-body traction. | Under the object/body; add a direct child collision shape for Area discovery and assign `surface`, `contact_point`, and `direct_point`. |
| `TileFluidSurfaceSimulation` (`Node`, abstract) | Backend contract for custom deposition, sampling, and drying. | Subclass it instead of instantiating it; the concrete backend **must be a direct child** of its surface. |
| `TileFluidSurfaceRow` (`MeshInstance2D`) | Internal water mesh for a rendering row/batch. | Created and managed automatically by the renderer in the world sorting band; do not add manually. |

Typical setup using tile coverage, a footprint emitter, and one wettable object:

```text
Room (Node2D, y_sort_enabled = true)
├── Floor (TileMapLayer, z_index = -1)
│   └── Surface (TileFluidSurface2D)
├── WateringTool (Node2D)
│   └── Emitter (TileFluidEmitter2D)
│       └── Footprint (TileFluidFootprint2D)
│           └── CollisionShape2D
└── Crate (RigidBody2D)
    ├── CollisionShape2D
    └── Receiver (TileFluidWettable2D)
        └── CollisionShape2D
```

- On `Surface`, assign `tile_layer = Floor` and configure `settings` and
  `appearance`. Simulation and rendering are managed internally.
- On `Emitter`, assign `surface = Surface` and `footprint = Footprint`. Match
  the footprint's collision mask to the receiver's collision layer.
- On `Receiver`, assign `surface = Surface`, its contact/direct-water markers,
  and `obstacle_body = Crate`. Assign `artwork` to a regular `Node2D` wrapper
  for wet tinting. Enable Surface traction and assign `traction_body`
  for wet-ground drag.

For a hose, replace `Emitter` and its footprint subtree with a `TileFluidSpray2D`
child of `WateringTool`; set its `surface = WetSurface` and `receiver_scope = World`.
Use either emission approach for a single water source unless double dosing is
intentional. Keep floor art behind the water/object sorting band.

`TileFluidSurfaceSettings`, `TileFluidSurfaceAppearance`, `TileFluidEmitterSettings`,
`TileFluidSpraySettings`, and `TileFluidWettableSettings` are Inspector Resources, not scene
nodes. Other helper classes are implementation details, not nodes to place in
the tree. The optional editor plugin adds no runtime node or autoload.
For a precomposed surface, instance `addons/tile_map_fluid/wet_surface.tscn` and
assign its coverage and host references as described in the component guide.

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
