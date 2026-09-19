# DeadShot Godot migration

The Godot edition lives on `main`; the original Three.js/Deno edition is retained on
`old-threejs` as the behavioural and visual reference. Conversion tools use a sibling
checkout of that branch at `../DeadShot`. The migration goal is full feature and visual parity.

## Verification ledger

Completion requires working native Godot implementations and runtime/visual evidence for every row.
An exported table or a parse check alone does not prove a feature works.

| Area | Required parity | Status |
|---|---|---|
| Maps | Desert Town, Forest Facility, Urban Docks; all meshes, props, terrain, spawns, cover, navigation | Native geometry exported; all 15 map/mode combinations simulate successfully; matched camera screenshots available |
| Blender models | Editable .blend sources and imported character, weapon, attachment, equipment/streak assets matching original geometry/colors | 138 assets; Blender hierarchy/material/transform/bounds round-trip verified within 0.1 mm |
| Rendering | Realistic material response, atmosphere, shadows, screen effects | Rebuilt as a realistic renderer: procedural sky driving ambient/reflection, real four-cascade PSSM sun shadows, SSAO, depth fog, ACES tone mapping, glow and a filmic grade; world-space triplanar detail/normal/weathering per surface profile; exported outline hulls dropped; map geometry parity re-verified after the outline pass (177/655/111 meshes); screen-effect fixtures retained; selectable Low/Medium/High/Ultra tiers strip the shader per level and scale AO, glow, cascades, MSAA and render scale (low renders roughly twice the frame rate of ultra on Intel HD 520; the tier benchmark asserts the ordering every run) |
| Player | Look, movement, sprint, crouch/prone, ADS, swapping, melee, interactions, health/regen/hardcore | Implemented; 14 actor checks and 16 match lifecycle checks pass, including typed paths, suicide scoring, pickup expiry and input-driven weapon exchange |
| Weapons | 18 firearms + knife; exact balance, fire modes, recoil, reload, pellets, rockets, attachments/camo | 13,777 source-derived checks pass for all 19 weapons, trigger/burst/reload/recoil/pellets/rockets and viewmodel animations |
| Bots | All difficulty settings, A* navigation, target selection, real combat, melee, respawn | Eight-bot 60-second combat regression passes; every map/mode smoke test has moving bots |
| Modes | TDM, FFA, Domination, CTF, Gun Game with scoring and victory conditions | Objective regression covers 29 source cases; all combinations run; TDM/FFA actual 100th kill, TDM draw, and Gun Game tiers/melee downgrade/bot cap/knife victory pass |
| Equipment | Flash, smoke, stun, snapshot, frag, semtex, knife, C4, molotov, thermite, claymore | Equipment/VFX regression passes; 37 charged-throw checks cover hold/release, distance, walls and cancellation; paired live-render fixtures retained |
| Scorestreaks | All 12 automated streaks, per-life score meter, selection, bots, care packages | Behavior tests pass; real Main/Match verifies Z+slot, HUD, UAV/jamming, console grants and nuke result transition |
| Menus | Main/options, pre-match, ten classes, attachments/camo/perks/streaks, pause/post-match | Native menus and actionable controls verified; post-match presentation aligned; bundled fonts preserve browser typography; Escape controls guide integration passes |
| HUD | Ammo, health, minimap, score/timer, killfeed, damage/hit indicators, scoreboard, objectives | Connected to live gameplay; matched-camera comparisons and source colors/layout verified; charged-throw power shown while holding |
| Persistence | Original defaults and save migration, ten classes, settings, last-match options | Disk round-trip and partial/corrupt browser JSON tests pass |
| Replays | Killcam, best play, timing/interpolation and replay UI | Recorder/camera source tests and real Main/Match death/skip/respawn/disabled killcam/best-play/result visibility tests pass |
| Networking | Lobby, host settings, ready/start, snapshots, remote actors/damage, disconnection | Native transport, original relay compatibility, two-player match, and UI lobby integration tests pass; death-reset ownership verified |
| Audio | Gunfire, reload, spatial FX, footsteps, adaptive music and volume controls | 55 source-synth WAVs and real Main/Match audio hooks verified, including exact explosion sizes, attenuation and music transitions; native HRTF/filter and recorded-loop differences documented |
| Input | Keyboard/mouse, controller, touch, fullscreen, console | Keyboard/mouse, digital controller movement and touch joystick verified; console isolation and Escape controls navigation pass |
| Packaging | Standalone Godot launch/export and instructions; no Three.js runtime dependency | Linux release executable/PCK runs an eight-bot match; Web release opens menus and gameplay in Chromium, with verified save import/export and bundled fonts |
| Acceptance | Source comparison screenshots, playable all-map/all-mode tests, gameplay regression checks | 15 combinations and ten final integration scripts pass; source comparisons retained; packaged-browser match starts, fires, charges throws and opens Escape controls; a 1.5-second real hold reaches 100% even at software-rendered 1 FPS |

The actual source has automated scorestreaks and adaptive synthesized music. It does not have
controllable scorestreak cameras or an announcer; those are not migration requirements.

## Current verification

Run from this project using `python tools/run_check.py --script res://<script>`.
This isolates the application name and disables MCP in test processes, preserving the live
editor registry, output log, and player saves. Exports use `tools/build_release.py`, which
creates a separate resource/import-cache copy.

- `tests/core_regression.gd`: source weapon fixtures and 60 simulated seconds of bot combat.
- `tests/actor_parity.gd`: player/bot decisions and the typed sidestep-path regression.
- `tests/weapon_parity.gd`: 13,777 source-derived weapon, animation and death-pose checks.
- `tests/match_lifecycle.gd`: suicides, stable ties, dead-player drop expiry, pickups, scavenger and ADS HUD.
- `tests/death_resets.gd`: player/bot ammo reset, weapon-state cleanup, scorestreak reset and remote ownership.
- `tests/charged_throws.gd`: release-to-throw distance, full fuse, collision and death/pause/console/focus cancellation.
- `tests/pause_controls_test.gd`: real Main pause/controls/back/resume, current bindings and input isolation.
- `tests/postmatch_summary.gd`: team kill totals and normal/nuke best-play finalization.
- `tests/screen_effects_test.gd`: replacing tint, independent flash/blur, deafen timer and cleanup.
- `tests/equipment_vfx_regression.gd`: equipment lifecycle and source VFX parameters.
- `scripts/audio/verify_audio.gd` and `scripts/audio/verify_audio_hooks.gd`: 55 assets and real gameplay routing.
- `tests/objectives_regression.gd`: Domination and CTF rules.
- `tests/all_matches.gd`: 15 map/mode combinations, six bots each, 15 simulated seconds each.
- `tests/mode_victories.gd`: actual kill limits, time draw, Gun Game clean loadout, tiers, bot cap, melee downgrade and final knife victory.
- `tests/net_relay_test.gd`: actual TCP/WebSocket rooms, authority, traffic and host transfer.
- `tests/network_match.gd`: remote interpolation, owner damage, kill/streak credit, bots, respawn and departure.
- `tests/network_lobby.gd`: UI host/ready/settings/start/leave flow with an embedded native relay.
- `tests/input_gamepad_test.gd`: source mappings, thresholds, transitions and disconnect cleanup.
- `scripts/game/verify_streaks.gd` and `scripts/game/verify_streak_integration.gd`: all 12 behaviors and live integration.
- `scripts/game/verify_replays.gd` and `scripts/game/verify_replay_integration.gd`: recorder/interpolation/camera and complete replay lifecycle.
- `scripts/ui/verify_ui.gd`: save round-trips, class/menu controls and HUD inputs.

Visual references are in `assets/maps/previews/source_match_<map>.png` and
`assets/maps/previews/match_<map>.png`. Together with source-derived geometry, shader/depth comparisons, weapon/animation fixtures,
and lifecycle integration checks, these cover the migration acceptance audit. Small rasterization,
transparency-ordering, random-particle and native audio differences are documented in the rendering
and audio READMEs; this is not a claim of pixel-identical output on every platform.

## Requested gameplay changes

The later gameplay request adds three intentional changes to the migration:

- Death refills every carried weapon from its attachment-adjusted ammo capacity and resets scorestreak progress. Already-deployed world streaks finish normally; scoreboard totals stay intact.
- Frag grenades and flashbangs charge while their equipment key is held, reach full power at 1.25 seconds, and throw on release. Charge uses actual hold time even when rendering stalls. Their fuses start on release. Pausing, opening the console, dying, or losing focus cancels a held throw.
- Escape → Controls opens a paused guide for current keyboard/mouse bindings, controller and touch input.

## Reproducible conversion

`tools/export_data.ts` extracts the source tables verbatim; generated JSON is retained with the
Godot project and does not require Deno to run the game. Other conversion tools document their
own commands. Blender's editable sources and exported GLBs are both retained.
