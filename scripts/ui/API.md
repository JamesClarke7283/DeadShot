# Native DeadShot UI

`game_ui.gd` extends CanvasLayer. Add it as a child; all screens start hidden.
Call `show_main_menu()` after startup. `store` is a SaveStore instance; use
`store.get_loadout(index)` for a copy of a class (Godot reserves `get_class()`).
The save format preserves the browser's camelCase property names and all ten
class slots. SaveStore can import the JSON value of `localStorage['deadshot.save']`
through `import_browser_save(json)`.

## Screen transitions

- `show_main_menu()`, `show_prematch()`, `show_class_editor(slot = -1)`
- `show_options(return_to = 'main')`, `show_loading(progress, status)`
- `show_match(hardcore = false)`, `show_pause()`, `show_controls()`
- `show_postmatch(rows, blue, red, mode, winner, best_play_kills = 0)`
- `show_replay(title, hint, color)`, `hide_replay()`
- `show_scoreboard(visible, rows = [], blue = 0, red = 0, mode = 'tdm')`
- `show_streak_menu(options)`, `hide_streak_menu()`

Match config is `{mapId, mode, botCount, difficulty, classSlot, hardcore}`.
Signals `start_match(config)`, `resume_match`, `leave_match`, `quit_requested`,
`settings_changed(settings)` and `streak_selected(id)` are owned by the game.
The optional best-play button emits `best_play_requested` when kills are at least two.
The UI never starts or stops simulation itself.
The pause menu's Controls page reads keyboard/mouse bindings from InputMap.
Its Back button and Escape return to pause; they do not emit `resume_match`.

## HUD

`update_hud(state)` merges a partial dictionary. Properties:

- `health`, `maxHealth`, `mag`, `reserve`, `weaponName`
- `blue`, `red`, `mode`, `timeLeft` (seconds)
- `spread` (pixels), `ads`, `reloading`, optional `fps`
- `streakScore`, `nextStreakName`, `nextStreakCost` (null next values mean maximum)
- `gunGameTier`, `gunGameMaxTier`, `gunGameWeapon` (tier zero hides it)
- `prompt` (empty string hides it), `alive`, `deathText`
- `killcam`, `killcamText`
- `flashOpacity`, `stunOpacity`, `stunBlur` (pixels), `damageOpacity`
- `objective`: `{kind, points:[{label,owner,progress}], blue,red,cap}` or
  `{kind, flags:[{team,status}], blue,red,cap}`; null/empty hides it
- `streaks`: `[{id,name,cost,score,available}]`
- `minimap`: `{player:{x,z,yaw}, blips:[{x,z,enemy}],
  bounds:{minX,maxX,minZ,maxZ}, jammed}`

`hit_marker(headshot = false)`, `damage_from(angle)` and `add_kill(event)` animate
feedback; kill event fields match the browser: killer, victim, killerTeam,
victimTeam, weaponId, headshot. Scoreboard rows preserve name, team, kills,
deaths, assists, score and isPlayer.

`apply_screen_effect(kind, intensity, duration)` handles `flash`/`flashbang`,
`stun` (supplied tint intensity is already 0.6 × proximity; blur is intensity ×
20px), `blur` (raw pixel sigma), `damage`, `scavenger`, and state-only `deafen`,
with linear timed decay. Damage, stun and scavenger replace a single tint state;
flash and blur retain independent timers. Effects pause with the match. Call
`clear_screen_effects()` when ending/resetting a match. The render order matches
the browser: radial ellipse tint, separable Gaussian blur, then white flash over
the HUD. Effects do not change movement or audio playback.

## Settings

`OPTIONS` edits one flat settings dictionary and persists each change through
`SaveStore.update_settings(patch)`, then emits the whole dictionary on
`settings_changed`. Keys: `sensitivity`, `fov`, `masterVolume`, `sfxVolume`,
`musicVolume`, `invertY`, `killcam`.

Graphics is two keys working as one control. `graphicsDetail` is the shipped
**0–100** slider. `graphics` is the band that position resolves to
(`low`/`medium`/`high`/`ultra`), kept so an older save or the browser import
format stays readable. A settings dictionary carrying `graphicsDetail` is
authoritative for the slider; one carrying only `graphics` moves the slider to
that band's anchor. `SaveStore.migrate()` drops a `graphicsDetail` that is not a
float, and a save predating it migrates to the default anchor.

## Multiplayer and console

`show_multiplayer()` opens the connection form. Signals:
`multiplayer_connect({url,name,room,asHost})`, `multiplayer_ready(bool)`,
`multiplayer_start`, `multiplayer_settings(config)`, `multiplayer_leave`.
The network client supplies `set_lobby_state({room,isHost,selfId,hostId,ready,
players:[{id,name,team,ready}],settings})` or `set_network_status(text)`.

The game handles the backquote action by calling `toggle_console()`. While
`console_open` is true, do not process gameplay keyboard shortcuts. The
`console_command(command)` signal requests execution; `console_print(text)`
appends command output. Gameplay keyboard bindings are suspended while typing
and restored on close or node cleanup. Set `preserve_virtual_action` to a
Callable returning whether the gamepad holds an action so opening the console
retains those actions. Gamepad and lower-screen touch controls continue running.

## Touch controls

Native touchscreen detection enables the same left joystick, right look pad and
FIRE/ADS/R/JMP/LETH/TAC controls. `set_touch_enabled(bool)` can force the overlay
for testing or platform overrides. Movement and action buttons drive the game's
existing InputMap actions directly. Connect `touch_look(delta: Vector2)` in the
controller to camera aim. The source applies yaw `-delta.x * 0.004` and pitch
`-delta.y * 0.004` directly, independent of mouse sensitivity. Menu/pause/replay
transitions release held touch actions. Multiple fingers can move, aim and fire
simultaneously.

## Verification

Run `python tools/run_check.py --script scripts/ui/verify_ui.gd` for actual screen
construction, all ten class tabs, complete weapon lists, overlay transitions,
combat feedback and atomic save/reload/import checks. The verification writes
only a process-specific temporary save, then removes it.
