extends RefCounted
## Native persistence for the same versioned DeadShot save schema used by the browser.
## JSON may be imported directly from localStorage["deadshot.save"].

const SAVE_PATH := "user://deadshot.save.json"
const CLASS_SLOTS := 10
var data: Dictionary
var _save_path: String

func _init(path: String = SAVE_PATH) -> void:
	_save_path = path
	data = default_save()
	if FileAccess.file_exists(_save_path):
		var parser := JSON.new()
		if parser.parse(FileAccess.get_file_as_string(_save_path)) == OK and parser.data is Dictionary:
			data = migrate(parser.data)

static func default_class(index: int) -> Dictionary:
	return {"name": "Custom %d" % (index + 1), "primary": {"weaponId": "m4", "attachments": ["reddot", "compensator"]}, "secondary": {"weaponId": "m9", "attachments": []}, "tactical": "flashbang", "lethal": "frag", "fieldUpgrade": "deadsilence", "perks": ["double_time", "ghost", "amped"], "streaks": ["uav", "care_package", "attack_heli"], "camo": "gunmetal"}

static func default_settings() -> Dictionary:
	return {"sensitivity": 1.0, "fov": 75, "masterVolume": 0.8, "sfxVolume": 0.9, "musicVolume": 0.5, "invertY": false, "killcam": true, "graphics": "high"}

static func default_match_config() -> Dictionary:
	return {"mapId": "desert_town", "mode": "tdm", "botCount": 8, "difficulty": "regular", "hardcore": false}

static func default_save() -> Dictionary:
	var classes: Array = []
	for i in CLASS_SLOTS:
		classes.append(default_class(i))
	return {"version": 1, "classes": classes, "settings": default_settings(), "lastMatch": default_match_config()}

static func migrate(input: Dictionary) -> Dictionary:
	var base := default_save()
	var classes: Variant = input.get("classes", [])
	if classes is Array:
		for i in mini(CLASS_SLOTS, classes.size()):
			if not classes[i] is Dictionary:
				continue
			for key in base.classes[i]:
				if not classes[i].has(key):
					continue
				if typeof(classes[i][key]) == typeof(base.classes[i][key]):
					if classes[i][key] is Dictionary:
						base.classes[i][key].merge(classes[i][key], true)
					else:
						base.classes[i][key] = classes[i][key]
	for section in ["settings", "lastMatch"]:
		if input.get(section) is Dictionary:
			for key in base[section]:
				var value: Variant = input[section].get(key)
				if typeof(value) == typeof(base[section][key]) or (value is float and base[section][key] is int):
					base[section][key] = value
	for i in CLASS_SLOTS:
		var item: Dictionary = base.classes[i]
		var defaults := default_class(i)
		for slot in ["primary", "secondary"]:
			if not item[slot].get("weaponId") is String:
				item[slot].weaponId = defaults[slot].weaponId
			if not item[slot].get("attachments") is Array:
				item[slot].attachments = defaults[slot].attachments.duplicate()
			item[slot].attachments = item[slot].attachments.filter(func(id): return id is String)
		var perks: Array = []
		for tier in 3:
			perks.append(item.perks[tier] if tier < item.perks.size() and item.perks[tier] is String else defaults.perks[tier])
		item.perks = perks
		item.streaks = item.streaks.filter(func(id): return id is String).slice(0, 3)
	base.lastMatch.botCount = clampi(int(base.lastMatch.botCount), 0, 16)
	return base

func save() -> void:
	# Atomic replace keeps an interrupted write from corrupting all ten classes.
	var temp := _save_path + ".tmp"
	var file := FileAccess.open(temp, FileAccess.WRITE)
	if file == null:
		push_error("Could not write DeadShot save: %s" % error_string(FileAccess.get_open_error()))
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	var error := DirAccess.rename_absolute(temp, _save_path)
	if error != OK:
		push_error("Could not replace DeadShot save: %s" % error_string(error))

func get_classes() -> Array:
	return data.classes.duplicate(true)

func get_loadout(index: int) -> Dictionary:
	return data.classes[clampi(index, 0, CLASS_SLOTS - 1)].duplicate(true)

func set_class(index: int, loadout: Dictionary) -> void:
	data.classes[clampi(index, 0, CLASS_SLOTS - 1)] = loadout.duplicate(true)
	save()

func get_settings() -> Dictionary:
	return data.settings.duplicate(true)

func update_settings(patch: Dictionary) -> void:
	data.settings.merge(patch, true)
	save()

func get_match_config() -> Dictionary:
	return data.lastMatch.duplicate(true)

func set_match_config(config: Dictionary) -> void:
	data.lastMatch = config.duplicate(true)
	save()

func reset() -> void:
	data = default_save()
	save()

func import_browser_save(json: String) -> bool:
	var parser := JSON.new()
	if parser.parse(json) != OK or not parser.data is Dictionary:
		return false
	data = migrate(parser.data)
	save()
	return true
