extends RefCounted
## Source-compatible JSON protocol. Hosts own bots; clients own their player.
const DEFAULT_SETTINGS := {"mapId": "desert_town", "mode": "tdm", "botCount": 4, "difficulty": "regular", "hardcore": false}

static func encode(message: Dictionary) -> String:
	return JSON.stringify(message)

static func decode(raw: String) -> Dictionary:
	var parser := JSON.new()
	if parser.parse(raw) != OK or not parser.data is Dictionary:
		return {}
	if not parser.data.get("t") is String:
		return {}
	return parser.data

static func sanitize_settings(settings: Dictionary) -> Dictionary:
	var mode: String = str(settings.get("mode", "tdm"))
	var difficulty: String = str(settings.get("difficulty", "regular"))
	var count: Variant = settings.get("botCount", 0)
	if not count is float and not count is int:
		count = 0
	return {"mapId": str(settings.get("mapId", DEFAULT_SETTINGS.mapId)), "mode": mode if mode in ["tdm", "ffa", "dom", "ctf", "gungame"] else "tdm", "botCount": clampi(floori(count), 0, 16), "difficulty": difficulty if difficulty in ["recruit", "regular", "veteran"] else "regular", "hardcore": bool(settings.get("hardcore", false))}
