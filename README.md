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

## Included nodes and scene layout

These are the addon's scene nodes. Parent locations below are recommended unless
marked required; references must still be assigned in the Inspector.

| Node (Godot base type) | Purpose | Where it belongs |
| --- | --- | --- |
| `WetSurface2D` (`Node2D`) | Connects floor coverage, saturation queries, deposits, drying, receivers, and optional traction. | Under the floor `TileMapLayer`, or under the room when composing several layers. Assign `tile_layer` for coordinates. |
| `WetGridSimulation` (`WetSurfaceSimulation` → `Node`) | Stores and simulates the floor's saturation grid. | **Required direct child** of its `WetSurface2D`; assign the surface's `simulation`. Use a separate instance per surface. |
| `WetSurfacePresentation` (`Node`) | Draws floor wetness from a `WetGridSimulation`. Optional for gameplay-only wetness. | Usually under `WetSurface2D`; assign `surface` and an explicit `presentation_parent` where water meshes should render. |
| `WetSurfaceLifecycle` (`Node`) | Prepares startup coverage, supports staged initialization, and batches obstacle updates after physics registration. | Usually under `WetSurface2D`; assign `surface`, optional `presentation`, and the surface's `lifecycle`. |
| `WaterEmitter2D` (`Node2D`) | Applies a uniform dose over a footprint, continuously while active or through `emit_dose()`. | Under the watering tool or source; assign one destination `surface` and its `footprint`. |
| `WaterFootprint2D` (`Area2D`) | Defines the emitter's shape union and discovers wettable objects. | Usually under `WaterEmitter2D`; its `CollisionShape2D` / filled `CollisionPolygon2D` shapes **must be direct children**. |
| `WaterSpray2D` (`Node2D`) | Emits overlapping soft splashes in a hose cone, with obstacle checks and receiver wetting. An alternative to footprint emission. | Under the watering tool, at its floor-space outlet, with positive X pointing along the spray; assign `surface` and `receiver_scope` or explicit `receivers`. |
| `Wettable2D` (`Area2D`) | Gives an object retained wetness, ground absorption, drying, direct-water signals, and optional rigid-body traction. | Under the object/body; add a direct child collision shape for Area discovery and assign `surface`, `contact_point`, and `direct_point`. |
| `WettableTint2D` (`Node2D`) | Optionally darkens an object's artwork as its receiver gets wet. | Under the object, **wrapping its artwork**; assign `receiver`. |
| `WetRectangleCoverage2D` (`WetCoverageProvider2D` → `Node2D`) | Supplies a rectangular wettable region instead of deriving coverage from occupied tiles. | Usually under the surface or room; assign the surface's `coverage_provider` to it. `bounds` is in the provider's local coordinates. |
| `WetCoverageProvider2D` (`Node2D`, abstract) | Extension point for custom world-space coverage polygons and envelope. | Subclass it for a custom provider, place that instance under the surface or room, and assign `coverage_provider`. |
| `WetSurfaceSimulation` (`Node`, abstract) | Backend contract for custom deposition, sampling, and drying. | Subclass it instead of instantiating it; the concrete backend **must be a direct child** of its surface. |
| `WetSurfaceRow` (`MeshInstance2D`) | Internal water mesh for a rendering row/batch. | Created and managed automatically beneath `presentation_parent`; do not add manually. |

Example using tile coverage, a footprint emitter, and one wettable object:

```text
Room (Node2D)
├── Floor (TileMapLayer)
│   └── WetSurface (WetSurface2D)
│       ├── Simulation (WetGridSimulation)
│       ├── Presentation (WetSurfacePresentation, optional)
│       ├── Lifecycle (WetSurfaceLifecycle, optional)
│       └── Coverage (WetRectangleCoverage2D, optional alternative to tiles)
└── World (Node2D, y_sort_enabled = true)
    ├── WaterRows (Node2D, y_sort_enabled = true)
    │   └── [WetSurfaceRow meshes created at runtime]
    ├── WateringTool (Node2D)
    │   └── Emitter (WaterEmitter2D)
    │       └── Footprint (WaterFootprint2D)
    │           └── CollisionShape2D (CircleShape2D or RectangleShape2D)
    └── Crate (RigidBody2D)
        ├── CollisionShape2D (body collision)
        ├── GroundContact (Marker2D)
        ├── DirectWaterPoint (Marker2D)
        ├── Receiver (Wettable2D)
        │   └── CollisionShape2D (receiver Area shape)
        └── WetTint (WettableTint2D, optional)
            └── Sprite2D
```

Wire the example in the Inspector:

- On `WetSurface`, set `tile_layer = Floor`, `simulation = Simulation`, and the
  optional `presentation = Presentation` / `lifecycle = Lifecycle`. Leave
  `coverage_provider` unset for tile coverage; to use `Coverage` instead, assign
  it and configure its `bounds`.
- On `Presentation`, set `surface = WetSurface` and
  `presentation_parent = WaterRows`. On `Lifecycle`, set `surface = WetSurface`
  and `presentation = Presentation` when using the renderer.
- On `Emitter`, set `surface = WetSurface` and `footprint = Footprint`. Match
  `Footprint.collision_mask` to `Receiver.collision_layer` and enable monitoring
  on the footprint and monitorability on the receiver.
- On `Receiver`, set `surface = WetSurface`, `contact_point = GroundContact`,
  `direct_point = DirectWaterPoint`, and `obstacle_body = Crate`. Optionally set
  `footprint` to its Area collision shape and `traction_body = Crate` for floor
  drag when `WetSurface.traction_enabled` is enabled. On `WetTint`, set
  `receiver = Receiver`.

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
