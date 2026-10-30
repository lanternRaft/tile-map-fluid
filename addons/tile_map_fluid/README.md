# TileMapFluid components

Copy or symlink this folder into `addons/tile_map_fluid/` in a Godot 4.7 project, let the editor
import it, and run `demo/demo.tscn` with F6. It needs stock Godot physics only,
with no plugins, InputMap setup, or autoloads. Grow Stuff composes these components
through its room, tool, and cargo adapters in `effects/wetness/`.

The permanent [performance benchmark suite](benchmarks/README.md) lives inside
the addon and runs in an addon-only project with stock Godot physics. It covers
idle, deposits, drying, crowded contacts, uploads and coverage changes at matched
resolutions, with optional matched-baseline regression checks. Raw timings and
captures are written outside the addon source.

The demo starts dry. Aim with the mouse, hold left mouse/Space to water from
the green pump, move the receiver with WASD/arrows, and toggle lifted contact
with L. The wall blocks water and movement. Floor/object drying settings are
independent Resources (18s/7s in the demo); lift or move onto dry ground to
observe object drying. Tile cells, footprints, collision masks, controls, and
all references can be inspected and adjusted in the scene tree/Inspector.

## Composition

1. Add `WetSurface2D` under a vanilla `TileMapLayer`, assign `tile_layer`, and
   assign a dedicated `WetGridSimulation` child as `simulation`.
   For a floor assembled from several layers, assign `coverage_layers` directly.
   The coordinate layer may be empty; the addon reads occupied floor tiles, unions
   overlaps, and clips blocking collisions once per geometry change. Hosts need
   no room polygons or separate water-access masks.
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
   selects the room/layer; overlapping TileMapLayers are never searched. Use one
   provider to compose a room's layers, or route separate emitters explicitly.
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

## Optional presentation and movement

Add `WetSurfacePresentation`, assign `surface` and a host-owned Node2D as
`presentation_parent`. `WetSurfaceAppearance` configures texture, tint, and
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
independently of retained receiver saturation. The demo keeps movement speed
constant so it does not prescribe game tuning.

## Units and boundaries

Public positions are world pixels. Providers return world polygons and a stable
world envelope; surfaces convert these to layer-local coverage. Default tile
coverage supports rectangular stacked atlas cells, negative coordinates, and
finite invertible layer transforms. The optional `receives_water` TileSet custom
data must be boolean. Missing/empty metadata uses
`receives_water_by_default` (true); an explicit false tile stays dry. Tile
artwork offsets/flips do not change the full cell footprint. Partial collision
polygons, clipped boundaries, scene tiles, and other layouts require a
`WetCoverageProvider2D` adapter supplying simple filled pieces; absent pieces
represent holes. Providers notify after changing access or batched tile edits.

Call `refresh_coverage()` after batched `set_cell`/`erase_cell` operations or
changing coverage settings. Layer `changed` signals and provider notifications
also invalidate coverage. The backend retains unaffected water, clears removed
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

For staged initialization, prepare coverage with `refresh_coverage(Rect2(), false)`,
reset the backend with `reset(surface.settings, surface.tile_layer.global_transform)`,
and call `refresh_obstacles(row_world_bounds, false)` for each
frozen row. The second argument omits seam neighbors only while constructing a
previously empty immutable field. `reset()` clears geometry and water for a deliberate
room rebuild. `splash()` supplies a soft radius deposit for existing game tools;
ordinary footprint emission remains a union dose. All paths use the same field.

The simulation clips hard rectangle/convex physics shapes on
`WetSurfaceSettings.obstacle_mask`; zero uses supplied polygons alone. Refresh
coverage after moving barriers. Bodies with boolean `water_underpaint` metadata
keep supporting floor underneath them. Visibility rays can enter these bodies,
but cannot exit their far side or skip a second hard barrier. Unknown barrier
shapes and physics-query overflow fail closed. `maximum_cells` caps allocation;
only covered cells allocate contacts, even with distant disconnected islands.

`rate` means normalized saturation per second **at each** covered sample and
receiver; `emit_dose()` specifies an instant normalized dose. There are no liters
or footprint-area multipliers. Positive doses clamp to one, stored saturation
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
