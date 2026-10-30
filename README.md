# TileMapFluid

Godot 4.7 components for TileMapLayer water saturation, emitters, wettable objects,
drying, floor water rendering, and object wetness tinting. Uses stock Godot physics with no
autoloads or third-party dependencies. Extracted from Grow Stuff; existing
`WetSurface2D`, `WetGridSimulation`, `WaterEmitter2D`, and `Wettable2D` APIs remain
compatible.

Copy or symlink `addons/tile_map_fluid` into your project's `addons/` directory,
then import the project. Enabling the editor plugin is optional. Open this
repository in Godot to run the included demo: aim with the mouse, water with
left mouse/Space, move the receiver with WASD/arrows, and toggle contact with L.

See the [component guide](addons/tile_map_fluid/README.md) for composition,
coordinate conventions, tile coverage, signals, and rendering integration.

In the demo scene, expand `Floor` to find `Surface` (`WetSurface2D`) and its
`Simulation` child. These belong to the instanced `demo_floor.tscn`; editable
children are enabled so you can inspect them directly in the demo. `Surface`
stores and coordinates floor wetness and automatically owns its renderer. The emitter and wettable objects reference `Floor/Surface`.

Add `WetSurface2D` and assign its `tile_layer` and coverage. Surface automatically
creates its simulation and renderer; configure water visuals through its
`appearance` resource. No separate Presentation node or renderer wiring is needed.
Water mesh rows are placed automatically in the nearest ancestor's Y-sorted world
band so the dry floor's draw order does not affect water/object sorting.

The precomposed `addons/tile_map_fluid/wet_surface.tscn` also includes Lifecycle
for staged initialization and batched obstacle refreshes. Existing scenes with
explicit simulation or renderer assignments remain supported.

`WetSurface2D` now uses the same editor icon as `WetSurfacePresentation`.
`WetSurfaceRow` uses that icon too; the former `surface.svg` icon has been removed.

## Included nodes and scene layout

These are the addon's scene nodes. Parent locations below are recommended unless
marked required; assign host references in the Inspector. Surface supplies its
simulation and renderer automatically when they are not already configured.

| Node (Godot base type) | Purpose | Where it belongs |
| --- | --- | --- |
| `WetSurface2D` (`Node2D`) | Connects floor coverage, saturation queries, deposits, drying, receivers, and optional traction. | Under the floor `TileMapLayer`, or under the room when composing several layers. Assign `tile_layer` for coordinates. |
| `WetGridSimulation` (`WetSurfaceSimulation` → `Node`) | Stores and simulates the floor's saturation grid. | Created automatically as a direct child of `WetSurface2D`. Explicit custom backends must also be direct children. |
| `WetSurfacePresentation` (`Node2D`) | Internal renderer owned automatically by Surface. | No manual placement required; configure `WetSurface2D.appearance`. |
| `WetSurfaceLifecycle` (`Node`) | Prepares startup coverage, supports staged initialization, and batches obstacle updates after physics registration. | Usually under `WetSurface2D`; assign `surface`, optional `presentation`, and the surface's `lifecycle`. |
| `WaterEmitter2D` (`Node2D`) | Applies a uniform dose over a footprint, continuously while active or through `emit_dose()`. | Under the watering tool or source; assign one destination `surface` and its `footprint`. |
| `WaterFootprint2D` (`Area2D`) | Defines the emitter's shape union and discovers wettable objects. | Usually under `WaterEmitter2D`; its `CollisionShape2D` / filled `CollisionPolygon2D` shapes **must be direct children**. |
| `WaterSpray2D` (`Node2D`) | Emits overlapping soft splashes in a hose cone, with obstacle checks and receiver wetting. An alternative to footprint emission. | Under the watering tool, at its floor-space outlet, with positive X pointing along the spray; assign `surface` and `receiver_scope` or explicit `receivers`. |
| `Wettable2D` (`Area2D`) | Gives an object retained wetness, ground absorption, drying, direct-water signals, optional artwork tinting, and rigid-body traction. | Under the object/body; add a direct child collision shape for Area discovery and assign `surface`, `contact_point`, and `direct_point`. |
| `WetSurfaceSimulation` (`Node`, abstract) | Backend contract for custom deposition, sampling, and drying. | Subclass it instead of instantiating it; the concrete backend **must be a direct child** of its surface. |
| `WetSurfaceRow` (`MeshInstance2D`) | Internal water mesh for a rendering row/batch. | Created and managed automatically by the renderer in the world sorting band; do not add manually. |

Typical setup using tile coverage, a footprint emitter, and one wettable object:

```text
Room (Node2D, y_sort_enabled = true)
├── Floor (TileMapLayer, z_index = -1)
│   └── Surface (WetSurface2D)
├── WateringTool (Node2D)
│   └── Emitter (WaterEmitter2D)
│       └── Footprint (WaterFootprint2D)
│           └── CollisionShape2D
└── Crate (RigidBody2D)
    ├── CollisionShape2D
    └── Receiver (Wettable2D)
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

For a hose, replace `Emitter` and its footprint subtree with a `WaterSpray2D`
child of `WateringTool`; set its `surface = WetSurface` and `receiver_scope = World`.
Use either emission approach for a single water source unless double dosing is
intentional. Keep floor art behind the water/object sorting band.

`WetSurfaceSettings`, `WetSurfaceAppearance`, `WaterEmitterSettings`,
`WaterSpraySettings`, and `WettableSettings` are Inspector Resources, not scene
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
