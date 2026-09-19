extends CanvasLayer
## All screens start hidden. Public show_* methods own visibility and mouse focus.
## See API.md for the combat-state dictionary and networking integration contract.
signal start_match(config: Dictionary)
signal resume_match
signal leave_match
signal quit_requested
signal settings_changed(settings: Dictionary)
signal streak_selected(id: String)
signal multiplayer_connect(config: Dictionary)
signal multiplayer_ready(ready: bool)
signal multiplayer_start
signal multiplayer_settings(config: Dictionary)
signal multiplayer_leave
signal console_command(command: String)
signal best_play_requested
signal touch_look(delta: Vector2)

const UI := preload("res://scripts/ui/ui_theme.gd")
const Store := preload("res://scripts/persistence/save_store.gd")
const Hud := preload("res://scripts/ui/hud_painter.gd")
const Touch := preload("res://scripts/ui/touch_controls.gd")
const GraphicsQuality := preload("res://scripts/world/graphics_quality.gd")
const MAPS := [
	{"id": "desert_town", "name": "Desert Town", "description": "Flat sandy town — long main-street sightlines and alley CQB."},
	{"id": "forest_facility", "name": "Forest Facility", "description": "Rolling forested hills with concrete bunkers and a radar dish — medium-range lanes."},
	{"id": "urban_docks", "name": "Urban Docks", "description": "Flat concrete waterfront — container lanes, cranes and tight CQB."},
]
const MODES := [{"id": "tdm", "name": "TEAM DEATHMATCH"}, {"id": "ffa", "name": "FREE-FOR-ALL"}, {"id": "dom", "name": "DOMINATION"}, {"id": "ctf", "name": "CAPTURE THE FLAG"}, {"id": "gungame", "name": "GUN GAME"}]
const DIFFICULTIES := [{"id": "recruit", "name": "Recruit"}, {"id": "regular", "name": "Regular"}, {"id": "veteran", "name": "Veteran"}]
var store := Store.new()
var screen := ""
var root: Control
var menu: Control
var hud: Control
var scoreboard: Control
var streak_menu: Control
var match_config: Dictionary
var current_slot := 0
var loadout: Dictionary
var tables: Dictionary = {}
var class_body: HBoxContainer
var class_preview: Node3D
var preview_camera: Camera3D
var preview_time := 0.0
var stat_bars: Dictionary = {}
var network_status := ""
var network_config := {"url": "ws://127.0.0.1:8090/ws", "name": "Player", "room": ""}
var lobby_state: Dictionary = {}
var settings_return := "main"
var console_panel: PanelContainer
var console_output: RichTextLabel
var console_input: LineEdit
var console_open := false
var effect_layer: Control
var replay_overlay: Control
var touch_controls: Control
var touch_enabled := DisplayServer.is_touchscreen_available() or OS.has_feature("android") or OS.has_feature("ios")
var fps_counter: Label
var fps_elapsed := 0.0
var options_status := ""
var web_import_callback
## Main supplies gamepad-held actions; touch actions are checked locally.
var preserve_virtual_action: Callable
var console_key_bindings: Dictionary = {}
const GAMEPLAY_ACTIONS := ["forward", "back", "left", "right", "jump", "crouch", "sprint", "reload", "lethal", "tactical", "melee", "interact", "weapon_primary", "weapon_secondary", "fire_mode", "scoreboard", "streaks", "pause", "streak_slot_1", "streak_slot_2", "streak_slot_3"]

func _input(event: InputEvent) -> void:
	if screen == "controls" and event.is_action_pressed("pause"):
		show_pause()
		get_viewport().set_input_as_handled()
		return
	if not console_open or not event is InputEventKey:
		return
	if event.pressed and not event.echo and event.keycode in [KEY_ESCAPE, KEY_QUOTELEFT]:
		toggle_console()
		get_viewport().set_input_as_handled()
		return

func _suspend_console_keys() -> void:
	# A focused LineEdit consumes UI events after Godot has updated InputMap.
	# Removing only keyboard bindings prevents both pressed and just_pressed,
	# while synthetic touch/pad actions and text editing keep working normally.
	for action in GAMEPLAY_ACTIONS:
		if not InputMap.has_action(action):
			continue
		var bindings: Array[InputEvent] = []
		for binding in InputMap.action_get_events(action):
			if binding is InputEventKey:
				bindings.append(binding)
				InputMap.action_erase_event(action, binding)
		if not bindings.is_empty():
			console_key_bindings[action] = bindings
			var virtual_held: bool = touch_controls.held.get(action, false) or (preserve_virtual_action.is_valid() and preserve_virtual_action.call(action))
			if not virtual_held:
				Input.action_release(action)

func _restore_console_keys() -> void:
	for action in console_key_bindings:
		if InputMap.has_action(action):
			for binding in console_key_bindings[action]:
				InputMap.action_add_event(action, binding)
	console_key_bindings.clear()

func _exit_tree() -> void:
	_restore_console_keys()

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	layer = 20
	root = Control.new()
	root.name = "DeadShotUI"
	add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UI.make_theme()
	for table_name in ["weapons", "attachments", "camos", "perks", "streaks", "equipment"]:
		var path := "res://data/%s.json" % table_name
		tables[table_name] = JSON.parse_string(FileAccess.get_file_as_string(path)) if FileAccess.file_exists(path) else []
		if not tables[table_name] is Array:
			tables[table_name] = []
	match_config = store.get_match_config()
	match_config.classSlot = 0
	hud = Hud.new()
	root.add_child(hud)
	hud.hide()
	touch_controls = Touch.new()
	root.add_child(touch_controls)
	touch_controls.look_delta.connect(func(delta): touch_look.emit(delta))
	touch_controls.hide()
	menu = _new_overlay("Menu")
	scoreboard = _new_overlay("Scoreboard")
	streak_menu = _new_overlay("StreakMenu")
	menu.hide()
	scoreboard.hide()
	streak_menu.hide()
	fps_counter = _label(root, "", 12, Color("b6ff5e"), 400)
	fps_counter.position = Vector2(8, 6)
	fps_counter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_console()
	_build_screen_effects()
	replay_overlay = _new_overlay("Replay")
	replay_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	replay_overlay.hide()

func _process(delta: float) -> void:
	fps_elapsed += delta
	if fps_elapsed >= 0.25 and is_instance_valid(fps_counter):
		fps_elapsed = 0
		fps_counter.text = "%d FPS" % Engine.get_frames_per_second()
	if screen == "match":
		_update_screen_effects(delta)
	elif is_instance_valid(effect_layer):
		effect_layer.hide()
	if screen == "class" and is_instance_valid(class_preview):
		preview_time += delta * 0.4
		class_preview.rotation.y = -sin(preview_time) * 0.5

func _new_overlay(node_name: String) -> Control:
	var control := Control.new()
	control.name = node_name
	root.add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return control

func _clear(control: Node) -> void:
	for child in control.get_children():
		control.remove_child(child)
		child.queue_free()

func _switch(next: String, transparent: bool = false) -> void:
	screen = next
	_clear(menu)
	menu.show()
	scoreboard.hide()
	streak_menu.hide()
	hud.visible = next == "pause"
	touch_controls.hide()
	UI.background(menu, transparent)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	replay_overlay.hide()
	if console_open:
		toggle_console()

func _label(parent: Node, text: String, font_size: int = 14, color: Color = UI.WHITE, weight: int = 600) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UI.font(weight))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable, muted: bool = false) -> Button:
	var result := Button.new()
	result.text = text
	parent.add_child(result)
	result.pressed.connect(action)
	result.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if muted:
		result.add_theme_stylebox_override("normal", UI.gradient_box(Color("42505f"), Color("2c3845")))
		result.add_theme_stylebox_override("hover", UI.gradient_box(Color("536373"), Color("394858")))
		result.add_theme_color_override("font_color", UI.WHITE)
		result.add_theme_color_override("font_hover_color", UI.WHITE)
	return result

func _vbox(parent: Node, gap: int = 14) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	parent.add_child(box)
	return box

func _hbox(parent: Node, gap: int = 10) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	parent.add_child(box)
	return box

func _center_panel(width: float = 820, padding: int = 32) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	menu.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_top = 24
	scroll.offset_bottom = -24
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var center := CenterContainer.new()
	scroll.add_child(center)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	center.size_flags_vertical = Control.SIZE_EXPAND_FILL
	var panel := PanelContainer.new()
	center.add_child(panel)
	panel.custom_minimum_size.x = minf(width, root.size.x - 48)
	var style := UI.box(Color("10141ceb"), UI.INK, 16, 3, padding)
	style.shadow_color = UI.INK
	style.shadow_size = 0
	style.shadow_offset = Vector2(6, 6)
	panel.add_theme_stylebox_override("panel", style)
	return _vbox(panel, 20)

func _section(parent: Node, title: String) -> VBoxContainer:
	var section := _vbox(parent, 8)
	_label(section, title.to_upper(), 13, UI.MUTED, 700)
	return section

func _option(parent: Node, choices: Array, value: String, action: Callable) -> OptionButton:
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(option)
	for i in choices.size():
		var item: Dictionary = choices[i]
		option.add_item(str(item.get("name", item.get("id", ""))))
		option.set_item_metadata(i, str(item.get("id", "")))
		option.get_popup().set_item_tooltip(i, str(item.get("description", item.get("name", ""))))
		if str(item.get("id", "")) == value:
			option.select(i)
	option.item_selected.connect(func(index):
		option.tooltip_text = option.get_popup().get_item_tooltip(index)
		action.call(option.get_item_metadata(index)))
	return option

func _field(parent: Node, text: String, value: String, action: Callable) -> LineEdit:
	var section := _section(parent, text)
	var input := LineEdit.new()
	input.text = value
	section.add_child(input)
	input.text_changed.connect(action)
	return input

func _check(parent: Node, text: String, checked: bool, action: Callable) -> CheckBox:
	var check := CheckBox.new()
	check.text = text
	check.button_pressed = checked
	parent.add_child(check)
	check.toggled.connect(action)
	return check

func _slider(parent: Node, caption: String, value: float, minimum: float, maximum: float, step: float, action: Callable) -> void:
	var section := _section(parent, caption)
	var row := _hbox(section, 16)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(180, 24)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var value_label := _label(row, str(int(value)) if step >= 1 else str(value), 18, UI.GREEN, 800)
	value_label.custom_minimum_size.x = 44
	slider.value_changed.connect(func(current):
		value_label.text = str(int(current)) if step >= 1 else str(current)
		action.call(current))

func show_main_menu() -> void:
	_switch("main")
	var center := CenterContainer.new()
	menu.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.offset_top = -20
	var column := _vbox(center, 4)
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	var logo := _label(column, "DEADSHOT", 88, UI.GREEN, 900)
	logo.add_theme_font_override("font", UI.font(900, 5))
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	logo.add_theme_color_override("font_shadow_color", UI.INK)
	logo.add_theme_constant_override("shadow_offset_x", 6)
	logo.add_theme_constant_override("shadow_offset_y", 6)
	logo.add_theme_constant_override("outline_size", 3)
	logo.add_theme_color_override("font_outline_color", UI.INK)
	for glow_info in [[24, 0.015], [20, 0.025], [16, 0.035], [12, 0.05], [8, 0.06]]:
		var glow := Label.new()
		logo.add_child(glow)
		glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		glow.show_behind_parent = true
		glow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glow.text = "DEADSHOT"
		glow.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		glow.add_theme_font_override("font", UI.font(900, 5))
		glow.add_theme_font_size_override("font_size", 88)
		glow.add_theme_color_override("font_color", Color.TRANSPARENT)
		glow.add_theme_color_override("font_outline_color", Color(0.804, 0.922, 0.431, glow_info[1]))
		glow.add_theme_constant_override("outline_size", glow_info[0])
	var subtitle := _label(column, "LOCK IN. LOAD OUT. LIGHT 'EM UP.", 18, UI.MUTED)
	subtitle.add_theme_font_override("font", UI.font(600, 3))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var title_gap := Control.new()
	title_gap.custom_minimum_size.y = 24
	column.add_child(title_gap)
	var button_center := CenterContainer.new()
	column.add_child(button_center)
	var buttons := _vbox(button_center, 14)
	buttons.custom_minimum_size.x = 260
	_button(buttons, "PLAY", show_prematch)
	_button(buttons, "MULTIPLAYER", show_multiplayer)
	_button(buttons, "CREATE-A-CLASS", show_class_editor)
	_button(buttons, "OPTIONS", func(): show_options("main"))
	var quit := _button(buttons, "QUIT", func(): quit_requested.emit())
	quit.add_theme_stylebox_override("normal", UI.gradient_box(Color("ee8888"), Color("cc5555")))
	quit.add_theme_stylebox_override("hover", UI.gradient_box(Color("ee8888").lightened(0.08), Color("cc5555").lightened(0.08)))
	quit.add_theme_stylebox_override("pressed", UI.gradient_box(Color("cc5555"), Color("ee8888")))
	for item in buttons.get_children():
		item.custom_minimum_size.y = 50
		item.add_theme_font_size_override("font_size", 18)

func show_prematch() -> void:
	_switch("prematch")
	var panel := _center_panel()
	_label(panel, "PRE-MATCH LOBBY", 34, UI.GREEN, 900)
	panel.get_child(0).add_theme_font_override("font", UI.font(900, 2))
	var maps := _section(panel, "Map")
	var map_row := _hbox(maps, 12)
	var map_group := ButtonGroup.new()
	for map in MAPS:
		var card := Button.new()
		card.toggle_mode = true
		card.button_group = map_group
		card.button_pressed = match_config.mapId == map.id
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.custom_minimum_size = Vector2(220, 100)
		card.add_theme_font_size_override("font_size", 13)
		card.add_theme_color_override("font_color", UI.WHITE)
		card.add_theme_color_override("font_pressed_color", UI.WHITE)
		card.add_theme_stylebox_override("normal", UI.box(Color("0a0c1099"), UI.INK, 10, 2, 14))
		card.add_theme_stylebox_override("pressed", UI.box(Color("9fd13e2e"), UI.GREEN, 10, 3, 14))
		map_row.add_child(card)
		var card_margin := MarginContainer.new()
		card.add_child(card_margin)
		card_margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for margin_side in ["left", "right", "top", "bottom"]:
			card_margin.add_theme_constant_override("margin_" + margin_side, 14)
		card_margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var card_column := _vbox(card_margin, 6)
		card_column.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_label(card_column, map.name, 17, UI.WHITE, 800).mouse_filter = Control.MOUSE_FILTER_IGNORE
		var description := _label(card_column, map.description, 12, UI.MUTED, 400)
		description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		description.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.pressed.connect(func(): match_config.mapId = map.id)
	var mode_section := _section(panel, "Mode")
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 10)
	flow.add_theme_constant_override("v_separation", 10)
	mode_section.add_child(flow)
	var mode_group := ButtonGroup.new()
	for mode in MODES:
		var button := _button(flow, mode.name, func(): match_config.mode = mode.id, true)
		button.toggle_mode = true
		button.button_group = mode_group
		button.button_pressed = match_config.mode == mode.id
		button.add_theme_font_size_override("font_size", 16)
		button.add_theme_color_override("font_pressed_color", UI.INK)
	_slider(panel, "Bots", match_config.botCount, 0, 16, 1, func(value): match_config.botCount = int(value))
	var difficulty := _section(panel, "Difficulty")
	var difficulty_row := _hbox(difficulty, 20)
	var group := ButtonGroup.new()
	for level in DIFFICULTIES:
		var check := _check(difficulty_row, level.name, match_config.difficulty == level.id, func(checked):
			if checked: match_config.difficulty = level.id)
		check.button_group = group
	var choices: Array = []
	for i in Store.CLASS_SLOTS:
		choices.append({"id": str(i), "name": "%d. %s" % [i + 1, store.get_loadout(i).name]})
	var class_select := _option(_section(panel, "Class"), choices, str(match_config.get("classSlot", 0)), func(value): match_config.classSlot = int(value))
	class_select.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	class_select.custom_minimum_size.x = 320
	class_select.add_theme_stylebox_override("normal", UI.box(UI.GREEN, UI.INK, 8, 2, 10))
	class_select.add_theme_color_override("font_color", UI.INK)
	_check(panel, "HARDCORE", match_config.hardcore, func(value): match_config.hardcore = value)
	_check(panel, "KILLCAM", store.get_settings().killcam, func(value): _setting("killcam", value))
	var footer := _hbox(panel)
	_button(footer, "BACK", show_main_menu, true)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(space)
	_button(footer, "START MATCH", func():
		store.set_match_config(match_config)
		start_match.emit(match_config.duplicate(true)))

func _setting(key: String, value: Variant) -> void:
	store.update_settings({key: value})
	settings_changed.emit(store.get_settings())

func show_options(return_to: String = "main") -> void:
	settings_return = return_to
	_switch("options", return_to == "pause")
	var panel := _center_panel(520, 28)
	_label(panel, "OPTIONS", 30, UI.GREEN, 900)
	var settings := store.get_settings()
	_slider(panel, "Master Volume", settings.masterVolume, 0, 1, 0.01, func(value): _setting("masterVolume", value))
	_slider(panel, "SFX Volume", settings.sfxVolume, 0, 1, 0.01, func(value): _setting("sfxVolume", value))
	_slider(panel, "Music Volume", settings.musicVolume, 0, 1, 0.01, func(value): _setting("musicVolume", value))
	_slider(panel, "Mouse Sensitivity", settings.sensitivity, 0.1, 3, 0.05, func(value): _setting("sensitivity", value))
	_slider(panel, "Field of View", settings.fov, 50, 110, 1, func(value): _setting("fov", value))
	var levels: Array = []
	for level in GraphicsQuality.LEVELS:
		levels.append({"id": level, "name": level.capitalize()})
	var graphics_option := _option(_section(panel, "Graphics"), levels, str(settings.get("graphics", GraphicsQuality.DEFAULT_LEVEL)), func(value): _setting("graphics", value))
	graphics_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	graphics_option.add_theme_font_size_override("font_size", 16)
	graphics_option.add_theme_font_override("font", UI.font(600))
	_check(panel, "INVERT Y", settings.invertY, func(value): _setting("invertY", value))
	_check(panel, "KILLCAM", settings.killcam, func(value): _setting("killcam", value))
	var saves := _hbox(panel, 10)
	_button(saves, "IMPORT SAVE", func(): _choose_save_file(false), true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(saves, "EXPORT SAVE", func(): _choose_save_file(true), true).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if not options_status.is_empty():
		_label(panel, options_status, 12, UI.GREEN).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_button(panel, "BACK", func():
		if settings_return == "pause": show_pause()
		else: show_main_menu(), true)

func _choose_save_file(exporting: bool) -> void:
	if OS.has_feature("web"):
		_choose_web_save(exporting)
		return
	var dialog := FileDialog.new()
	root.add_child(dialog)
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.file_mode = FileDialog.FILE_MODE_SAVE_FILE if exporting else FileDialog.FILE_MODE_OPEN_FILE
	dialog.title = "Export DeadShot save" if exporting else "Import DeadShot save JSON"
	dialog.filters = PackedStringArray(["*.json ; DeadShot save JSON"])
	if exporting:
		dialog.current_file = "deadshot.save.json"
	dialog.file_selected.connect(func(path):
		if exporting:
			_export_save(path)
		else:
			_import_save(path)
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered_ratio(0.7)

func _choose_web_save(exporting: bool) -> void:
	if exporting:
		JavaScriptBridge.download_buffer(JSON.stringify(store.data, "\t").to_utf8_buffer(), "deadshot.save.json", "application/json")
		options_status = "Exported all classes and settings to deadshot.save.json"
		show_options(settings_return)
		return
	# Keep the callback alive until FileReader completes, as required by the
	# JavaScriptBridge API. Use the browser picker rather than the Web virtual FS.
	if web_import_callback == null:
		web_import_callback = JavaScriptBridge.create_callback(_web_save_imported)
	JavaScriptBridge.eval("""window.deadshotChooseSave = function(callback) {
    var previous = document.getElementById('deadshot-save-upload');
    if (previous) previous.remove();
    var input = document.createElement('input');
    input.id = 'deadshot-save-upload';
    input.type = 'file';
    input.accept = '.json,application/json';
    input.style.display = 'none';
    input.oncancel = function() { input.remove(); };
    input.onchange = function() {
        var file = input.files && input.files[0];
        if (!file) { input.remove(); return; }
        var reader = new FileReader();
        reader.onload = function() { callback('data', String(reader.result)); input.remove(); };
        reader.onerror = function() { callback('error', 'Could not read the selected save file.'); input.remove(); };
        reader.readAsText(file);
    };
    document.body.appendChild(input);
    input.click();
};""", true)
	JavaScriptBridge.get_interface("window").deadshotChooseSave(web_import_callback)

func _web_save_imported(arguments: Array) -> void:
	if arguments.size() < 2: return
	if str(arguments[0]) == "data":
		_import_save_text(str(arguments[1]))
	else:
		options_status = str(arguments[1])
		show_options(settings_return)

func _import_save(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		options_status = "Could not read the selected save file."
		show_options(settings_return)
		return false
	var contents := file.get_as_text()
	file.close()
	return _import_save_text(contents)

func _import_save_text(contents: String) -> bool:
	var success: bool = store.import_browser_save(contents)
	if success:
		match_config = store.get_match_config()
		match_config.classSlot = current_slot
		settings_changed.emit(store.get_settings())
		options_status = "Imported all ten classes, settings and last-match choices."
	else:
		options_status = "This file does not contain a valid DeadShot save JSON object."
	show_options(settings_return)
	return success

func _export_save(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		options_status = "Could not write to the selected location."
		show_options(settings_return)
		return false
	file.store_string(JSON.stringify(store.data, "\t"))
	file.close()
	options_status = "Exported all classes and settings to " + path.get_file()
	show_options(settings_return)
	return true

func show_match(hardcore: bool = false) -> void:
	screen = "match"
	menu.hide()
	scoreboard.hide()
	streak_menu.hide()
	hud.hardcore = hardcore
	hud.show()
	touch_controls.visible = touch_enabled
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	replay_overlay.hide()
	if console_open:
		toggle_console()

func show_pause() -> void:
	_switch("pause", true)
	var panel := _center_panel(340, 28)
	_label(panel, "PAUSED", 34, UI.GREEN, 900).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_button(panel, "RESUME", func(): resume_match.emit())
	_button(panel, "CONTROLS", show_controls)
	_button(panel, "OPTIONS", func(): show_options("pause"))
	_button(panel, "LEAVE MATCH", func(): leave_match.emit(), true)
	_button(panel, "QUIT", func(): quit_requested.emit(), true)

func _binding_names(action: String, fallback: String) -> String:
	var names: Array[String] = []
	if InputMap.has_action(action):
		for event in InputMap.action_get_events(action):
			var name := ""
			if event is InputEventKey:
				name = OS.get_keycode_string(event.physical_keycode if event.physical_keycode != 0 else event.keycode)
			elif event is InputEventMouseButton:
				name = {MOUSE_BUTTON_LEFT: "Left mouse", MOUSE_BUTTON_RIGHT: "Right mouse", MOUSE_BUTTON_WHEEL_UP: "Wheel up", MOUSE_BUTTON_WHEEL_DOWN: "Wheel down"}.get(event.button_index, "Mouse %d" % event.button_index)
			if not name.is_empty() and not name in names: names.append(name)
	return " / ".join(names) if not names.is_empty() else fallback

func _control_row(parent: Node, binding: String, description: String) -> void:
	var row := _hbox(parent, 20)
	var key := _label(row, binding, 14, UI.GREEN, 700)
	key.custom_minimum_size.x = 245
	key.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var detail := _label(row, description, 14, UI.WHITE, 400)
	detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func show_controls() -> void:
	_switch("controls", true)
	var panel := PanelContainer.new()
	menu.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var inset := maxf(24, (root.size.x - 920) * 0.5)
	panel.offset_left = inset
	panel.offset_right = -inset
	panel.offset_top = 28
	panel.offset_bottom = -28
	panel.add_theme_stylebox_override("panel", UI.box(Color("10141cf5"), UI.INK, 14, 2, 24))
	var column := _vbox(panel, 14)
	_label(column, "CONTROLS", 30, UI.GREEN, 900)
	_label(column, "The match stays paused while you read. Scroll for controller and touch controls.", 13, UI.MUTED, 400)
	var scroll := ScrollContainer.new()
	column.add_child(scroll)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var content := _vbox(scroll, 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label(content, "KEYBOARD & MOUSE", 15, UI.GREEN, 800)
	_control_row(content, "Mouse movement", "Look around")
	for item in [["forward", "W / Up", "Move forward"], ["back", "S / Down", "Move backward"], ["left", "A / Left", "Strafe left"], ["right", "D / Right", "Strafe right"], ["fire", "Left mouse", "Fire weapon"], ["ads", "Right mouse", "Hold to aim down sights"], ["reload", "R", "Reload"], ["sprint", "Shift", "Sprint while moving forward; lower stance while stationary"], ["crouch", "Ctrl / C", "Lower stance: stand, crouch, then prone"], ["jump", "Space", "Raise stance: prone, crouch, then stand; skip a replay"], ["weapon_primary", "1", "Equip primary weapon"], ["weapon_secondary", "2", "Equip secondary weapon"], ["weapon_next", "Wheel up / Wheel down", "Cycle weapons"], ["melee", "K", "Melee knife"], ["interact", "E", "Interact or pick up a nearby weapon"], ["lethal", "G", "Frag grenade: hold up to 1.25s to charge, release to throw. Other lethals: press to use; double-tap to detonate C4."], ["tactical", "Q", "Flashbang: hold up to 1.25s to charge, release to throw. Other tacticals: press to use."], ["scoreboard", "Tab", "Hold to show the scoreboard"], ["streaks", "Z", "Hold to open scorestreaks, then press a slot key below"], ["pause", "Escape", "Pause / resume; return from this guide to the pause menu"]]:
		_control_row(content, _binding_names(item[0], item[1]), item[2])
	for slot in 3:
		_control_row(content, _binding_names("streak_slot_%d" % (slot + 1), str(slot + 1)), "Activate scorestreak slot %d while holding the scorestreak selector" % (slot + 1))
	_control_row(content, "F11", "Toggle fullscreen")
	_control_row(content, "Backquote (`)", "Open or close the developer console")
	_label(content, "CONTROLLER (XBOX LAYOUT)", 15, UI.GREEN, 800)
	for item in [["Left stick / right stick", "Move / look"], ["RT / LT", "Fire / hold to aim"], ["A / X", "Raise stance / reload"], ["Press left stick", "Sprint while moving forward; lower stance while stationary"], ["RB / LB", "Frag / flashbang: hold to charge, release to throw. Other equipment: press to use."], ["Y", "Open the scorestreak selector"], ["Back / Start", "Scoreboard / pause"]]:
		_control_row(content, item[0], item[1])
	_label(content, "TOUCHSCREEN", 15, UI.GREEN, 800)
	for item in [["Left joystick / right drag", "Move / look"], ["FIRE / ADS", "Fire / aim down sights"], ["R / JMP", "Reload / raise stance"], ["LETH / TAC", "Frag / flashbang: hold to charge, release to throw. Other equipment: press to use."]]:
		_control_row(content, item[0], item[1])
	_button(column, "BACK TO PAUSE", show_pause, true)

func update_hud(state: Dictionary) -> void:
	hud.update_state(state)
	effect_layer.set_direct(state)

func hit_marker(headshot: bool = false) -> void:
	hud.hit_marker(headshot)

func damage_from(angle: float) -> void:
	hud.damage_from(angle)

func add_kill(event: Dictionary) -> void:
	hud.add_kill(event)

func _card(parent: Node, title: String) -> VBoxContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	panel.add_theme_stylebox_override("panel", UI.box(Color("ffffff0a"), Color("ffffff14"), 10, 1, 14))
	var column := _vbox(panel, 8)
	_label(column, title.to_upper(), 13, Color("9fd13e"), 700)
	return column

func _labeled_option(parent: Node, title: String, choices: Array, value: String, action: Callable) -> OptionButton:
	var row := _hbox(parent, 10)
	var caption := _label(row, title, 12, Color("aeb7c4"), 400)
	caption.custom_minimum_size.x = 96
	var option := _option(row, choices, value, action)
	option.add_theme_font_size_override("font_size", 13)
	option.add_theme_font_override("font", UI.font(400))
	option.fit_to_longest_item = false
	return option

func _persist_class() -> void:
	store.set_class(current_slot, loadout)

func _filtered(table_name: String, field: String, value: String) -> Array:
	return tables[table_name].filter(func(item): return item.get(field, "") == value)

func show_class_editor(slot: int = -1) -> void:
	if slot >= 0:
		current_slot = clampi(slot, 0, Store.CLASS_SLOTS - 1)
	loadout = store.get_loadout(current_slot)
	_switch("class")
	var margin := MarginContainer.new()
	menu.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var column := _vbox(scroll, 14)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := _hbox(column)
	_label(header, "CREATE A CLASS", 28, UI.WHITE, 800).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.get_child(0).add_theme_font_override("font", UI.font(800, 2))
	_button(header, "BACK", show_main_menu)
	var tabs := _hbox(column, 6)
	for i in Store.CLASS_SLOTS:
		var tab := _button(tabs, str(i + 1), func(): show_class_editor(i), i != current_slot)
		tab.add_theme_font_size_override("font_size", 14)
		tab.custom_minimum_size.x = 40
		for state_name in ["normal", "hover", "pressed"]:
			var style: StyleBox = tab.get_theme_stylebox(state_name).duplicate()
			style.content_margin_left = 10
			style.content_margin_right = 10
			style.content_margin_top = 8
			style.content_margin_bottom = 8
			tab.add_theme_stylebox_override(state_name, style)
	class_body = _hbox(column, 24)
	var controls := _vbox(class_body, 14)
	controls.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	controls.custom_minimum_size.x = 450
	var aside := _vbox(class_body, 14)
	aside.custom_minimum_size.x = 360
	var name_card := _card(controls, "Class Name")
	var input := LineEdit.new()
	input.text = loadout.name
	input.max_length = 24
	name_card.add_child(input)
	input.text_changed.connect(func(value):
		loadout.name = value
		_persist_class())
	_build_weapon_editor(controls, "primary", ["optic", "barrel", "magazine", "stock", "grip", "perk"])
	_build_weapon_editor(controls, "secondary", ["optic"])
	var equipment := _card(controls, "Equipment")
	for category in ["tactical", "lethal"]:
		_labeled_option(equipment, category.capitalize(), _filtered("equipment", "category", category), loadout[category], func(value):
			loadout[category] = value
			_persist_class())
	_labeled_option(equipment, "Field Upgrade", _filtered("attachments", "slot", "fieldUpgrade"), loadout.fieldUpgrade, func(value):
		loadout.fieldUpgrade = value
		_persist_class())
	var perks := _card(controls, "Perk Package")
	for i in 3:
		var tier: String = ["blue", "red", "gold"][i]
		_labeled_option(perks, tier.capitalize(), _filtered("perks", "tier", tier), loadout.perks[i], func(value):
			loadout.perks[i] = value
			_persist_class())
	var streaks := _card(controls, "Scorestreaks (up to 3)")
	var streak_choices: Array = [{"id": "", "name": "None"}]
	for streak in tables.streaks:
		streak_choices.append({"id": streak.id, "name": "%s (%d)" % [streak.name, streak.cost], "description": "%s — earned at %d streak score." % [streak.name, streak.cost]})
	for i in 3:
		_labeled_option(streaks, "Streak %d" % (i + 1), streak_choices, loadout.streaks[i] if i < loadout.streaks.size() else "", func(value):
			while loadout.streaks.size() < 3: loadout.streaks.append("")
			loadout.streaks[i] = value
			_persist_class())
	var preview_card := _card(aside, "Preview")
	_build_preview(preview_card)
	var camo_card := _card(aside, "Camo")
	var swatches := HFlowContainer.new()
	swatches.add_theme_constant_override("h_separation", 8)
	swatches.add_theme_constant_override("v_separation", 8)
	camo_card.add_child(swatches)
	for camo in tables.camos:
		var color := Color.hex(int(camo.color) * 256 + 255)
		var swatch := Button.new()
		swatch.custom_minimum_size = Vector2(40, 40)
		swatch.tooltip_text = camo.name
		swatch.add_theme_stylebox_override("normal", UI.box(color, UI.GREEN if loadout.camo == camo.id else UI.INK, 8, 3, 0))
		swatches.add_child(swatch)
		swatch.pressed.connect(func():
			loadout.camo = camo.id
			_persist_class()
			_refresh_preview()
			for index in tables.camos.size():
				var swatch_style: StyleBoxFlat = swatches.get_child(index).get_theme_stylebox("normal").duplicate()
				swatch_style.border_color = UI.GREEN if tables.camos[index].id == loadout.camo else UI.INK
				swatches.get_child(index).add_theme_stylebox_override("normal", swatch_style))
	var picker := ColorPickerButton.new()
	picker.custom_minimum_size = Vector2(40, 40)
	picker.tooltip_text = "Custom colour"
	picker.color = _camo_color()
	picker.edit_alpha = false
	for state_name in ["normal", "hover", "pressed"]:
		picker.add_theme_stylebox_override(state_name, UI.box(Color("1c222d"), Color("5b6675"), 8, 2, 4))
	swatches.add_child(picker)
	picker.color_changed.connect(func(color):
		loadout.camo = "#" + color.to_html(false)
		_persist_class()
		_refresh_preview())
	var stats := _card(aside, "Primary Stats")
	stat_bars.clear()
	for key in ["mobility", "range", "accuracy", "damage", "control"]:
		var row := _hbox(stats, 8)
		_label(row, key.capitalize(), 12, Color("aeb7c4")).custom_minimum_size.x = 70
		var progress := ProgressBar.new()
		progress.show_percentage = false
		progress.custom_minimum_size = Vector2(150, 10)
		progress.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		progress.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(progress)
		var value := _label(row, "0", 12)
		value.custom_minimum_size.x = 32
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		stat_bars[key] = {"bar": progress, "label": value}
	_refresh_stats()

func _weapon_choices() -> Array:
	var result: Array = []
	for category in ["assault", "smg", "lmg", "marksman", "sniper", "shotgun", "pistol", "launcher"]:
		for weapon in tables.weapons:
			if weapon.get("category", "") == category and weapon.id != "knife":
				result.append({"id": weapon.id, "name": weapon.name, "description": category.capitalize()})
	return result

func _build_weapon_editor(parent: Node, kind: String, slots: Array) -> void:
	var card := _card(parent, kind)
	var attachments_container: VBoxContainer
	_labeled_option(card, "Weapon", _weapon_choices(), loadout[kind].weaponId, func(value):
		loadout[kind].weaponId = value
		loadout[kind].attachments = []
		_persist_class()
		# Rebuild only attachment selects so changing guns keeps the scroll position.
		var target: VBoxContainer = card.get_node("AttachmentRows")
		_clear(target)
		_add_attachment_rows(target, kind, slots)
		_refresh_stats()
		_refresh_preview())
	attachments_container = _vbox(card, 6)
	attachments_container.name = "AttachmentRows"
	_add_attachment_rows(attachments_container, kind, slots)

func _add_attachment_rows(parent: Node, kind: String, slots: Array) -> void:
	for slot in slots:
		var choices: Array = [{"id": "", "name": "None", "description": "Nothing equipped in this slot."}]
		var chosen := ""
		for attachment in _filtered("attachments", "slot", slot):
			var option: Dictionary = attachment.duplicate(true)
			var modifiers: Array = []
			for key in attachment.get("modifiers", {}):
				modifiers.append("%s %s" % [key, attachment.modifiers[key]])
			if kind == "primary" and not modifiers.is_empty():
				option.name += " (%s)" % ", ".join(modifiers)
			choices.append(option)
			if attachment.id in loadout[kind].attachments:
				chosen = attachment.id
		_labeled_option(parent, slot.capitalize(), choices, chosen, func(value):
			var ids: Array = _filtered("attachments", "slot", slot).map(func(attachment): return attachment.id)
			loadout[kind].attachments = loadout[kind].attachments.filter(func(id): return not id in ids)
			if not value.is_empty(): loadout[kind].attachments.append(value)
			_persist_class()
			_refresh_stats()
			_refresh_preview())

func _camo_color() -> Color:
	if str(loadout.camo).begins_with("#"):
		return Color(loadout.camo)
	for camo in tables.camos:
		if camo.id == loadout.camo:
			return Color.hex(int(camo.color) * 256 + 255)
	return Color("2b2f36")

func _build_preview(parent: Node) -> void:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(330, 260)
	container.stretch = true
	parent.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(360, 260)
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color("090c11")
	# Sky ambient so the weapon's metal parts pick up reflected light instead of
	# reading as black silhouettes against the menu background.
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c4d4ee")
	environment.environment.ambient_light_energy = 1.15
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.environment.tonemap_exposure = 1.0
	environment.environment.tonemap_white = 2.0
	environment.environment.glow_enabled = true
	environment.environment.glow_intensity = 0.35
	environment.environment.glow_hdr_threshold = 1.2
	viewport.add_child(environment)
	var key := DirectionalLight3D.new()
	key.light_color = Color("fff4e0")
	key.light_energy = 2.4
	viewport.add_child(key)
	key.look_at_from_position(Vector3(0, 0, 0.4) + Vector3(0.6, 1, 0.5).normalized() * 2.0, Vector3(0, 0, 0))
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("9fc4ff")
	rim.light_energy = 1.4
	viewport.add_child(rim)
	rim.look_at_from_position(Vector3(0, 0, 0.4) + Vector3(-0.8, 0.5, 0.6), Vector3(0, 0, 0))
	preview_camera = Camera3D.new()
	preview_camera.position = Vector3.ZERO
	preview_camera.fov = 55
	preview_camera.near = 0.05
	viewport.add_child(preview_camera)
	class_preview = Node3D.new()
	viewport.add_child(class_preview)
	_refresh_preview()

func _refresh_preview() -> void:
	if not is_instance_valid(class_preview):
		return
	_clear(class_preview)
	var factory_path := "res://scripts/visuals/visual_factory.gd"
	if ResourceLoader.exists(factory_path):
		var factory: GDScript = load(factory_path)
		var previous_environment: Dictionary = factory.environment
		factory.environment = {}
		var model: Node3D = factory.create_weapon(loadout.primary.weaponId, _camo_color(), loadout.primary.attachments)
		factory.environment = previous_environment
		class_preview.add_child(model)
		# Show the weapon's side profile, framed from its real bounds so every
		# weapon and attachment combination fills the panel consistently.
		model.rotation.y = PI * 0.5
		var bounds := _model_bounds(model)
		var centre := bounds.get_center()
		var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
		var distance := maxf(0.35, extent * 0.85)
		model.position = Vector3(-centre.x, -centre.y, -centre.z - distance)

func _model_bounds(model: Node) -> AABB:
	var bounds := AABB()
	var found := false
	for child in model.get_children():
		if child is MeshInstance3D:
			var box: AABB = child.transform * child.mesh.get_aabb()
			bounds = box if not found else bounds.merge(box)
			found = true
		elif child is Node3D:
			var nested := _model_bounds(child)
			if nested.size != Vector3.ZERO or nested.position != Vector3.ZERO:
				bounds = nested if not found else bounds.merge(nested)
				found = true
	return bounds

func _refresh_stats() -> void:
	if stat_bars.is_empty():
		return
	var definition: Dictionary = {}
	for weapon in tables.weapons:
		if weapon.id == loadout.primary.weaponId:
			definition = weapon.duplicate(true)
	if definition.is_empty():
		return
	var mobility: float = definition.mobility
	var damage: float = definition.damage
	var far_range: float = definition.range.far
	var vertical: float = definition.recoil.vertical
	var horizontal: float = definition.recoil.horizontal
	for attachment in tables.attachments:
		if not attachment.id in loadout.primary.attachments:
			continue
		var modifiers: Dictionary = attachment.modifiers
		mobility += modifiers.get("mobilityAdd", 0)
		damage *= modifiers.get("damageMult", 1)
		far_range *= modifiers.get("rangeMult", 1)
		vertical *= modifiers.get("recoilMult", 1)
		horizontal *= modifiers.get("recoilMult", 1)
	var values := {"mobility": clampf(mobility, 1, 100), "range": clampf(far_range, 0, 200) / 2, "accuracy": clampf(100 - horizontal * 20, 0, 100), "damage": clampf(damage, 0, 120) * 0.83, "control": clampf(100 - vertical * 15, 0, 100)}
	for key in values:
		stat_bars[key].bar.value = values[key]
		stat_bars[key].label.text = str(roundi(values[key]))

func _score_table(parent: Node, rows: Array, mode: String, blue: int, red: int) -> void:
	_label(parent, "FREE-FOR-ALL" if mode == "ffa" or mode == "gungame" else "BLUE %d  —  %d RED" % [blue, red], 24, UI.GREEN, 800).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var sorted := rows.duplicate(true)
	sorted.sort_custom(func(a, b):
		if a.get("score", 0) == b.get("score", 0): return a.get("kills", 0) > b.get("kills", 0)
		return a.get("score", 0) > b.get("score", 0))
	var groups: Array = ["ffa"] if mode == "ffa" or mode == "gungame" else ["blue", "red"]
	for team in groups:
		if team != "ffa":
			_label(parent, team.to_upper(), 16, Hud.team_color(team), 800)
		var grid := GridContainer.new()
		grid.columns = 5
		grid.add_theme_constant_override("h_separation", 14)
		grid.add_theme_constant_override("v_separation", 5)
		parent.add_child(grid)
		for caption in ["PLAYER", "K", "D", "A", "SCORE"]:
			var heading := _label(grid, caption, 12, UI.MUTED, 700)
			heading.custom_minimum_size.x = 240 if caption == "PLAYER" else 56
			if caption == "PLAYER": heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			else: heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		for row in sorted:
			if team != "ffa" and row.get("team", "blue") != team:
				continue
			var is_player: bool = row.get("isPlayer", false)
			var cells := [("▸ " if is_player else "") + str(row.get("name", "Player")), str(row.get("kills", 0)), str(row.get("deaths", 0)), str(row.get("assists", 0)), str(row.get("score", 0))]
			for i in cells.size():
				var cell := _label(grid, cells[i], 14, Hud.team_color(row.get("team", "ffa")) if i == 0 else UI.GREEN if is_player else UI.WHITE, 700)
				if i > 0:
					cell.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func show_scoreboard(is_visible: bool, rows: Array = [], blue: int = 0, red: int = 0, mode: String = "tdm") -> void:
	scoreboard.visible = is_visible
	if not is_visible:
		return
	_clear(scoreboard)
	scoreboard.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var center := CenterContainer.new()
	scoreboard.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = minf(680, root.size.x - 48)
	panel.add_theme_stylebox_override("panel", UI.box(Color("10141ced"), UI.INK, 14, 2, 24))
	center.add_child(panel)
	_score_table(_vbox(panel, 12), rows, mode, blue, red)

func show_postmatch(rows: Array, _blue: int, _red: int, _mode: String, winner: String, best_play_kills: int = 0) -> void:
	_switch("postmatch")
	var background: ColorRect = menu.get_child(0)
	var shader := Shader.new()
	shader.code = """shader_type canvas_item;
void fragment() {
    vec2 dimensions = 1.0 / SCREEN_PIXEL_SIZE;
    float radius = length((UV - vec2(0.5,0.35)) * dimensions) / length(vec2(0.5,0.65) * dimensions);
    COLOR = vec4(mix(vec3(20.0,32.0,44.0)/255.0, vec3(5.0,7.0,10.0)/255.0, clamp(radius/0.7,0.0,1.0)),1.0);
}"""
	background.material = ShaderMaterial.new()
	background.material.shader = shader
	var center := CenterContainer.new()
	menu.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := _vbox(center, 12)
	var title := _label(column, winner if not winner.is_empty() else "Match Over", 44, Color("b6ff5e"), 900)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_color_override("font_shadow_color", Color.BLACK)
	title.add_theme_constant_override("shadow_offset_x", 3)
	title.add_theme_constant_override("shadow_offset_y", 3)
	var table := _vbox(column, 4)
	table.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var monospace := UI.mono_font()
	for row in rows.slice(0, 12):
		# The source DOM collapses its literal separator spaces to single spaces.
		var text := "%s %d/%d/%d %d" % [row.get("name", "Player"), row.get("kills", 0), row.get("deaths", 0), row.get("assists", 0), row.get("score", 0)]
		var label := _label(table, text, 14, Color("ffd166") if row.get("isPlayer", false) else Color("ccffee"), 400)
		label.add_theme_font_override("font", monospace)
	var footer := _hbox(column, 12)
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	if best_play_kills >= 2:
		var best := _button(footer, "▶ BEST PLAY (%d KILLS)" % best_play_kills, func(): best_play_requested.emit())
		best.add_theme_stylebox_override("normal", UI.gradient_box(Color("ffd166"), Color("e0a92e")))
		best.add_theme_stylebox_override("hover", UI.gradient_box(Color("ffd166").lightened(0.08), Color("e0a92e").lightened(0.08)))
	_button(footer, "Continue", func(): leave_match.emit())

func show_streak_menu(options: Array) -> void:
	_clear(streak_menu)
	streak_menu.show()
	streak_menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var panel := PanelContainer.new()
	streak_menu.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	panel.offset_left = -155
	panel.offset_right = 155
	panel.offset_bottom = -120
	panel.offset_top = -375
	panel.add_theme_stylebox_override("panel", UI.box(Color("10141cf0"), UI.INK, 12, 2, 18))
	var content := _vbox(panel, 8)
	_label(content, "SCORESTREAKS", 13, UI.GREEN, 800).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label(content, "Hold Z, press 1 – 3", 11, UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if options.is_empty():
		_label(content, "No streaks earned yet", 13, UI.MUTED)
	for i in options.size():
		var option: Dictionary = options[i]
		var button := _button(content, "%d   %s" % [int(option.get("slot", i)) + 1, option.name], func(): streak_selected.emit(option.id))
		button.disabled = not option.get("available", false)

func hide_streak_menu() -> void:
	streak_menu.hide()

func show_replay(title: String, hint: String, color: Color = Color("ff7a7a")) -> void:
	menu.hide()
	hud.hide()
	touch_controls.hide()
	scoreboard.hide()
	streak_menu.hide()
	_clear(replay_overlay)
	replay_overlay.show()
	var title_label := _label(replay_overlay, title, 32, color, 900)
	title_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	title_label.offset_top = -112
	title_label.offset_bottom = -76
	title_label.add_theme_font_size_override("font_size", 30)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var hint_label := _label(replay_overlay, hint, 14, UI.GREEN, 700)
	hint_label.add_theme_font_override("font", UI.font(700, 1))
	hint_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	hint_label.offset_top = -74
	hint_label.offset_bottom = -56
	hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func hide_replay() -> void:
	replay_overlay.hide()

func show_multiplayer() -> void:
	lobby_state = {}
	network_status = ""
	_render_multiplayer()

func _render_multiplayer() -> void:
	_switch("multiplayer")
	var panel := _center_panel(520, 32)
	_label(panel, "MULTIPLAYER", 30, UI.GREEN, 900)
	if lobby_state.is_empty():
		_field(panel, "Server URL", network_config.url, func(value): network_config.url = value.strip_edges())
		_field(panel, "Your Name", network_config.name, func(value): network_config.name = value.left(24)).max_length = 24
		_field(panel, "Room Code (blank = new room)", network_config.room, func(value): network_config.room = value.strip_edges().to_upper())
		var connect_buttons := _hbox(panel, 12)
		_button(connect_buttons, "HOST GAME", func(): _connect_multiplayer(true)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_button(connect_buttons, "JOIN GAME", func(): _connect_multiplayer(false)).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_button(panel, "BACK", func():
			multiplayer_leave.emit()
			show_main_menu(), true)
	else:
		var host: bool = lobby_state.get("isHost", false)
		_label(panel, "Room %s  •  %s" % [lobby_state.get("room", network_config.room), "You are the host" if host else "Waiting for host"], 14, UI.GREEN)
		var roster := _card(panel, "Players")
		for player in lobby_state.get("players", []):
			var row := _hbox(roster)
			var name_text: String = player.get("name", "Player")
			if player.get("id", -1) == lobby_state.get("selfId", -2): name_text += " (you)"
			if player.get("id", -1) == lobby_state.get("hostId", -2): name_text += " ★"
			_label(row, name_text, 13, Hud.team_color(player.get("team", "ffa"))).size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_label(row, "READY" if player.get("ready", false) else "…", 13, UI.GREEN if player.get("ready", false) else UI.MUTED)
		var settings: Dictionary = lobby_state.get("settings", Store.default_match_config())
		if host:
			_labeled_option(panel, "Map", MAPS, settings.mapId, func(value): _lobby_setting("mapId", value))
			_labeled_option(panel, "Mode", MODES, settings.mode, func(value): _lobby_setting("mode", value))
			var bots: Array = []
			for count in 17: bots.append({"id": str(count), "name": str(count)})
			_labeled_option(panel, "Bots", bots, str(settings.botCount), func(value): _lobby_setting("botCount", int(value)))
			_labeled_option(panel, "Difficulty", DIFFICULTIES, settings.difficulty, func(value): _lobby_setting("difficulty", value))
			_labeled_option(panel, "Hardcore", [{"id": "off", "name": "Off"}, {"id": "on", "name": "On"}], "on" if settings.hardcore else "off", func(value): _lobby_setting("hardcore", value == "on"))
		else:
			_label(panel, "%s · %s · %d bots · %s%s" % [settings.mapId.replace("_", " ").capitalize(), settings.mode.to_upper(), settings.botCount, settings.difficulty, " · hardcore" if settings.hardcore else ""], 13, UI.MUTED).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		var footer := _hbox(panel, 12)
		_button(footer, "UNREADY" if lobby_state.get("ready", false) else "READY", func():
			lobby_state.ready = not lobby_state.get("ready", false)
			multiplayer_ready.emit(lobby_state.ready)
			_render_multiplayer()).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if host:
			_button(footer, "START MATCH", func(): multiplayer_start.emit()).size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_button(panel, "LEAVE", func():
			multiplayer_leave.emit()
			lobby_state = {}
			show_main_menu(), true)
	if not network_status.is_empty():
		_label(panel, network_status, 13, Color("ff9b6b")).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART

func _connect_multiplayer(as_host: bool) -> void:
	if network_config.room.is_empty():
		if not as_host:
			set_network_status("Enter a room code to join, or use HOST GAME to make one.")
			return
		var alphabet := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
		for i in 4:
			network_config.room += alphabet[randi() % alphabet.length()]
	network_status = "Connecting to %s …" % network_config.url
	_render_multiplayer()
	var config := network_config.duplicate(true)
	config.asHost = as_host
	multiplayer_connect.emit(config)

func _lobby_setting(key: String, value: Variant) -> void:
	if not lobby_state.has("settings"):
		lobby_state.settings = Store.default_match_config()
	lobby_state.settings[key] = value
	multiplayer_settings.emit(lobby_state.settings.duplicate(true))

func set_lobby_state(state: Dictionary) -> void:
	lobby_state = state.duplicate(true)
	network_status = ""
	_render_multiplayer()

func set_network_status(text: String) -> void:
	network_status = text
	if screen == "multiplayer":
		_render_multiplayer()

func _build_console() -> void:
	console_panel = PanelContainer.new()
	root.add_child(console_panel)
	console_panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	console_panel.anchor_bottom = 0.4
	console_panel.add_theme_stylebox_override("panel", UI.box(Color("06080beb"), Color("b6ff5e"), 0, 1, 10))
	var column := _vbox(console_panel, 6)
	console_output = RichTextLabel.new()
	console_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	console_output.scroll_following = true
	console_output.selection_enabled = true
	console_output.add_theme_color_override("default_color", Color("ccffee"))
	var monospace := UI.mono_font()
	console_output.add_theme_font_override("normal_font", monospace)
	console_output.add_theme_font_size_override("normal_font_size", 13)
	column.add_child(console_output)
	console_input = LineEdit.new()
	console_input.placeholder_text = "command… (try: help)"
	console_input.add_theme_font_override("font", monospace)
	console_input.add_theme_font_size_override("font_size", 13)
	console_input.add_theme_color_override("font_color", Color("b6ff5e"))
	column.add_child(console_input)
	console_input.text_submitted.connect(func(text):
		var command: String = text.strip_edges()
		if command.is_empty(): return
		console_print("> " + command)
		console_input.clear()
		console_command.emit(command))
	console_input.gui_input.connect(func(event):
		if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
			toggle_console()
			console_input.accept_event())
	console_print("DeadShot dev console. Type 'help'.")
	console_panel.hide()

func toggle_console() -> void:
	console_open = not console_open
	console_panel.visible = console_open
	touch_controls.visible = screen == "match" and touch_enabled
	touch_controls.blocked_top = 0.4 if console_open else 0.0
	if console_open:
		_suspend_console_keys()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		console_input.grab_focus()
	else:
		_restore_console_keys()
		console_input.release_focus()
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if screen == "match" else Input.MOUSE_MODE_VISIBLE

func console_print(text: String) -> void:
	console_output.append_text(text + "\n")

func show_loading(progress: float = 0, status: String = "Loading…") -> void:
	_switch("loading")
	var center := CenterContainer.new()
	menu.add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var column := _vbox(center, 20)
	_label(column, "DEADSHOT", 88, Color("b6ff5e"), 900).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var bar := ProgressBar.new()
	bar.custom_minimum_size = Vector2(420, 14)
	bar.show_percentage = false
	bar.value = clampf(progress * 100, 0, 100)
	column.add_child(bar)
	_label(column, status, 15, UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _build_screen_effects() -> void:
	effect_layer = preload("res://scripts/ui/screen_effects.gd").new()
	root.add_child(effect_layer)

func apply_screen_effect(kind: String, intensity: float, duration: float) -> void:
	effect_layer.apply_effect(kind, intensity, duration)

func clear_screen_effects() -> void:
	if is_instance_valid(effect_layer):
		effect_layer.clear()

func set_touch_enabled(enabled: bool) -> void:
	touch_enabled = enabled
	touch_controls.visible = enabled and screen == "match" and not replay_overlay.visible

func _update_screen_effects(delta: float) -> void:
	effect_layer.update_effects(delta)
