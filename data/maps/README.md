# Exact source map and rendering data

`tools/export_maps.ts` executes the original Three map builders and serializes their BufferGeometry, linear colors, world transforms, instancing, original movement boxes, spawn pads, navigation graph, bounds, and authored terrain. The native loader reverses triangle winding for Godot; it retains coordinates and scale. Blender sources in `assets/maps` contain those same mesh objects.

| Map | Mesh instances | Unique geometry | Original boxes | Spawns | Navigation points |
| --- | ---: | ---: | ---: | ---: | ---: |
| desert_town | 258 | 118 | 81 | 27 | 471 |
| forest_facility | 718 | 85 | 66 | 27 | 472 |
| urban_docks | 183 | 96 | 66 | 27 | 648 |

`MapWorld.load_map(id)` constructs the map and environment. Public `spawn_points`, `nav_points`, `collision_boxes`, `bounds`, `environment_data`, and `height_at(x,z)` expose gameplay data. Physics layer 1 retains source locomotion boxes/terrain. Layer 2 contains all visible source triangles except outlines, matching bullets and equipment raycasts independently of locomotion. Shader foliage wind follows source elapsed time; foliage shadow geometry stays still because the source did not patch its shadow-depth material.

The source Game keeps the default Scene lighting across map changes; map-specific authored lighting was never applied. Exported `environment` reproduces this effective lighting, with `authoredLighting` retained separately. The shared toon shader reproduces the source Uint8 nearest-sampled ramp, hemisphere lighting, Three r180 ACES transform at exposure 1.05, and fog after display conversion. Godot Compatibility uses display-space EMISSION and linear DIFFUSE_LIGHT; these paths are intentionally different. Transient point lights use the source inverse-square cutoff and join radiance before ACES. At most 32 simultaneous point lights are supported.

`tools/export_vfx.ts` likewise exports the original spark, bullet hole, tracer, muzzle flash, explosion, smoke, molotov, and thermite mesh topology to `data/vfx.json`. `CombatVFX` preserves their palettes, sizes, timing, and the 96-decal recycling cap. Equipment models come from the Blender asset library.

`SourceShadow` reproduces the source's 2048px, 80m-wide orthographic camera, 0.5–200m depth range, world-space texel snapping, reversed face culling, 0.04m normal offset, -0.0005 depth bias, and Three PCFSoft sampling. It keeps shared-mesh proxies, rebuilds the caster list only when geometry enters/leaves, and updates animated transforms separately. Unchanged static scenes retain their depth texture.

Independent source/native depth captures at the same camera agree on 99.9966% of caster coverage. Median depth difference is 0.32mm over the 199.5m depth range; the 95th percentile is 12.4mm. The native pass stores 24-bit RGB depth rather than source RGBA packing, and raster precision still differs between renderers. Roof-edge speckles and occasional transparency ordering differ, so these measurements do not imply pixel identity.

A 1280×720 native Intel HD520 comparison with eight active bots measured 40.8fps (24.5ms/frame) with the source shadow pass, against 52.4fps (19.1ms/frame) with the optimized native fallback. These are local measurements with other desktop workloads present, not guaranteed performance. Browser reference captures used software WebGL, so their FPS is not directly comparable.

Validation scripts use the isolated runner so they do not overwrite the live Godot MCP registry, authentication, or application log:

- `python tools/run_check.py --script res://scripts/world/verify_maps.gd`
- `python tools/run_check.py --script res://tests/objectives_regression.gd`
- `python tools/run_check.py --script res://tests/actor_parity.gd`
- `python tools/run_check.py --script res://tests/equipment_vfx_regression.gd`
- `python tools/run_check.py --script res://tests/shadow_parity.gd`
- `python tools/run_check.py --graphical --script res://tests/snapshot_match.gd`
- `python tools/run_check.py --graphical --script res://scripts/world/snapshot_maps.gd`
- `python tools/run_check.py --graphical --script res://tests/snapshot_vfx.gd`
- `python tools/run_check.py --graphical --script res://tests/render_performance.gd`

Paired source/native screenshots are retained under `assets/maps/previews`: `source_match_*` / `match_*` (player camera), `source_*` / map-name PNGs (aerial camera), and `source_equipment_vfx.png` / `equipment_vfx.png`. The explosion center's measured source/native RGB matches exactly at `(238,167,83)` after correcting Compatibility emission conversion. Particle placement remains randomly generated as in the source.

Full-frame mean absolute RGB difference on the 0–255 scale, using matched 1280×720 captures:

| Map | Aerial camera | Player camera, including HUD |
| --- | ---: | ---: |
| desert_town | 0.211 | 1.408 |
| forest_facility | 0.184 | 1.296 |
| urban_docks | 0.124 | 1.387 |

The aerial camera is at `(0,20,50)` looking toward the origin; the player camera starts at `(-40,height_at(-40,0)+1.7,0)` facing along +X. HUD font rasterization and FPS text contribute to the player-view differences. These full-frame averages supplement visual inspection and the separate shadow-depth comparison; they do not establish pixel identity.
