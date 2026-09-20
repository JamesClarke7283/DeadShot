# DeadShot — Godot edition

A native Godot port of DeadShot. The project keeps the source game's three maps,
18 selectable weapons, ten custom classes, five modes, equipment, perks,
scorestreaks and multiplayer relay protocol. Blender sources and exported GLB
models live in `assets/maps` and `assets/models`; gameplay and menus run in
GDScript without a Deno or Three.js runtime.

## Graphics

The port renders with a realistic material system on **Forward+** rather than
the original cartoon cells. Each surface family generates its own procedural
albedo, normal, roughness and height maps — wind-rippled sand, aggregate
concrete, growth-ringed timber, woven cloth — and a parallax occlusion march
displaces each sample through that height field, so surfaces read as material
rather than as a picture of material. Procedural weathering, upward dust
accumulation and vertical grime streaking sit on top of the map's exported base
tones, so the original art direction survives while picking up real material
response. A procedural sky feeds both ambient and reflected light, the sun casts
real PSSM shadows, and screen-space ambient occlusion and indirect light, voxel
global illumination, screen-space reflections, volumetric fog, depth fog, ACES
tone mapping, glow and a filmic grade complete the frame. Muzzle flashes,
explosions and lamps are real `OmniLight3D` sources rather than painted-on
sprites, and the first-person weapon is lit by its own camera-mounted rig so it
reads as metal rather than a silhouette.

Exported outline hulls are dropped at import, and the ported single-orthographic
shadow camera has been replaced by the engine's shadow system. See
`scripts/world/map_material.gd` for the surface profiles and
`scripts/world/map_world.gd` for the environment.

### Graphics quality

**OPTIONS → GRAPHICS DETAIL** is a single continuous **0–100** slider: raise it
for looks, lower it for frame rate. Four named bands sit at anchors along it and
the **PRESET** row jumps the slider to one of them:

| | detail 0 (Low) | 33 (Medium) | 66 (High, default) | 100 (Ultra) |
| --- | --- | --- | --- | --- |
| Surface projection | planar | planar | triplanar | triplanar |
| Normal map | off | off | on | on |
| Weathering map | off | on | on | on |
| Parallax occlusion | off | off | on | on |
| Screen-space AO | off | off | on | on |
| Screen-space indirect light | off | off | on | on |
| Screen-space reflections | off | off | on | on |
| Voxel global illumination | off | off | off | on |
| Volumetric fog | off | off | on | on |
| Glow | off | on | on | on |
| Sun shadow cascades | 1 | 1 | 2 | 4 |
| MSAA | off | off | 2× | 4× |
| FXAA / TAA | off / off | FXAA / off | off / off | off / on |
| 3D render scale | 0.8 | 0.9 | 1.0 | 1.0 |
| Detail texture resolution | 128 | 256 | 256 | 256 |
| Concurrent VFX lights | 2 | 4 | 8 | 12 |
| Viewmodel fill and rim | off | off | on | on |

The choice is stored as `settings.graphicsDetail` and applies live, without
restarting a match. Continuous quantities — shadow distance and blur, render
scale, grain contrast, normal and parallax strength, SSAO/SSIL/SDFGI energy,
volumetric density, viewmodel detail — interpolate between neighbouring anchors,
so dragging the slider gives a graded cost curve rather than four cliffs.
Discrete features (a shader block, a lighting pass, a light budget) stay at the
lower anchor and switch on once the slider reaches the band that owns them,
which is also what holds the shader variant count at four instead of a recompile
per slider step.

An `HSlider` emits `value_changed` continuously while dragged, and a detail
change rebuilds every world material. The viewport half of the change (MSAA,
render scale, shadow atlas) tracks the slider immediately; the material rebuild
waits for a 150 ms quiet period, so a drag does not recompile the world's shader
variants once per pixel of travel.

The surface shader carries `QUALITY_*` markers that each band strips before
compiling, so a low-band fragment shader genuinely skips the three-plane
projection, the normal rebuild, the weathering lookup and the parallax march
instead of sampling them and discarding the result.

`tests/graphics_quality_test.gd` verifies the ordering and each band's
configuration — the fastest-of-several-batches frame time rises monotonically
from Low to Ultra, the viewport, shadow, ambient-occlusion and indirect-light
settings match the preset, the stripped shader really lost the work, and
switching band mid-match rebuilds the live materials without dropping the
player out of the match. It is an ordering and configuration check, not a
throughput claim: on a fast GPU the absolute figures are dominated by CPU frame
submission, so they read in the hundreds of fps and should not be quoted as
achieved frame rates.

#### Renderer

The project renders with **Forward+**, which is what makes the screen-space and
global-illumination passes above real. Under the Compatibility renderer those
settings exist in the `Environment` resource but are silently ignored, so the
scene read as flat: no ambient occlusion, no bounce light, no volumetric light
shafts. `GraphicsQuality.advanced_lighting_supported()` reports the renderer, and
the environment and ambient are authored against which one is active — the Web
preset stays on Compatibility, so it keeps the explicit colour ambient and the
higher exposure that renderer needs.

Lighting is energy-conserving: ambient is taken from the sky (so the map's own
palette drives the colour cast and the ambient tracks SDFGI's bounce rather than
fighting it), the sun uses its exported intensity directly, and exposure is
calibrated by measurement — rendering the reference viewpoint across a range put
mean frame luminance at 0.23 for 0.08, 0.44 for 0.18 and 0.54 for 0.25 with no
clipping, so the exterior sits near a 0.45 mean, where an ACES-graded daylight
exterior belongs.

Volumetric fog's injection terms matter as much as its density. Feeding the
scene's ambient and sky radiance back into the medium lit the volume from every
direction, which washed the frame flat — the far and sky band measured 0.476
luminance with the volume against 0.210 without it, while the sun's own
contribution was invisible underneath. Real haze scatters mostly the sun, so
`volumetric_fog_gi_inject` is off, ambient and sky injection are near zero, and
the density is low: the arenas are daylight exteriors. The volume now adds
modest distance haze (far band 0.337 against 0.210 clear) with the foreground
untouched, instead of a white-out.

The cloud deck is deliberately static. Godot caches the sky's radiance cubemap
only while the sky shader is time-invariant, and since that cubemap feeds
ambient, reflections and SDFGI's sky light, drifting the clouds with `TIME`
forced a full radiance re-render every frame — measured at roughly five times
the frame cost of an entire low band. A stable sky is also the better read in a
shooter where the horizon is a sightline.

#### Surfaces

Every surface family generates its own procedural maps rather than sharing one
noise field: sand is wind-rippled, concrete is aggregate in cement, asphalt is
graded aggregate, wood is growth rings plus pores along the grain, fabric is a
plain warp/weft weave, foliage is leaf lobes, rust is pitted flaking steel, stone
is chiselled blocks with eroded mortar, and machined metal is a fine isotropic
brush. A family's single height field is authored once and everything else
derives from it — the normal map is that field converted to tangent space, and
the parallax occlusion march reads the field directly — which is what keeps
displacement and shading consistent instead of merely correlated. See
`scripts/world/surface_library.gd` for the generators and
`scripts/world/map_material.gd` for the per-family profiles and parallax depths.

Two further terms keep a surface from reading as one painted panel. Each family
also carries an **albedo hue variation**: two decorrelated low-frequency fields
and a patch mask drift a wall's own tint between two colour casts, so concrete
varies panel to panel, render is patched, and asphalt has old and new repairs.
Grain alone only moves brightness within a tile, which leaves every panel the
same colour however it is lit. Families whose authored palette must survive —
skin, glass, team tints, camo — are deliberately absent and get no variation.

The grain is sampled at **two widely separated scales** and blended. A single
projection at one scale makes its tile period legible from a few metres away, and
adding octaves inside that tile cannot fix it, because the repeat is the problem
rather than the detail. The second scale is offset and rotated so its tile
boundaries never line up with the first.

Generation is off the frame budget: a shared seamless-noise bank is synthesised
once per resolution and reused by every family, the family is resolved to an
integer once outside the pixel loop, and fields are cached per (family,
resolution) and generated on first use, so a match pays only for the families it
places. The first per-pixel formulation matched on the family *string* inside
the loop and took 24 s at 1024², which was a visible freeze; the current one
generates a family in ~72 ms and is capped at 256 texels, the point past which
the extra detail stops being resolvable at these tiling rates.

#### Geometry

Shading alone does not make a blockout read as a real object, so every
player-facing asset is rebuilt as detailed geometry rather than the stacked
boxes the ported export contained. Each surface supplies what the lighting needs
to resolve: true silhouette (chamfers and bevels rather than sharp box edges),
separation between adjacent volumes (recessed panel lines), and small proud
features (screws, rivets, stitches, buckles) that catch a highlight — 1 646 904
triangles across the 138 models, plus 105 170–146 994 of additive detail per map.

Two integration defects are worth recording because they were invisible to
reasoning and obvious on screen. The trees' limbs were shaded with the painted
metal trim material and their leaf mass with the bark material, so branches read
as reflective rods and canopies as dark woody blotches; limbs now share the
trunk's wood and the lobes have their own `foliage` material with the leaf-lobe
height field and backlight transmission. And a canopy detail pass only *looked*
like it covered its authored volume: the authored box canopy's corners still
protruded, because a lobe layout solved against an inscribed sphere cannot enclose
a box. It is now solved and tested analytically — every authored canopy vertex
against every lobe as a sphere, no rasterisation, so overlapping lobes cannot make
a parity test report a false pass — with the lobe radii also required to cover the
rendered faceted mesh, which falls short of its own analytic surface.

The models are generated procedurally in metres by `tools/deadshot_weapons.py`,
`tools/deadshot_characters.py` and `tools/deadshot_props.py` over the shared
`tools/deadshot_detail.py` mesh DSL, then exported through Blender exactly as
the ported assets were. The map detail pass is `tools/deadshot_enrich_maps.py`;
it is purely additive, so `MapWorld` still builds the same world and the
exported gameplay data — collision boxes, spawn pads and the navigation graph —
is unchanged.

## Play and develop

Use Godot 4.7.2 or a compatible Godot 4.7 installation. The project uses the
**Forward+** renderer; the Web preset falls back to Compatibility. Open
`project.godot` in the editor, then press F6/F5, or:

```sh
godot --path .
godot --path . --editor
```

Choose **PLAY** to configure map, mode, bots, difficulty, class, hardcore and
killcam. **CREATE-A-CLASS** edits any of ten saved loadouts; changes save
immediately. **OPTIONS** controls sensitivity, FOV, volume, invert Y, killcam and the graphics tier.
Import/export buttons transfer the versioned JSON save, including the browser's
`localStorage["deadshot.save"]` JSON format. Native saves are written atomically
to Godot's `user://deadshot.save.json`.

Death refills every carried weapon and resets scorestreak progress for the next
life. Deployed streaks finish normally, and match scoreboard totals are retained.

## Controls

| Action | Keyboard/mouse |
| --- | --- |
| Move / look | WASD or arrows / mouse |
| Fire / aim | Left / right mouse |
| Raise stance / crouch | Space / Ctrl or C |
| Lower stance / sprint forward | Shift while stationary / Shift while moving forward |
| Reload / interact | R / E |
| Primary / secondary / cycle | 1 / 2 / mouse wheel |
| Melee | K |
| Lethal / tactical | G / Q; hold then release to charge frag grenades / flashbangs |
| Scorestreak selector | Hold Z, then 1–3 |
| Scoreboard / pause | Hold Tab / Escape |
| Skip replay / fullscreen | Space / F11 |
| Developer console | Backquote |

Xbox-style pads use left stick movement and right stick aim; RT/LT fire/aim;
A raises stance; X reload; RB/LB lethal/tactical; L3 lowers stance or sprints;
Y streaks; Back scoreboard;
Start pause. Touchscreen devices get a left joystick, right look pad and action
buttons. The first connected pad is used; idle pads do not override the keyboard.
Open **Escape → CONTROLS** for the full keymap, including current keyboard
bindings, controller buttons and touch controls. The guide keeps the match
paused. Frag grenades and flashbangs charge for up to 1.25 seconds before release;
their fuse starts when thrown. Other equipment activates on a press.

## Multiplayer

Use **MULTIPLAYER** to host or join a room. The native relay uses the same plain
JSON WebSocket protocol as the browser edition, so compatible clients can share
a relay. The host chooses settings and owns bot simulation; each client owns its
player. A standalone relay does not require Deno:

```sh
godot --headless --path . --script scripts/server/relay_main.gd -- --port=8090
```

Connect to `ws://127.0.0.1:8090/ws` on the same machine, or replace the hostname
with the relay machine's reachable LAN address. The first player in a new room
becomes host; when the host leaves, the next player becomes host.

## Export

Install export templates matching the editor version. Linux and Windows presets
are included and package the JSON gameplay tables and Blender-exported GLBs;
source `.blend` files, conversion tools, tests and comparison screenshots are
excluded.

```sh
python tools/build_release.py Linux
python tools/build_release.py Windows
```

Distribute each executable together with its adjacent `DeadShot.pck` and
`licenses` directory. Linux can
launch `./builds/linux/DeadShot.x86_64`; no Godot editor is required.
The build script copies the project and import cache before invoking Godot,
disables editor-only MCP hooks in that copy, and preserves the game's application
name. Export logs are saved under `builds/logs`.

A Web preset is provided for the browser target. Matching Godot Web export
templates are installed in this workspace. Export with:

```sh
python tools/build_release.py Web
```

Serve that directory over HTTP. Browser pointer capture requires clicking the
game, and the browser client joins a native/remote WebSocket relay rather than
hosting a TCP server itself.

Noto Sans, Noto Sans Mono and Noto Sans Symbols 2 are bundled so browser and
desktop builds retain the same typography. Their SIL Open Font License notices
are in `assets/fonts` and copied beside release files.

## Verification

```sh
python tools/run_check.py --script scripts/ui/verify_ui.gd
python tools/run_check.py --script tests/input_gamepad_test.gd
python tools/run_check.py --script tests/input_console_test.gd
python tools/run_check.py --script tests/screen_effects_test.gd
python tools/run_check.py --script tests/graphics_settings_test.gd
python tools/run_check.py --graphical --script tests/graphics_quality_test.gd
python tools/run_check.py --script tests/detail_slider_test.gd
python tools/run_check.py --script tests/pause_controls_test.gd
python tools/run_check.py --script tests/net_relay_test.gd
python tools/run_check.py --script tests/network_lobby.gd
python tools/run_check.py --script scripts/world/verify_maps.gd
python tools/run_check.py --script tools/blender_verify_models.gd
python tools/run_check.py --graphical --script tools/snapshot_assets.gd
python tools/run_check.py --graphical --script tools/ui_snapshot.gd
```

The UI checks instantiate every screen and verify real settings/class controls,
save import/export, overlay transitions and touch cleanup. Network checks open
real local WebSockets and verify all message types, room isolation, authority,
host transfer and clean disconnects. UI snapshots default to `/tmp/deadshot-ui`.
Additional gameplay, assets and replay checks live in `tests/`. The check runner
uses an isolated application name and disables MCP in the test process, keeping
the live editor connection and player saves intact.
