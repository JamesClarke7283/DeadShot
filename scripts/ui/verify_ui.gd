extends SceneTree
## Headless integration smoke test: godot --headless --path . --script scripts/ui/verify_ui.gd
const Store := preload("res://scripts/persistence/save_store.gd")
const GameUI := preload("res://scripts/ui/game_ui.gd")
var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func verify(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
		push_error(message)

func find_control(node: Node, predicate: Callable) -> Node:
	if predicate.call(node): return node
	for child in node.get_children():
		var found := find_control(child, predicate)
		if found: return found
	return null

func choose(option: OptionButton, id: String) -> void:
	for index in option.item_count:
		if str(option.get_item_metadata(index)) == id:
			option.select(index)
			option.item_selected.emit(index)
			return
	verify(false, "Expected selectable option: " + id)

func _run() -> void:
	var path := "user://deadshot.ui-verification-%d.json" % OS.get_process_id()
	var save := Store.new(path)
	verify(save.get_classes().size() == 10, "Ten independent custom classes are available")
	var edited := save.get_loadout(9)
	edited.name = "Verification class"
	edited.primary = {"weaponId": "ak47", "attachments": ["holo", "compensator"]}
	edited.camo = "#112233"
	save.set_class(9, edited)
	save.update_settings({"sensitivity": 1.25, "killcam": false})
	save.set_match_config({"mapId": "urban_docks", "mode": "ctf", "botCount": 16, "difficulty": "veteran", "hardcore": true})
	var reloaded := Store.new(path)
	verify(reloaded.get_loadout(9) == edited, "Full edited loadout survives disk reload")
	verify(reloaded.get_loadout(0).name == "Custom 1", "Other class slots remain independent")
	verify(reloaded.get_settings().sensitivity == 1.25 and not reloaded.get_settings().killcam, "Settings survive disk reload")
	verify(reloaded.get_match_config().hardcore and reloaded.get_match_config().mode == "ctf", "Last match survives disk reload")
	verify(not reloaded.import_browser_save("corrupt"), "Corrupt browser save is rejected")
	verify(reloaded.import_browser_save('{"classes":[{"name":"Imported"}],"settings":{"fov":90}}'), "Partial browser JSON imports")
	verify(reloaded.get_loadout(0).name == "Imported" and reloaded.get_loadout(0).primary.weaponId == "m4", "Imported partial saves merge default fields")
	verify(reloaded.get_settings().fov == 90, "JSON numeric settings migrate correctly")
	verify(reloaded.import_browser_save('{"classes":[{"primary":{"weaponId":42,"attachments":"invalid"},"perks":[],"streaks":[1,"uav"]}]}'), "Malformed nested fields migrate safely")
	verify(reloaded.get_loadout(0).primary.weaponId == "m4" and reloaded.get_loadout(0).perks.size() == 3 and reloaded.get_loadout(0).streaks == ["uav"], "Invalid nested loadout values fall back without breaking the editor")
	DirAccess.remove_absolute(path)
	var ui := GameUI.new()
	ui.store = Store.new(path)
	root.add_child(ui)
	await process_frame
	verify(not ui.menu.visible and not ui.hud.visible and not ui.scoreboard.visible, "Every overlay starts hidden")
	ui.show_main_menu()
	await process_frame
	verify(ui.screen == "main", "Main menu opens")
	ui.show_prematch()
	await process_frame
	verify(ui.match_config.mapId == "desert_town", "Prematch initializes from defaults")
	for slot in 10:
		ui.show_class_editor(slot)
		await process_frame
		verify(ui.current_slot == slot and ui.loadout.name == "Custom %d" % (slot + 1), "Class tab %d selects correct loadout" % (slot + 1))
	verify(ui._weapon_choices().size() == 18, "All 18 primary/secondary weapons appear")
	var primary: OptionButton = find_control(ui.menu, func(node): return node is OptionButton and node.get_selected_metadata() == "m4")
	choose(primary, "ak12")
	verify(ui.store.get_loadout(9).primary.weaponId == "ak12", "Primary weapon selector writes the selected class")
	var lethal: OptionButton = find_control(ui.menu, func(node): return node is OptionButton and node.get_selected_metadata() == "frag")
	choose(lethal, "semtex")
	verify(ui.store.get_loadout(9).lethal == "semtex", "Lethal selector updates its own equipment field")
	var perk: OptionButton = find_control(ui.menu, func(node): return node is OptionButton and node.get_selected_metadata() == "amped")
	choose(perk, "tracker")
	verify(ui.store.get_loadout(9).perks[2] == "tracker", "Perk selector updates the correct tier")
	var custom_camo: ColorPickerButton = find_control(ui.menu, func(node): return node is ColorPickerButton)
	custom_camo.color_changed.emit(Color("123456"))
	verify(ui.store.get_loadout(9).camo == "#123456", "Custom camo color is persisted")
	ui.show_options()
	await process_frame
	var volume: HSlider = find_control(ui.menu, func(node): return node is HSlider and node.get_parent().get_parent().get_child(0).text == "MASTER VOLUME")
	volume.value = 0.25
	verify(ui.store.get_settings().masterVolume == 0.25, "Options slider saves the correct setting")
	var export_path := path + ".export.json"
	verify(ui._export_save(export_path), "Options can export native save JSON")
	ui.store.update_settings({"masterVolume": 0.9})
	verify(ui._import_save(export_path) and ui.store.get_settings().masterVolume == 0.25, "Options import restores exported classes and settings")
	DirAccess.remove_absolute(export_path)
	ui.show_prematch()
	await process_frame
	var bots: HSlider = find_control(ui.menu, func(node): return node is HSlider)
	bots.value = 13
	var ctf_button: Button = find_control(ui.menu, func(node): return node is Button and node.text == "CAPTURE THE FLAG")
	ctf_button.pressed.emit()
	var capture := {"config": {}}
	ui.start_match.connect(func(config): capture.config = config)
	var start_button: Button = find_control(ui.menu, func(node): return node is Button and node.text == "START MATCH")
	start_button.pressed.emit()
	verify(capture.config.botCount == 13 and capture.config.mode == "ctf", "Prematch controls emit actual chosen match settings")
	ui.show_multiplayer()
	await process_frame
	ui.set_lobby_state({"isHost": true, "room": "TEST", "ready": false, "players": [{"id": 1, "name": "Player", "team": "blue", "ready": true}], "settings": Store.default_match_config()})
	await process_frame
	ui.show_match(true)
	ui.update_hud({"health": 75, "objective": {"kind": "dom", "points": [{"label": "A", "owner": "blue", "progress": 0.5}], "blue": 50, "red": 20, "cap": 200}, "nextStreakName": null, "nextStreakCost": null, "streaks": [{"name": "UAV", "cost": 500, "score": 250, "available": false}], "minimap": {"player": {"x": 10, "z": 10, "yaw": 1.0}, "bounds": {"minX": -50, "maxX": 50, "minZ": -50, "maxZ": 50}, "blips": [{"x": 15, "z": 15, "enemy": true}]}})
	ui.add_kill({"killer": "Player", "victim": "Enemy", "weaponId": "m4", "killerTeam": "blue", "victimTeam": "red", "headshot": true})
	ui.hit_marker(true)
	ui.damage_from(0.5)
	await process_frame
	verify(not ui.menu.visible and ui.hud.visible and ui.hud.hardcore, "Entering a match hides modal menus")
	for action in ["forward", "back", "left", "right", "fire", "ads", "reload", "jump", "lethal", "tactical"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
	ui.set_touch_enabled(true)
	await process_frame
	ui.touch_controls._begin_touch(0, Vector2(90, ui.touch_controls.size.y - 135))
	ui.touch_controls._begin_touch(1, ui.touch_controls.size + Vector2(-75, -165))
	verify(Input.is_action_pressed("forward") and Input.is_action_pressed("fire"), "Touch joystick and fire support simultaneous fingers")
	ui.touch_controls._end_touch(0)
	verify(not Input.is_action_pressed("forward") and Input.is_action_pressed("fire"), "Ending movement retains independently held fire")
	ui.show_scoreboard(true, [{"name": "Player", "kills": 5, "deaths": 1, "assists": 2, "score": 550, "team": "blue", "isPlayer": true}], 5, 2, "tdm")
	await process_frame
	ui.show_streak_menu([{"id": "uav", "name": "UAV", "available": true}])
	await process_frame
	ui.toggle_console()
	verify(ui.console_open, "Developer console opens")
	ui.show_pause()
	await process_frame
	verify(not ui.console_open and not ui.streak_menu.visible and not ui.scoreboard.visible, "Pause dismisses temporary overlays")
	verify(not Input.is_action_pressed("fire") and not ui.touch_controls.visible, "Pause releases held touch actions")
	var final_rows: Array = []
	for index in 15:
		final_rows.append({"name": "Finisher %d" % index, "kills": 12, "deaths": 3, "assists": 1, "score": 1250, "isPlayer": index == 0})
	ui.show_postmatch(final_rows, 5, 2, "tdm", "BLUE team wins", 3)
	await process_frame
	verify(find_control(ui.menu, func(node): return node is Label and node.text == "BLUE team wins") != null, "Postmatch preserves the source winner text")
	verify(find_control(ui.menu, func(node): return node is Label and node.text.begins_with("Finisher 11 ")) != null and find_control(ui.menu, func(node): return node is Label and node.text.begins_with("Finisher 12 ")) == null, "Postmatch displays the source top twelve rows")
	verify(find_control(ui.menu, func(node): return node is Button and node.text == "Continue") != null, "Postmatch provides source Continue action")
	ui.show_loading(0.5, "Verifying UI…")
	await process_frame
	DirAccess.remove_absolute(path)
	print("UI + storage verification: %s" % ("PASS" if failures.is_empty() else "%d failures" % failures.size()))
	quit(0 if failures.is_empty() else 1)
