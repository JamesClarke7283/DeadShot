extends SceneTree
const UI := preload("res://scripts/ui/game_ui.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func key(code: Key, pressed: bool = true) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.unicode = code + 32 if code >= KEY_A and code <= KEY_Z else code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	var bindings := {"forward": KEY_W, "left": KEY_A, "back": KEY_S, "right": KEY_D, "reload": KEY_R, "melee": KEY_K, "jump": KEY_SPACE, "pause": KEY_ESCAPE}
	for action in bindings:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var binding := InputEventKey.new()
		binding.physical_keycode = bindings[action]
		InputMap.action_add_event(action, binding)
	var ui := UI.new()
	root.add_child(ui)
	await process_frame
	ui.show_match()
	ui.toggle_console()
	await process_frame
	for code in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_R, KEY_K]:
		key(code)
		for action in bindings:
			check(not Input.is_action_pressed(action) and not Input.is_action_just_pressed(action), "Console typing suppresses pressed and just_pressed for " + action)
		key(code, false)
		await process_frame
	check(ui.console_input.text == "wasdrk", "The console still receives the actual typed text")
	check(ui.console_open and ui.screen == "match" and not paused, "Typing does not pause gameplay")
	ui.preserve_virtual_action = func(action): return action == "jump"
	Input.action_press("jump")
	key(KEY_SPACE)
	check(Input.is_action_pressed("jump"), "Typing retains a simultaneously held gamepad action")
	key(KEY_SPACE, false)
	Input.action_release("jump")
	key(KEY_ESCAPE)
	await process_frame
	check(not ui.console_open and not Input.is_action_pressed("pause"), "Escape closes the console without pausing the match")
	key(KEY_ESCAPE, false)
	ui.toggle_console()
	key(KEY_QUOTELEFT)
	await process_frame
	check(not ui.console_open, "Backquote closes the focused console instead of entering text")
	key(KEY_QUOTELEFT, false)
	key(KEY_W)
	check(Input.is_action_pressed("forward"), "Keyboard gameplay bindings are restored after closing the console")
	key(KEY_W, false)
	ui.toggle_console()
	ui.queue_free()
	await process_frame
	var restored := false
	for binding in InputMap.action_get_events("forward"):
		if binding is InputEventKey and binding.physical_keycode == KEY_W: restored = true
	check(restored, "Freeing the UI restores suspended keyboard bindings")
	print("Console keyboard isolation: %s" % ("PASS" if failures.is_empty() else "%d failures" % failures.size()))
	quit(0 if failures.is_empty() else 1)
