# DeadShot — Godot edition

A native Godot port of DeadShot. The project keeps the source game's three maps,
18 selectable weapons, ten custom classes, five modes, equipment, perks,
scorestreaks and multiplayer relay protocol. Blender sources and exported GLB
models live in `assets/maps` and `assets/models`; gameplay and menus run in
GDScript without a Deno or Three.js runtime.

## Graphics

The port renders with a realistic material system rather than the original
cartoon cells. Each surface profile drives world-space triplanar detail and
normal maps, roughness, metalness, procedural weathering, upward dust
accumulation and vertical grime streaking on top of the map's exported base
tones, so the original art direction survives while picking up material
response. A procedural sky feeds reflected light, the sun casts real PSSM
shadows, and depth fog, SSAO, ACES tone mapping, glow and a filmic grade
complete the frame. Muzzle flashes, explosions and lamps are real `OmniLight3D`
sources rather than painted-on sprites, and the first-person weapon is lit by
its own camera-mounted rig so it reads as metal rather than a silhouette.

Exported outline hulls are dropped at import, and the ported single-orthographic
shadow camera has been replaced by the engine's shadow system. See
`scripts/world/map_material.gd` for the surface profiles and
`scripts/world/map_world.gd` for the environment.

### Geometry

Shading alone does not make a blockout read as a real object, so every
player-facing asset is rebuilt as detailed geometry rather than the stacked
boxes the ported export contained:

| Asset | Before | After |
| --- | ---: | ---: |
| Assault rifle (viewmodel) | 192 tris | 6 200 tris |
| Sniper rifle | 192 tris | 6 372 tris |
| Pistol | 168 tris | 2 442 tris |
| Soldier (each team) | 2 728 tris | 6 092 tris |
| Sentry turret | 2 452 tris | 1 496 tris |
| Recon UAV | 424 tris | 660 tris |

A rifle is assembled from its real sub-assemblies — receiver, bolt carrier and
charging handle, M-LOK handguard, gas block, barrel, muzzle device, iron sights,
rail, magazine, trigger group, pistol grip, buffer tube and stock — and a
soldier from a sculpted torso, plate carrier, pouches, helmet, goggles, gloved
hands, knee pads and boots. The maps gain the parapets, plinths, window frames,
glazing and downpipes the ported blockout omitted, and the authored props gain
their own detail — wheel arches, bumpers and lamps on every vehicle, cabin
glazing, lattice bracing and operator cabs on the cranes, pitched canopies over
the market stalls, curved reflectors on the radar dishes — without disturbing a
single authored collision box, spawn pad or navigation edge.

The models are generated procedurally in metres by `tools/deadshot_weapons.py`,
`tools/deadshot_characters.py` and `tools/deadshot_props.py` over the shared
`tools/deadshot_detail.py` mesh DSL, then exported through Blender exactly as
the ported assets were. `assets/models/source/README.md` documents the pipeline,
the named animation pivots each builder preserves, and how to regenerate.
`tools/snapshot_assets.gd` renders every asset through the real material system
to `assets/models/previews_*.png` for review.

The map detail pass is `tools/deadshot_enrich_maps.py`; it is purely additive, so
`MapWorld` still builds the same world and the exported gameplay data is
unchanged.

### Graphics quality

**OPTIONS → GRAPHICS** selects **Low**, **Medium**, **High** (default) or
**Ultra**. The choice is stored as `settings.graphics` in the save file and
applies live, without restarting a match. Each tier is one preset in
`scripts/world/graphics_quality.gd`:

| | Low | Medium | High | Ultra |
| --- | --- | --- | --- | --- |
| Surface projection | planar | planar | triplanar | triplanar |
| Normal map | off | off | on | on |
| Weathering map | off | on | on | on |
| Screen-space AO | off | off | on | on |
| Glow | off | on | on | on |
| Sun shadow cascades | 1 | 1 | 2 | 4 |
| MSAA | off | off | 2x | 4x |
| 3D render scale | 0.8 | 0.9 | 1.0 | 1.0 |
| Noise texture resolution | 128 | 256 | 256 | 512 |
| Concurrent VFX lights | 2 | 4 | 8 | 12 |
| Viewmodel fill and rim | off | off | on | on |

The surface shader carries `QUALITY_*` markers that each tier strips before
compiling, so a low-tier fragment shader genuinely skips the three-plane
projection, the normal rebuild and the weathering lookup instead of sampling
them and discarding the result. `tests/graphics_quality_test.gd` measures every
tier and asserts the ordering, the stripped work, and that switching tier
mid-match rebuilds the live materials.

The test disables vsync, isolates render work from bot simulation, and measures
at 2560x1440 with the fastest of several timing batches per tier. Every tier
renders comfortably above the 60 Hz present interval, so with vsync on all four
levels measure as 60 fps and the ordering assertion ends up testing the refresh
rate instead of the tier's cost. Ticking the match inside the timed loop let the
eight bot planners' shared CPU cost dominate the wall clock, and at 1280x720 the
tiers differ by single-digit percent, which is inside run-to-run noise; measuring
presentation only, at four times the pixel count, scales the work each tier
actually controls and turns that difference into a margin several times the
noise. The draw-call and shader-variant assertions confirm which work each tier
paid for. Absolute figures vary with machine load, so the test asserts the
ordering rather than fixed numbers.

## Play and develop

Use Godot 4.7.2 or a compatible Godot 4.7 installation. The project uses the
Compatibility renderer. Open `project.godot` in the editor, then press F6/F5, or:

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
