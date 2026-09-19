# DeadShot — Godot edition

A native Godot port of DeadShot's cartoon FPS. The project keeps the source game's
three maps, 18 selectable weapons, ten custom classes, five modes, equipment,
perks, scorestreaks and multiplayer relay protocol. Blender sources and exported
GLB models live in `assets/maps` and `assets/models`; gameplay and menus run in
GDScript without a Deno or Three.js runtime.

## Play and develop

Use Godot 4.7.2 or a compatible Godot 4.7 installation. The project uses the
Compatibility renderer. Open `project.godot` in the editor, then press F6/F5, or:

```sh
godot --path .
godot --path . --editor
```

Choose **PLAY** to configure map, mode, bots, difficulty, class, hardcore and
killcam. **CREATE-A-CLASS** edits any of ten saved loadouts; changes save
immediately. **OPTIONS** controls sensitivity, FOV, volume, invert Y and killcam.
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
python tools/run_check.py --script tests/pause_controls_test.gd
python tools/run_check.py --script tests/net_relay_test.gd
python tools/run_check.py --script tests/network_lobby.gd
python tools/run_check.py --graphical --script tools/ui_snapshot.gd
```

The UI checks instantiate every screen and verify real settings/class controls,
save import/export, overlay transitions and touch cleanup. Network checks open
real local WebSockets and verify all message types, room isolation, authority,
host transfer and clean disconnects. UI snapshots default to `/tmp/deadshot-ui`.
Additional gameplay, assets and replay checks live in `tests/`. The check runner
uses an isolated application name and disables MCP in the test process, keeping
the live editor connection and player saves intact.
