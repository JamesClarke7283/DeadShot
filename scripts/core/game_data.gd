class_name GameData
extends RefCounted
## Declarative balance data exported verbatim from the original TypeScript game.
static var _tables: Dictionary = {}

static func table(id: String) -> Variant:
	if not _tables.has(id):
		var file = FileAccess.open("res://data/%s.json" % id, FileAccess.READ)
		if file == null:
			push_error("Missing DeadShot data table: " + id)
			return []
		_tables[id] = JSON.parse_string(file.get_as_text())
	return _tables[id]

static func entry(table_id: String, id: String) -> Dictionary:
	for item in table(table_id):
		if item.id == id:
			return item.duplicate(true)
	return {}

static func weapon(id: String) -> Dictionary:
	return entry("weapons", id)

static func color_from_hex(value: int) -> Color:
	return Color(float((value >> 16) & 255) / 255.0, float((value >> 8) & 255) / 255.0, float(value & 255) / 255.0)

static func camo(id: String) -> Color:
	if id.begins_with("#") and Color.html_is_valid(id):
		return Color.html(id)
	var data = entry("camos", id)
	return color_from_hex(int(data.get("color", 0x2b2f36)))

static func stats(definition: Dictionary, attachments: Array = []) -> Dictionary:
	var result = definition.duplicate(true)
	result.spreadMult = 1.0
	result.effects = []
	for ref in attachments:
		var attachment: Dictionary = entry("attachments", ref) if ref is String else ref
		var mods: Dictionary = attachment.get("modifiers", {})
		for pair in [["damageMult", "damage"], ["fireRateMult", "fireRate"], ["reloadMult", "reloadTime"], ["adsMult", "adsTime"], ["bulletVelocityMult", "bulletVelocity"], ["spreadMult", "spreadMult"]]:
			if mods.has(pair[0]):
				result[pair[1]] *= mods[pair[0]]
		for pair in [["magazineAdd", "magazine"], ["reserveAdd", "reserve"], ["mobilityAdd", "mobility"]]:
			if mods.has(pair[0]):
				result[pair[1]] += mods[pair[0]]
		if mods.has("recoilMult"):
			result.recoil.vertical *= mods.recoilMult
			result.recoil.horizontal *= mods.recoilMult
		if mods.has("recoveryMult"):
			result.recoil.recovery *= mods.recoveryMult
		if mods.has("rangeMult"):
			result.range.near *= mods.rangeMult
			result.range.far *= mods.rangeMult
		if attachment.has("effect"):
			result.effects.append(attachment.effect)
	result.magazine = maxi(1, roundi(result.magazine))
	result.mobility = clampf(result.mobility, 1.0, 100.0)
	return result

static func damage_at_range(stats_value: Dictionary, distance: float) -> float:
	var falloff: Dictionary = stats_value.range
	if distance <= falloff.near:
		return stats_value.damage
	if distance >= falloff.far:
		return falloff.minDamage
	return lerpf(stats_value.damage, falloff.minDamage, (distance - falloff.near) / (falloff.far - falloff.near))
