extends Control
## Interactive Create-a-Class Armory. Cards share one details panel and every
## selection edits the existing save-schema loadout directly.
signal changed
signal back_requested
signal slot_selected(index: int)

const UI = preload("res://scripts/ui/ui_theme.gd")
const Icons = preload("res://scripts/ui/armory_icons.gd")
const Factory = preload("res://scripts/visuals/visual_factory.gd")
const PRIMARY_SLOTS := ["optic", "barrel", "magazine", "stock", "grip", "perk"]
const SLOT_NAMES := {"optic": "OPTIC", "barrel": "BARREL", "magazine": "MAGAZINE", "stock": "STOCK", "grip": "GRIP", "perk": "GUN PERK"}
const CATEGORY_NAMES := {"assault": "ASSAULT RIFLE", "smg": "SMG", "lmg": "LMG", "marksman": "MARKSMAN RIFLE", "sniper": "SNIPER RIFLE", "shotgun": "SHOTGUN", "pistol": "PISTOL", "launcher": "LAUNCHER"}
const THUMBNAILS := {"assault": "m4", "smg": "mp5", "lmg": "m249", "marksman": "mk14", "sniper": "barrett", "shotgun": "spas12", "pistol": "m9", "launcher": "rpg7"}
const TIER_COLORS := [Color("63baff"), Color("ff7069"), Color("ffd166")]
const EQUIPMENT_DESCRIPTIONS := {
	"flashbang": "Blinds and deafens enemies near the blast. Hold the tactical input to charge the throw.",
	"smoke": "Deploys an obscuring smoke cloud that blocks clear sightlines through the target area.",
	"stun": "Slows and disorients enemies caught in the blast, disrupting their aim and movement.",
	"snapshot": "Reveals enemy positions briefly through cover for you and your team.",
	"frag": "A timed explosive grenade. Hold the lethal input to charge the throw, then release.",
	"semtex": "An explosive charge that sticks to surfaces and targets before detonating.",
	"knife": "A fast thrown blade for precise, quiet eliminations at close range.",
	"c4": "A remote explosive charge. Place it, then detonate it when enemies move into range.",
	"molotov": "Creates a pool of fire that damages enemies and denies the area.",
	"thermite": "Burns intensely after impact, dealing damage over time in a small area.",
	"claymore": "A directional proximity mine for watching flanks and protecting objectives.",
}

var tables: Dictionary = {}
var loadout: Dictionary = {}
var current_slot := 0
var page := "armory"
var weapon_kind := "primary"
var attachment_slot := "optic"
var kit_mode := "tactical"
var streak_slot := 0
var page_host: Control
var page_button: Button
var summary_label: Label
var weapon_grid: GridContainer
var attachment_grid: GridContainer
var attachment_tabs: HFlowContainer
var perk_list: VBoxContainer
var camo_swatches: HFlowContainer
var kit_grid: GridContainer
var kit_tabs: HFlowContainer
var kit_slot_row: HBoxContainer
var detail_title: Label
var detail_description: Label
var detail_modifiers: Label
var weapon_title: Label
var weapon_subtitle: Label
var stat_bars: Dictionary = {}
var preview_pivot: Node3D
var preview_time := 0.0
var _textures: Dictionary = {}

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_shell()
	_show_page("armory")

func _process(delta: float) -> void:
	if is_instance_valid(preview_pivot):
		preview_time += delta * 0.45
		preview_pivot.rotation.y = -sin(preview_time) * 0.22

func _build_shell() -> void:
	var margin := MarginContainer.new()
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	var column := _vbox(margin, 10)
	var header := _hbox(column, 12)
	var heading := _vbox(header, 0)
	_label(heading, "ARMORY", 30, UI.GREEN, 900)
	_label(heading, "CREATE A CLASS  /  WEAPONS & EQUIPMENT", 10, UI.MUTED, 600)
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(space)
	var name_input := LineEdit.new()
	name_input.name = "ClassName"
	name_input.text = str(loadout.get("name", "Custom"))
	name_input.max_length = 24
	name_input.custom_minimum_size = Vector2(170, 38)
	name_input.tooltip_text = "Class name"
	header.add_child(name_input)
	name_input.text_changed.connect(func(value):
		loadout.name = value
		changed.emit())
	page_button = _button(header, "FIELD KIT", _toggle_page, true)
	page_button.name = "FieldKitToggle"
	_button(header, "BACK", func(): back_requested.emit(), true)
	var tabs := _hbox(column, 6)
	_label(tabs, "CLASS", 11, UI.MUTED, 700)
	for index in range(10):
		var tab := _button(tabs, str(index + 1), func(): slot_selected.emit(index), index != current_slot)
		tab.name = "ClassTab%d" % index
		tab.custom_minimum_size = Vector2(35, 29)
		tab.add_theme_font_size_override("font_size", 12)
		for state_name in ["normal", "hover", "pressed"]:
			var style: StyleBox = tab.get_theme_stylebox(state_name).duplicate()
			style.content_margin_left = 4
			style.content_margin_right = 4
			style.content_margin_top = 4
			style.content_margin_bottom = 4
			tab.add_theme_stylebox_override(state_name, style)
	var tab_space := Control.new()
	tab_space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tabs.add_child(tab_space)
	summary_label = _label(tabs, "", 11, UI.MUTED, 600)
	page_host = Control.new()
	page_host.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.add_child(page_host)
	_refresh_summary()

func _toggle_page() -> void:
	_show_page("kit" if page == "armory" else "armory")

func _show_page(next: String) -> void:
	page = next
	_clear(page_host)
	preview_pivot = null
	stat_bars.clear()
	page_button.text = "FIELD KIT" if page == "armory" else "ARMORY"
	if page == "armory":
		_build_armory()
	else:
		_build_kit()
	_refresh_summary()

func _build_armory() -> void:
	var main := _hbox(page_host, 12)
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var weapons := _panel(main, "WEAPON LIST", 240)
	var kind_tabs := _hbox(weapons, 6)
	for kind in ["primary", "secondary"]:
		var button := _button(kind_tabs, kind.to_upper(), func(): _set_weapon_kind(kind), weapon_kind != kind)
		button.name = "WeaponKind_" + kind
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.custom_minimum_size.y = 30
		button.add_theme_font_size_override("font_size", 11)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	weapons.add_child(scroll)
	weapon_grid = GridContainer.new()
	weapon_grid.columns = 2
	weapon_grid.add_theme_constant_override("h_separation", 7)
	weapon_grid.add_theme_constant_override("v_separation", 7)
	weapon_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(weapon_grid)

	var center := _vbox(main, 10)
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var preview := _panel(center, "")
	preview.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.get_parent().custom_minimum_size.y = 235
	var heading := _hbox(preview, 8)
	var titles := _vbox(heading, 1)
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	weapon_title = _label(titles, "", 22, UI.WHITE, 800)
	weapon_subtitle = _label(titles, "", 10, UI.GREEN, 600)
	_label(heading, "LIVE 3D", 10, UI.MUTED, 700)
	_build_preview(preview)
	_build_stats(preview)

	var attachments := _panel(center, "ATTACHMENTS  /  SELECT A SLOT")
	attachments.get_parent().custom_minimum_size.y = 205
	attachment_tabs = HFlowContainer.new()
	attachment_tabs.add_theme_constant_override("h_separation", 5)
	attachment_tabs.add_theme_constant_override("v_separation", 5)
	attachments.add_child(attachment_tabs)
	attachment_grid = GridContainer.new()
	attachment_grid.columns = 5
	attachment_grid.add_theme_constant_override("h_separation", 7)
	attachment_grid.add_theme_constant_override("v_separation", 7)
	attachment_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	attachments.add_child(attachment_grid)

	var right := _vbox(main, 10)
	right.custom_minimum_size.x = 280
	var details := _panel(right, "ITEM DETAILS")
	details.get_parent().custom_minimum_size.y = 142
	detail_title = _label(details, "", 17, UI.WHITE, 800)
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_description = _label(details, "", 11, UI.MUTED, 400)
	detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_description.max_lines_visible = 3
	detail_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_modifiers = _label(details, "", 10, UI.GREEN, 600)
	detail_modifiers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_modifiers.max_lines_visible = 2
	var perks := _panel(right, "PERK PACKAGE  /  1 · 2 · 3")
	perks.get_parent().size_flags_vertical = Control.SIZE_EXPAND_FILL
	perk_list = _vbox(perks, 5)
	var camo := _panel(right, "CAMO")
	camo_swatches = HFlowContainer.new()
	camo_swatches.add_theme_constant_override("h_separation", 3)
	camo_swatches.add_theme_constant_override("v_separation", 3)
	camo.add_child(camo_swatches)

	_refresh_weapon_grid()
	_refresh_attachment_tabs()
	_refresh_perks()
	_refresh_camo()
	_refresh_preview()
	var weapon := _weapon(loadout[weapon_kind].weaponId)
	_show_detail(str(weapon.get("name", "Weapon")), _weapon_description(weapon), _weapon_modifiers(weapon), UI.GREEN)

func _set_weapon_kind(kind: String) -> void:
	weapon_kind = kind
	attachment_slot = "optic"
	_show_page("armory")

func _weapon_choices() -> Array:
	return tables.get("weapons", []).filter(func(weapon): return weapon.id != "knife")

func _weapon(id: String) -> Dictionary:
	for weapon in tables.get("weapons", []):
		if weapon.id == id:
			return weapon
	return {}

func _refresh_weapon_grid() -> void:
	if not is_instance_valid(weapon_grid):
		return
	_clear(weapon_grid)
	for definition in _weapon_choices():
		var item: Dictionary = definition.duplicate(true)
		item.description = _weapon_description(definition)
		item.modifiersText = _weapon_modifiers(definition)
		var selected: bool = loadout[weapon_kind].weaponId == definition.id
		_item_card(weapon_grid, "weapon", item, selected, func(): _select_weapon(definition.id), Vector2(103, 94), UI.GREEN, str(CATEGORY_NAMES.get(definition.category, definition.category)))

func _select_weapon(id: String) -> void:
	if loadout[weapon_kind].weaponId != id:
		loadout[weapon_kind].weaponId = id
		loadout[weapon_kind].attachments = []
		changed.emit()
	_refresh_weapon_grid()
	_refresh_attachment_grid()
	_refresh_preview()
	var weapon := _weapon(id)
	_show_detail(str(weapon.get("name", "Weapon")), _weapon_description(weapon), _weapon_modifiers(weapon), UI.GREEN)

func _refresh_attachment_tabs() -> void:
	if not is_instance_valid(attachment_tabs):
		return
	_clear(attachment_tabs)
	var slots := PRIMARY_SLOTS if weapon_kind == "primary" else ["optic"]
	for slot in slots:
		var button := _button(attachment_tabs, str(SLOT_NAMES[slot]), func():
			attachment_slot = slot
			_refresh_attachment_tabs()
			_refresh_attachment_grid(), attachment_slot != slot)
		button.name = "AttachmentSlot_" + slot
		button.add_theme_font_size_override("font_size", 9)
		button.custom_minimum_size = Vector2(72 if slot != "magazine" else 88, 27)
	_refresh_attachment_grid()

func _slot_attachments(slot: String) -> Array:
	return tables.get("attachments", []).filter(func(attachment): return attachment.get("slot", "") == slot)

func _selected_attachment() -> String:
	for attachment in _slot_attachments(attachment_slot):
		if attachment.id in loadout[weapon_kind].attachments:
			return attachment.id
	return ""

func _refresh_attachment_grid() -> void:
	if not is_instance_valid(attachment_grid):
		return
	_clear(attachment_grid)
	var none := {"id": "", "cardId": "none", "name": "No Attachment", "description": "Leave this slot empty.", "modifiersText": "No stat changes.", "slot": attachment_slot}
	var choices: Array = [none]
	choices.append_array(_slot_attachments(attachment_slot))
	for definition in choices:
		var item: Dictionary = definition.duplicate(true)
		if not item.has("modifiersText"):
			item.modifiersText = _modifier_summary(definition.get("modifiers", {}))
		var selected: bool = _selected_attachment() == definition.id
		_item_card(attachment_grid, "attachment", item, selected, func(): _equip_attachment(definition.id), Vector2(126, 103), UI.GREEN, str(SLOT_NAMES.get(attachment_slot, attachment_slot)))

func _equip_attachment(id: String) -> void:
	var ids: Array = _slot_attachments(attachment_slot).map(func(attachment): return attachment.id)
	loadout[weapon_kind].attachments = loadout[weapon_kind].attachments.filter(func(equipped): return not equipped in ids)
	if not id.is_empty():
		loadout[weapon_kind].attachments.append(id)
	changed.emit()
	_refresh_attachment_grid()
	_refresh_preview()

func _refresh_perks() -> void:
	if not is_instance_valid(perk_list):
		return
	_clear(perk_list)
	var tiers := ["blue", "red", "gold"]
	for tier_index in range(3):
		_label(perk_list, "PERK %d  /  %s" % [tier_index + 1, tiers[tier_index].to_upper()], 9, TIER_COLORS[tier_index], 700)
		var row := _hbox(perk_list, 5)
		for perk in tables.get("perks", []):
			if perk.tier != tiers[tier_index]:
				continue
			var item: Dictionary = perk.duplicate(true)
			var selected: bool = loadout.perks[tier_index] == perk.id
			_item_card(row, "perk", item, selected, func(): _select_perk(tier_index, perk.id), Vector2(78, 77), TIER_COLORS[tier_index])

func _select_perk(tier: int, id: String) -> void:
	loadout.perks[tier] = id
	changed.emit()
	_refresh_perks()

func _refresh_camo() -> void:
	if not is_instance_valid(camo_swatches):
		return
	_clear(camo_swatches)
	for camo in tables.get("camos", []):
		var color := Color.hex(int(camo.color) * 256 + 255)
		var swatch := Button.new()
		swatch.name = "Camo_" + str(camo.id)
		swatch.custom_minimum_size = Vector2(20, 20)
		swatch.tooltip_text = str(camo.name)
		swatch.add_theme_stylebox_override("normal", UI.box(color, UI.GREEN if loadout.camo == camo.id else UI.INK, 5, 2, 0))
		swatch.add_theme_stylebox_override("hover", UI.box(color.lightened(0.1), UI.GREEN, 5, 2, 0))
		camo_swatches.add_child(swatch)
		swatch.pressed.connect(func():
			loadout.camo = camo.id
			changed.emit()
			_refresh_camo()
			_refresh_preview())
	var picker := ColorPickerButton.new()
	picker.name = "CustomCamo"
	picker.custom_minimum_size = Vector2(22, 22)
	picker.tooltip_text = "Custom camo colour"
	picker.color = _camo_color()
	picker.edit_alpha = false
	for state_name in ["normal", "hover", "pressed"]:
		picker.add_theme_stylebox_override(state_name, UI.box(Color("1c222d"), UI.GREEN, 5, 2, 2))
	camo_swatches.add_child(picker)
	picker.color_changed.connect(func(color):
		loadout.camo = "#" + color.to_html(false)
		changed.emit()
		_refresh_preview())

func _build_preview(parent: Node) -> void:
	var container := SubViewportContainer.new()
	container.name = "ArmoryPreview"
	container.custom_minimum_size = Vector2(460, 145)
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(container)
	var viewport := SubViewport.new()
	viewport.size = Vector2i(640, 230)
	viewport.transparent_bg = true
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	container.add_child(viewport)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0, 0, 0, 0)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color("c4d4ee")
	environment.environment.ambient_light_energy = 0.85
	environment.environment.tonemap_mode = Environment.TONE_MAPPER_ACES
	environment.environment.tonemap_exposure = 0.9
	viewport.add_child(environment)
	var key := DirectionalLight3D.new()
	key.light_color = Color("fff4e0")
	key.light_energy = 1.8
	viewport.add_child(key)
	key.look_at_from_position(Vector3(1.2, 2, 1.5), Vector3.ZERO)
	var rim := DirectionalLight3D.new()
	rim.light_color = Color("9fc4ff")
	rim.light_energy = 1.25
	viewport.add_child(rim)
	rim.look_at_from_position(Vector3(-1.8, 0.8, 0.5), Vector3.ZERO)
	var camera := Camera3D.new()
	camera.position = Vector3.ZERO
	camera.fov = 48
	camera.near = 0.02
	viewport.add_child(camera)
	camera.make_current()
	preview_pivot = Node3D.new()
	viewport.add_child(preview_pivot)

func _refresh_preview() -> void:
	if not is_instance_valid(preview_pivot):
		return
	_clear(preview_pivot)
	var previous_environment: Dictionary = Factory.environment
	Factory.environment = {}
	var model: Node3D = Factory.create_weapon(loadout[weapon_kind].weaponId, _camo_color(), loadout[weapon_kind].attachments)
	Factory.environment = previous_environment
	preview_pivot.add_child(model)
	model.rotation.y = PI * 0.5
	var bounds := _model_bounds(model)
	var centre := bounds.get_center()
	var extent := maxf(bounds.size.x, maxf(bounds.size.y, bounds.size.z))
	model.position = -centre - Vector3(0, 0, maxf(0.35, extent * 0.92))
	var weapon := _weapon(loadout[weapon_kind].weaponId)
	weapon_title.text = str(weapon.get("name", "WEAPON")).to_upper()
	weapon_subtitle.text = "%s  /  %s  /  %s" % [weapon_kind.to_upper(), CATEGORY_NAMES.get(weapon.get("category", ""), "WEAPON"), str(weapon.get("fireMode", "auto")).to_upper()]
	_refresh_stats()

func _model_bounds(model: Node) -> AABB:
	var bounds := AABB()
	var found := false
	for child in model.get_children():
		if child is MeshInstance3D and child.visible:
			var box: AABB = child.transform * child.mesh.get_aabb()
			bounds = box if not found else bounds.merge(box)
			found = true
		elif child is Node3D:
			var nested := _model_bounds(child)
			if nested.size != Vector3.ZERO or nested.position != Vector3.ZERO:
				bounds = nested if not found else bounds.merge(nested)
				found = true
	return bounds

func _build_stats(parent: Node) -> void:
	var row := _hbox(parent, 8)
	for key in ["damage", "mobility", "range", "accuracy", "control"]:
		var column := _vbox(row, 2)
		column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_label(column, key.to_upper(), 8, UI.MUTED, 600)
		var progress := ProgressBar.new()
		progress.show_percentage = false
		progress.custom_minimum_size.y = 5
		progress.max_value = 100
		column.add_child(progress)
		stat_bars[key] = progress

func _refresh_stats() -> void:
	if stat_bars.is_empty():
		return
	var definition := _weapon(loadout[weapon_kind].weaponId)
	if definition.is_empty():
		return
	var mobility := float(definition.mobility)
	var damage := float(definition.damage)
	var far_range := float(definition.range.far)
	var vertical := float(definition.recoil.vertical)
	var horizontal := float(definition.recoil.horizontal)
	for attachment in tables.get("attachments", []):
		if not attachment.id in loadout[weapon_kind].attachments:
			continue
		var modifiers: Dictionary = attachment.modifiers
		mobility += float(modifiers.get("mobilityAdd", 0))
		damage *= float(modifiers.get("damageMult", 1))
		far_range *= float(modifiers.get("rangeMult", 1))
		vertical *= float(modifiers.get("recoilMult", 1))
		horizontal *= float(modifiers.get("recoilMult", 1))
	var values := {"damage": clampf(damage, 0, 120) * 0.83, "mobility": clampf(mobility, 1, 100), "range": clampf(far_range, 0, 200) / 2, "accuracy": clampf(100 - horizontal * 20, 0, 100), "control": clampf(100 - vertical * 15, 0, 100)}
	for key in values:
		stat_bars[key].value = values[key]

func _build_kit() -> void:
	var main := _hbox(page_host, 12)
	main.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var browser := _panel(main, "FIELD KIT  /  EQUIPMENT & SCORESTREAKS")
	browser.get_parent().size_flags_horizontal = Control.SIZE_EXPAND_FILL
	kit_tabs = HFlowContainer.new()
	kit_tabs.add_theme_constant_override("h_separation", 6)
	browser.add_child(kit_tabs)
	kit_slot_row = _hbox(browser, 6)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	browser.add_child(scroll)
	kit_grid = GridContainer.new()
	kit_grid.columns = 4
	kit_grid.add_theme_constant_override("h_separation", 10)
	kit_grid.add_theme_constant_override("v_separation", 10)
	kit_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(kit_grid)
	var right := _vbox(main, 12)
	right.custom_minimum_size.x = 285
	var details := _panel(right, "ITEM DETAILS")
	details.get_parent().custom_minimum_size.y = 235
	detail_title = _label(details, "", 20, UI.WHITE, 800)
	detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_description = _label(details, "", 13, UI.MUTED, 400)
	detail_description.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail_description.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_modifiers = _label(details, "", 11, UI.GREEN, 600)
	detail_modifiers.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var summary := _panel(right, "CURRENT LOADOUT")
	_label(summary, "PRIMARY", 9, UI.MUTED, 700)
	_label(summary, str(_weapon(loadout.primary.weaponId).get("name", "—")), 20, UI.WHITE, 800)
	_label(summary, "SECONDARY", 9, UI.MUTED, 700)
	_label(summary, str(_weapon(loadout.secondary.weaponId).get("name", "—")), 20, UI.WHITE, 800)
	_label(summary, "Changes save automatically to Class %d." % (current_slot + 1), 11, UI.GREEN, 600).autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_refresh_kit()

func _refresh_kit() -> void:
	if not is_instance_valid(kit_grid):
		return
	_clear(kit_tabs)
	for mode in ["tactical", "lethal", "fieldUpgrade", "streaks"]:
		var caption: String = "FIELD UPGRADE" if mode == "fieldUpgrade" else mode.to_upper()
		var button := _button(kit_tabs, caption, func():
			kit_mode = mode
			_refresh_kit(), kit_mode != mode)
		button.name = "KitMode_" + mode
		button.custom_minimum_size.y = 32
	_clear(kit_slot_row)
	kit_slot_row.visible = kit_mode == "streaks"
	if kit_mode == "streaks":
		_label(kit_slot_row, "SLOT", 10, UI.MUTED, 700)
		for index in range(3):
			_button(kit_slot_row, str(index + 1), func():
				streak_slot = index
				_refresh_kit(), streak_slot != index).custom_minimum_size = Vector2(38, 28)
	_clear(kit_grid)
	var choices: Array = []
	if kit_mode in ["tactical", "lethal"]:
		choices = tables.get("equipment", []).filter(func(item): return item.category == kit_mode)
	elif kit_mode == "fieldUpgrade":
		choices = tables.get("attachments", []).filter(func(item): return item.slot == "fieldUpgrade")
	else:
		choices = tables.get("streaks", []).duplicate(true)
		choices.push_front({"id": "", "cardId": "none", "name": "No Streak", "cost": 0})
	for definition in choices:
		var item: Dictionary = definition.duplicate(true)
		var group := "streak" if kit_mode == "streaks" else ("attachment" if kit_mode == "fieldUpgrade" else "equipment")
		item.description = _kit_description(kit_mode, definition)
		item.modifiersText = "%d streak score" % int(definition.cost) if kit_mode == "streaks" and int(definition.get("cost", 0)) > 0 else "Click to equip · saves automatically"
		var selected := false
		if kit_mode == "streaks":
			selected = streak_slot < loadout.streaks.size() and loadout.streaks[streak_slot] == definition.id
		else:
			selected = loadout.get(kit_mode, "") == definition.id
		_item_card(kit_grid, group, item, selected, func(): _select_kit(definition.id), Vector2(155, 120), UI.GREEN, "SLOT %d" % (streak_slot + 1) if kit_mode == "streaks" else kit_mode.to_upper())
	if not choices.is_empty():
		var first: Dictionary = choices[0]
		_show_detail(str(first.get("name", "Field Kit")), _kit_description(kit_mode, first), "Select a card to equip it.", UI.GREEN)

func _select_kit(id: String) -> void:
	if kit_mode == "streaks":
		while loadout.streaks.size() < 3:
			loadout.streaks.append("")
		loadout.streaks[streak_slot] = id
	else:
		loadout[kit_mode] = id
	changed.emit()
	_refresh_kit()

func _kit_description(mode: String, item: Dictionary) -> String:
	if mode == "streaks":
		if item.id.is_empty():
			return "Leave this scorestreak slot empty."
		return "%s is earned at %d streak score. Equip it in scorestreak slot %d." % [item.name, int(item.cost), streak_slot + 1]
	if mode == "fieldUpgrade":
		return str(item.get("description", "Activate this field upgrade during a match."))
	return str(EQUIPMENT_DESCRIPTIONS.get(item.id, "Equip this item in your %s slot." % mode))

func _weapon_description(weapon: Dictionary) -> String:
	if weapon.is_empty():
		return "Select a weapon from the gallery."
	return "%s %s. %s damage · %d-round magazine · %dm effective range." % [str(weapon.fireMode).capitalize(), str(CATEGORY_NAMES.get(weapon.category, "weapon")).to_lower(), str(weapon.damage), int(weapon.magazine), int(weapon.range.far)]

func _weapon_modifiers(weapon: Dictionary) -> String:
	if weapon.is_empty():
		return ""
	return "%d RPM   ·   %d mobility   ·   %.2fs reload   ·   %.2fs ADS" % [int(weapon.fireRate), int(weapon.mobility), float(weapon.reloadTime), float(weapon.adsTime)]

func _modifier_summary(modifiers: Dictionary) -> String:
	var lines: Array[String] = []
	for key in modifiers:
		var value := float(modifiers[key])
		match key:
			"adsMult": lines.append("ADS time %+d%%" % roundi((value - 1) * 100))
			"spreadMult": lines.append("Hipfire spread %+d%%" % roundi((value - 1) * 100))
			"rangeMult": lines.append("Range %+d%%" % roundi((value - 1) * 100))
			"mobilityAdd": lines.append("Mobility %+d" % roundi(value))
			"recoilMult": lines.append("Recoil %+d%%" % roundi((value - 1) * 100))
			"bulletVelocityMult": lines.append("Bullet velocity %+d%%" % roundi((value - 1) * 100))
			"magazineAdd": lines.append("Magazine %+d rounds" % roundi(value))
			"reloadMult": lines.append("Reload time %+d%%" % roundi((value - 1) * 100))
			"damageMult": lines.append("Damage %+d%%" % roundi((value - 1) * 100))
			"recoveryMult": lines.append("Recoil recovery %+d%%" % roundi((value - 1) * 100))
			"reserveAdd": lines.append("Reserve ammo %+d" % roundi(value))
	return "\n".join(lines) if not lines.is_empty() else "Standard handling · no stat penalties"

func _show_detail(title: String, description: String, modifiers: String = "", _accent: Color = UI.GREEN) -> void:
	if not is_instance_valid(detail_title):
		return
	detail_title.text = title.to_upper()
	detail_description.text = description
	detail_modifiers.text = modifiers

func _refresh_summary() -> void:
	if not is_instance_valid(summary_label) or loadout.is_empty():
		return
	summary_label.text = "%s  /  %s" % [str(_weapon(loadout.primary.weaponId).get("name", "—")).to_upper(), str(_weapon(loadout.secondary.weaponId).get("name", "—")).to_upper()]

func _camo_color() -> Color:
	if str(loadout.camo).begins_with("#"):
		return Color(loadout.camo)
	for camo in tables.get("camos", []):
		if camo.id == loadout.camo:
			return Color.hex(int(camo.color) * 256 + 255)
	return Color("2b2f36")

func _item_card(parent: Node, group: String, item: Dictionary, selected: bool, action: Callable, dimensions: Vector2, accent: Color = UI.GREEN, subtitle: String = "") -> Button:
	var button := Button.new()
	button.name = "%s_%s" % [group.capitalize(), str(item.get("cardId", item.get("id", "item")))]
	button.custom_minimum_size = dimensions
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_ALL
	button.set_meta("armory_id", item.get("id", ""))
	button.set_meta("armory_group", group)
	var description := str(item.get("description", ""))
	var modifiers := str(item.get("modifiersText", ""))
	button.tooltip_text = str(item.get("name", "Item")) + "\n" + description + ("\n" + modifiers if not modifiers.is_empty() else "")
	_card_styles(button, selected, accent)
	parent.add_child(button)
	button.pressed.connect(action)
	button.mouse_entered.connect(func(): _show_detail(str(item.get("name", "Item")), description, modifiers, accent))
	button.focus_entered.connect(func(): _show_detail(str(item.get("name", "Item")), description, modifiers, accent))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 5)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(margin)
	var column := _vbox(margin, 2)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.alignment = BoxContainer.ALIGNMENT_CENTER
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.custom_minimum_size.y = dimensions.y * 0.46
	icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if group == "weapon":
		icon.texture = _weapon_texture(str(item.get("category", "assault")))
	else:
		var icon_id := str(item.get("id", ""))
		if group == "attachment" and icon_id.is_empty():
			icon_id = "none"
		icon.texture = Icons.texture(group, icon_id, accent)
	column.add_child(icon)
	var title := _label(column, str(item.get("name", "ITEM")).to_upper(), 10 if dimensions.x < 100 else 11, UI.WHITE if not selected else accent, 700)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.max_lines_visible = 2
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not subtitle.is_empty():
		var caption := _label(column, "EQUIPPED" if selected else subtitle, 8, accent if selected else UI.MUTED, 600)
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return button

func _card_styles(button: Button, selected: bool, accent: Color) -> void:
	var background := Color("24301f") if selected else Color("141a21")
	button.add_theme_stylebox_override("normal", UI.box(background, accent if selected else Color("35414a"), 7, 2 if selected else 1, 4))
	button.add_theme_stylebox_override("hover", UI.box(Color("263324"), accent, 7, 2, 4))
	button.add_theme_stylebox_override("pressed", UI.box(Color("324228"), accent, 7, 2, 4))
	button.add_theme_stylebox_override("focus", UI.box(Color.TRANSPARENT, UI.WHITE, 7, 2, 4))

func _weapon_texture(category: String) -> Texture2D:
	var id := str(THUMBNAILS.get(category, "m4"))
	if not _textures.has(id):
		var path := "res://assets/armory/weapons/%s.png" % id
		_textures[id] = load(path) if ResourceLoader.exists(path) else null
	return _textures[id]

func _panel(parent: Node, title: String, width: float = 0) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = width
	panel.add_theme_stylebox_override("panel", UI.box(Color("0f151dde"), Color("2b353d"), 9, 1, 10))
	parent.add_child(panel)
	var column := _vbox(panel, 7)
	if not title.is_empty():
		_label(column, title, 10, UI.GREEN, 700)
	return column

func _label(parent: Node, text: String, font_size: int = 14, color: Color = UI.WHITE, weight: int = 600) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", UI.font(weight))
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, action: Callable, muted: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_ALL
	parent.add_child(button)
	button.pressed.connect(action)
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if muted:
		button.add_theme_stylebox_override("normal", UI.box(Color("1b242d"), Color("3c4a55"), 6, 1, 8))
		button.add_theme_stylebox_override("hover", UI.box(Color("293741"), UI.GREEN, 6, 1, 8))
		button.add_theme_color_override("font_color", UI.WHITE)
		button.add_theme_color_override("font_hover_color", UI.WHITE)
	return button

func _vbox(parent: Node, gap: int = 8) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	parent.add_child(box)
	return box

func _hbox(parent: Node, gap: int = 8) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", gap)
	parent.add_child(box)
	return box

func _clear(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()
