# Native gamepad adapter

Instantiate `gamepad.gd` as a Node child. Call `poll(delta, player)` each frame
while a match is active, including while paused. Pass null as `player` while
paused or replaying so the adapter still handles Start
without rotating the camera. Call `release_all()` when leaving a match.

Remove direct InputEventJoypadMotion/Button entries from the controller's
InputMap setup and remove its previous right-stick loop. The adapter exclusively
owns pad actions; native keyboard and mouse bindings remain in InputMap.

Mapping preserves `src/core/Gamepad.ts`: left stick digital movement above .3;
independent .18 right-stick deadzones at 2.8 radians/sec; RT fire; LT ADS; A raises stance;
X reload; RB lethal; LB tactical; L3 sprint; Y streaks; Back scoreboard; Start
pause. There is no source B or R3 action. The first connected pad is selected.

Set `ui.preserve_virtual_action = func(action): return gamepad.held.get(action, false)`
so opening the text console preserves any held pad actions. Console keyboard
bindings are suspended until it closes; gamepad polling and aiming continue.

Action changes emit InputEventAction so the main controller's event-based pause
handler works. Idle or disconnected controllers do not release keyboard actions.
Disconnect and scene cleanup release only pad-owned actions. `connected()`
reports hardware availability. `poll_state(delta,player,axes,buttons,present)`
supports deterministic tests without physical controllers; axes use Godot's
left/right sticks and LT/RT order, button keys use Godot JOY_BUTTON constants.

Run `python tools/run_check.py --script tests/input_gamepad_test.gd` to verify
thresholds, aim rotation, button events, no duplicate presses, disconnect cleanup
and idle-keyboard preservation.
