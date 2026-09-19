extends SceneTree
var failures: Array[String] = []

func _initialize() -> void: call_deferred("run")

func check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func find(node: Node, predicate: Callable) -> Node:
	if predicate.call(node): return node
	for child in node.get_children():
		var found := find(child, predicate)
		if found: return found
	return null

func press(ui: Node, caption: String) -> void:
	var button := find(ui.menu, func(node): return node is Button and node.text == caption)
	check(button != null, "Button exists: " + caption)
	if button: button.pressed.emit()

func key(code: Key, pressed: bool) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = pressed
	Input.parse_input_event(event)
	Input.flush_buffered_events()

func run() -> void:
	var main = load("res://scripts/core/main.gd").new()
	root.add_child(main)
	await process_frame
	main.start_match({"mapId":"desert_town", "mode":"tdm", "botCount":0, "difficulty":"regular", "classSlot":0, "hardcore":false})
	await physics_frame
	main.paused = true
	main.ui.show_pause()
	var start: Vector3 = main.game_match.player.position
	var alternate := InputEventKey.new()
	alternate.physical_keycode = KEY_T
	InputMap.action_add_event("reload", alternate)
	press(main.ui, "CONTROLS")
	await process_frame
	check(main.paused and main.ui.screen == "controls", "The guide opens while keeping the match paused")
	check(find(main.ui.menu, func(node): return node is Label and node.text.contains("R / T")) != null, "Guide reads actual remapped action bindings")
	check(find(main.ui.menu, func(node): return node is Label and node.text.contains("1.25s")) != null, "Guide explains charged grenade and flashbang throws")
	key(KEY_W, true)
	key(KEY_G, true)
	for i in 5: await physics_frame
	check(main.game_match.player.position.is_equal_approx(start), "Keyboard input in the guide does not move the paused player")
	key(KEY_W, false)
	key(KEY_G, false)
	press(main.ui, "BACK TO PAUSE")
	check(main.paused and main.ui.screen == "pause", "Back returns to the pause menu without resuming")
	press(main.ui, "CONTROLS")
	key(KEY_ESCAPE, true)
	await process_frame
	check(main.paused and main.ui.screen == "pause", "Escape from the guide returns to pause without leaking a resume event")
	key(KEY_ESCAPE, false)
	press(main.ui, "RESUME")
	check(not main.paused and main.ui.screen == "match", "Resume restores the live match")
	check(not Input.is_action_pressed("forward") and not Input.is_action_pressed("lethal"), "Guide input leaves no held movement or throw action")
	InputMap.action_erase_event("reload", alternate)
	main.leave_match()
	# AudioServer defers playback disposal through the mixer thread and another
	# main-loop tick. Let that cleanup finish before ending this headless test.
	main.audio.stop_music()
	await create_timer(0.25).timeout
	main.queue_free()
	await process_frame
	await create_timer(0.25).timeout
	print("Pause controls guide: %s" % ("PASS" if failures.is_empty() else "%d failures" % failures.size()))
	quit(0 if failures.is_empty() else 1)
