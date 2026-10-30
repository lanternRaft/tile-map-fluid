# TileMapFluid components

Copy or symlink this folder into `addons/tile_map_fluid/` in a Godot 4.7 project, let the editor
import it, and run `demo/demo.tscn` with F6. It needs stock Godot physics only,
with no plugins, InputMap setup, or autoloads. Grow Stuff composes these components
directly in its room, tool, and cargo scenes.

The permanent [performance benchmark suite](benchmarks/README.md) lives inside
the addon and runs in an addon-only project with stock Godot physics. It covers
idle, deposits, drying, crowded contacts, uploads and coverage changes at matched
resolutions, with optional matched-baseline regression checks. Raw timings and
captures are written outside the addon source.

The demo starts dry. A fixed-range particle stream lands ahead of the character;
the C-shaped wall blocks spray from every side. The static mushroom and pushable
rigid-body crate have independent wetness tints. The all-wet performance button
saturates the floor and objects, pauses drying until stopped, and resets the live
FPS, average FPS, worst frame time, and draw-call readout.

Aim with the mouse, hold left mouse/Space to water from
the character’s handheld sprayer, move with WASD/arrows, and toggle lifted contact
with L. The wall blocks water and movement. Floor/object drying settings are
independent Resources (18s/7s in the demo); lift or move onto dry ground to
observe object drying. Tile cells, footprints, collision masks, controls, and
all references can be inspected and adjusted in the scene tree/Inspector.

## Composition

1. Add `WetSurface2D` under a vanilla `TileMapLayer` and assign `tile_layer`.
   Surface automatically creates its simulation and renderer; configure visuals
   through `appearance`. An explicitly assigned simulation must be a dedicated child.
   The addon reads occupied tiles from the assigned layer and clips blocking
   collisions once per geometry change. Hosts need no room polygons or separate
   water-access masks.
   Surface coordinates always belong to the referenced layer, including when the
   component node itself is offset. Runtime saturation belongs to that child;
   TileSet, TileData, textures, and settings remain shared configuration.
2. Assign a `WaterFootprint2D` Area to `WaterEmitter2D`. Author direct child
   circle/rectangle CollisionShape2Ds or filled CollisionPolygon2Ds (a triangle
   or wider polygon makes a hose cone). Enabled shapes form a union. Floor
   backends visit their own samples and test `contains_world_point()`, once per
   sample per stamp; floor tiles need no Areas. Discovery is a broad phase:
   the receiver's direct-water marker must lie inside the union.
3. Assign exactly one destination `surface` on the emitter. The composition root
   selects the room/layer; overlapping TileMapLayers are never searched. Route separate emitters explicitly for separate surfaces.
4. Add `Wettable2D` Areas to objects and assign the same surface. Their monitorable
   collision layer must match the footprint's monitoring mask. Explicit emitter
   `receivers` also support shape-free objects; duplicates across both discovery
   paths receive one dose. A null-surface receiver requires explicit registration
   on a null-surface emitter. Separate World2Ds cannot exchange water.
5. Choose ground and direct-water markers explicitly. Disable contact through
   `set_contact_enabled(false)` while lifted, carried, or on a countertop; direct
   hits still work. `changed`/`water_added` support signal-only reactions. Optional
   presentation and movement adapters can consume saturation without coupling
   wet fur to ground traction.

## Surface rendering and movement

For the game's hose behavior, add `WaterSpray2D` directly to the tool scene and
assign `surface`, `receiver_scope`, and a scene-local `WaterSpraySettings` Resource.
Position it at the floor-space outlet and point its positive X axis along the spray.
`active` emits continuously using scaled physics time. Hosts advancing it manually
must disable its automatic physics processing. Configure the dose rate, cone,
splash spacing, growing radii, and obstacle mask in the Inspector. Shared
`WaterSprayGeometry` checks also support plant-care targeting; water delivery
does not perform care or consume supplies.

This spray intentionally adds overlapping soft splashes rather than a uniform
union stamp. Denser sampling increases saturation. Each splash radius grows with
local saturation; the grid resolution still limits the apparent edge precision.
Grounded receivers with a `footprint` accept center/nearest-axis shape probes;
receivers with disabled contact use their direct marker. Assign `obstacle_body`
explicitly so the receiver's own collider may be the final ray hit. Scope candidates
and explicit `receivers` are deduplicated, and only the assigned surface's receivers
in the same physics world receive water.

Surface automatically creates its simulation and renderer. Configure visuals with
`WetSurface2D.appearance`; water rows join the nearest Y-sorted ancestor.
Existing manually composed scenes can still place `WetSurfacePresentation` in the world and assign
`surface`. It owns its mesh rows directly and enables Y sorting. `WetSurfaceAppearance` configures texture, tint, and
upload interval. It supports `WetGridSimulation`; another backend can supply
its own presenter using `changed`. `refresh()` uploads immediately; `rebuild()`
applies changed appearance settings without rebuilding simulation or physics.
Assign any ordinary imported SVG or raster `Texture2D`; the renderer uses its
existing Godot texture without runtime SVG conversion. Full and clipped patches
share combined triangle meshes, one material, a static patch-contact table and a
bulk-updated float32 saturation texture. Explicit contact indices preserve barriers
and newly exposed dry seams; rectangular texture filtering cannot connect them.
Only changed ordering bands replace geometry. Neither visuals nor saturation
updates modify TileSet physics. Dry fields hide their meshes and stop uploading
after the final clearing update. `diagnostics()` exposes storage/resource counts
and upload totals; `field_uploaded` announces actual visual uploads.

Row anchors use the layer's local Y lattice, transformed into the explicit
parent. For physical sorting, put the parent in the host's Y-sorted world with
Y sorting enabled on organizational containers; rows remain atomic at relative
Z=0. Keep dry floor art behind that band. A dedicated ground band is also
possible when the host deliberately renders all water beneath its objects. In an
atomic parent, `appearance.rows_per_batch` can combine multiple rows; Y-sorted
parents always retain individual row anchors. Staged hosts can disable
`automatic_updates` and call `refresh()` after preparing each simulation region,
then enable automatic updates when initialization is complete.
Rotated layers retain accurate geometry; local-Y slices do not provide global-Y
occlusion for arbitrary rotated tall artwork. The host owns that sorting policy.

For optional object darkening, place artwork under a dedicated `WettableTint2D`
wrapper and assign its `receiver`. It multiplies its authored `modulate` by a
wetness factor and restores it when dry or removed. It never edits shared
materials, child colors, or parent effects. Reserve this wrapper's modulation
for wetness; animate unrelated effects on its parents/children. Signal-only
receivers need no wrapper. Tint is visual and has no effect on floor traction.

Movement adapters sample `surface.saturation_at(world_contact)` and blend their
own acceleration/braking/damping policy. Use the floor sample for traction,
independently of retained receiver saturation. The demo reduces acceleration and braking on wet ground so the character slides.
Its tuning is demo-specific.

For rigid-body floor drag, enable `surface.traction_enabled` and configure
`wet_drag_multiplier` and `traction_affects_rotation` on the surface. Assign a
receiver's `traction_body` to opt into automatic damping. Contact loss, dry ground,
surface changes, and removal restore the body's dry damping. Leave `traction_body`
unset when a host carrying/movement component owns damping; it can multiply its
current dry damping by `surface.traction_multiplier(receiver.surface_saturation)`.

## Units and boundaries

Public positions are world pixels. Coverage comes from the assigned TileMapLayer
in layer-local coordinates. Tile coverage supports rectangular stacked atlas cells,
negative coordinates, and
finite invertible layer transforms. The optional `receives_water` TileSet custom
data must be boolean. Missing/empty metadata uses
`receives_water_by_default` (true); an explicit false tile stays dry. Tile
artwork offsets/flips do not change the full cell footprint. Scene tiles and other tile layouts are unsupported. Blocking collision polygons
clip the wettable tile coverage independently of artwork.

Call `refresh_coverage()` after batched `set_cell`/`erase_cell` operations or
changing coverage settings. Layer `changed` signals also invalidate coverage. The backend retains unaffected water, clears removed
coverage, and initializes added coverage dry. Unchanged clipped patches keep their
water even when the envelope changes; shrinking a patch resamples its surviving
water, while newly exposed patches start dry. The lattice defaults to layer-local
zero; `sample_origin` retains a host's existing grid anchor. Newly exposed floor
has separate dry contacts at retained wet seams. Invalid coverage clears storage, so fixing it cannot restore
stale water. Changing spacing resets the field.

Point queries use cached containing-cell pieces, including for custom backends;
receiver cost does not grow with total floor area. After moving or toggling blocking
colliders, call `surface.refresh_obstacles(world_bounds)`. Empty bounds refresh
the full sparse field; a bounded refresh retains distant patch identities and
reuses released contacts. It does not rescan floor tiles. A door blocks water through
its collision mask, independently of a game's navigation or logical access state.

The reusable `wet_surface.tscn` composes a surface, coordinate layer, grid backend,
presentation, and `WetSurfaceLifecycle`. Assign the tile layer, receiver
scope, and appearance. New surfaces manage renderer placement automatically. The lifecycle refreshes
startup obstacles after physics registration and batches `request_obstacles(world_bounds)`
notifications at that same safe boundary. Empty bounds mean a full refresh.
Set `lifecycle.staged` before tree entry for a frozen host, then call
`advance_initialization()` until it returns true. Each step prepares one lattice row;
automatic evaporation stays suspended until completion. `lifecycle.rebuild()` clears
water and restarts preparation. `anchor_to_coverage` optionally anchors the lattice
to the initial envelope; otherwise `settings.sample_origin` remains authoritative.
Low-level hosts can still prepare coverage with `refresh_coverage(Rect2(), false)`,
reset the backend, and call `refresh_obstacles(row_world_bounds, false)` themselves.
Only omit seam neighbors while constructing a previously empty immutable field.

`surface.splash(world_point, dose)` supplies a soft deposit using the surface's
`splash_initial_radius` and `splash_maximum_radius`; ordinary footprint emission
remains a union dose. `WetSurfaceMetrics` exposes read-only lattice/occupancy diagnostics.

The simulation clips hard rectangle/convex physics shapes on
`WetSurfaceSettings.obstacle_mask`; zero uses supplied polygons alone. Refresh
coverage after moving barriers. Bodies with boolean `water_underpaint` metadata
keep supporting floor underneath them. Visibility rays can enter these bodies,
but cannot exit their far side or skip a second hard barrier. Unknown barrier
shapes and physics-query overflow fail closed. `maximum_cells` caps allocation;
only covered cells allocate contacts, even with distant disconnected islands.

`rate` means normalized saturation per second **at each** covered sample and
receiver; `emit_dose()` specifies an instant normalized dose. There are no liters
or footprint-area multipliers. Positive saturation increments clamp to one, stored saturation
clamps to [0, 1], and non-finite/nonpositive doses or time steps are ignored.
Point deposits wet their containing interpolation patch. Footprints test the
exact union against contacts; a footprint smaller than a sample gap wets its
intersected patch so small splashes remain usable at 32 pixels. This preserves
coarse interpolation, rather than promising exact footprint edges below the
sample spacing. Overlapping shapes never add multiple doses to one contact.

Drying uses seconds; zero drying time disables it. Continuous emission advances
on scaled physics delta and stops immediately when inactive. Manual `advance()`
is for explicit host clocks/testing; disable automatic physics processing when
using it. Host tools alone consume supply and perform plant care.

Solid-body ray masks and source-body exclusions are explicit emitter settings.
Receiver Areas do not intercept floor water; an optional receiver body may be
the final ray hit. Wetting receivers and floors is independent, and ground
absorption does not drain the floor. Backend implementations use
`WaterVisibility2D` for the same obstruction contract.

Bundled SVGs/shaders are first-party: the water SVG/shader were extracted from
Grow Stuff, and the demo SVGs were authored for this addon. No third-party art
or additional asset attribution is required.

Receivers may opt into `automatic_surface`; assign each surface's `contact_scope`
to the ancestor containing its receivers. Discovery selects the nearest scope in
the same physics world and follows reparenting. Explicit surfaces remain the default.
`contact_required_paths` and `contact_blocked_paths` read indexed public properties
relative to the receiver to configure contact without a host-specific subclass.
An optional `artwork` reference uses `WettableSettings.object_tint` and preserves
other modulation effects. `report_full_dose` defaults to reporting full direct doses to signal consumers
while saturation still clamps; disable it to report doses clamped to one.
