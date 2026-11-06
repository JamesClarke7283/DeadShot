extends RefCounted
## Lightweight, cached vector pictograms for Armory item cards.
static var _cache: Dictionary = {}

static func texture(group: String, id: String, color: Color = Color("cdeb6e")) -> Texture2D:
	var key := "%s/%s/%s" % [group, id, color.to_html()]
	if _cache.has(key):
		return _cache[key]
	var drawing := ""
	match group:
		"perk":
			drawing = _perk(id)
		"equipment":
			drawing = _equipment(id)
		"streak":
			drawing = _streak(id)
		_:
			drawing = _attachment(id if not id.is_empty() else group)
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="96" height="96" viewBox="0 0 96 96"><circle cx="48" cy="48" r="43" fill="#10161c" stroke="#304038" stroke-width="2"/><g fill="none" stroke="#%s" stroke-width="4.5" stroke-linecap="round" stroke-linejoin="round">%s</g></svg>' % [color.to_html(false), drawing]
	var image := Image.new()
	if image.load_svg_from_string(svg) != OK:
		return null
	var result := ImageTexture.create_from_image(image)
	_cache[key] = result
	return result

static func _attachment(id: String) -> String:
	match id:
		"optic", "iron", "reddot", "holo", "acog":
			if id == "acog":
				return '<path d="M19 39h58v18H19zM31 33h34l7 6H24zM38 57v10h20V57"/><circle cx="48" cy="48" r="8"/><path d="M48 43v10M43 48h10"/>'
			if id == "holo":
				return '<path d="M25 25h46v46H25zM18 42h7M71 42h7M33 71v8h30v-8"/><circle cx="48" cy="48" r="11"/><path d="M48 38v20M38 48h20"/>'
			if id == "iron":
				return '<path d="M18 66h60M27 66V37l10-10v39M59 66V28h10v38"/><circle cx="48" cy="55" r="5"/>'
			return '<circle cx="48" cy="45" r="24"/><circle cx="48" cy="45" r="6"/><path d="M48 13v14M48 63v14M16 45h14M66 45h14M36 77h24"/>'
		"barrel", "compensator", "suppressor", "longbarrel", "muzzlebrake":
			var length := 68 if id == "longbarrel" else 56
			return '<path d="M14 40h%dv16H14zM22 36v24M34 36v24M70 34v28M78 43h6v10h-6"/><path d="M20 48h48"/>' % length
		"magazine", "extmag", "fastmag", "fmj", "drum":
			if id == "drum":
				return '<circle cx="48" cy="51" r="26"/><circle cx="48" cy="51" r="15"/><path d="M36 16h24v12H36zM48 36v30M33 51h30"/>'
			return '<path d="M34 15h29l-5 53-18 13-13-9 12-50zM36 29l22 1M32 47l23 2M29 63l23 3"/><path d="M39 22l15 1"/>'
		"stock", "stock_std", "nostock", "heavystock":
			return '<path d="M13 33h29l17-13h24v20H62L44 54H28v25H13zM28 40h25M20 62h8"/>'
		"grip", "grip_none", "foregrip", "angledgrip", "laser":
			if id == "laser":
				return '<path d="M19 30h42v25H19zM61 37h11v11H61zM29 55v14h22V55M72 42l12-8M72 42l12 8"/>'
			return '<path d="M29 14h38v17H54L46 80H25l13-49H29zM40 38h13M36 52h13"/>'
		"fieldUpgrade", "deadsilence", "trophy", "munitions", "stoppingpower":
			return '<path d="M48 12l28 11v22c0 18-12 29-28 38-16-9-28-20-28-38V23z"/><path d="M51 24L34 51h14l-3 22 18-29H49z"/>'
		"none", "grip_none", "perk_none", "fu_none":
			return '<circle cx="48" cy="48" r="27"/><path d="M29 29l38 38"/>'
		_:
			return '<path d="M48 11l10 24 26 3-20 17 6 26-22-14-22 14 6-26-20-17 26-3z"/>'
	return ""

static func _perk(id: String) -> String:
	match id:
		"double_time":
			return '<path d="M20 27l18 21-18 21M43 27l18 21-18 21M67 20v17M61 29h12"/>'
		"scavenger":
			return '<path d="M28 15h13v43H28zM45 28h13v30H45zM28 15l6-7 7 7M45 28l6-7 7 7M20 69h47M61 60v18M52 69h18"/>'
		"coldblooded":
			return '<path d="M48 14v68M19 31l58 34M19 65l58-34M40 21l8 9 8-9M40 75l8-9 8 9M21 42l12-3-3-12M75 54l-12 3 3 12M30 70l3-12-12-3M66 26l-3 12 12 3"/>'
		"ghost":
			return '<path d="M25 76V43c0-18 9-29 23-29s23 11 23 29v33l-8-7-8 7-7-7-8 7-8-7z"/><circle cx="39" cy="42" r="3"/><circle cx="58" cy="42" r="3"/><path d="M41 56h14"/>'
		"hardline":
			return '<path d="M22 23h52M22 39h40M22 55h28M22 71h16M66 52v22M57 65l9 9 9-9"/>'
		"overkill":
			return '<path d="M18 23l51 51M25 16l52 52M15 35l13-13 12 4 27 27-8 8-27-27zM81 35L68 22l-12 4-8 8 8 8 8-8zM28 62l-9 15M65 62l9 15"/>'
		"amped":
			return '<path d="M53 10L25 51h21l-5 35 30-45H50zM19 22h12M15 32h10M67 70h14M71 60h10"/>'
		"high_alert":
			return '<path d="M10 48s14-23 38-23 38 23 38 23-14 23-38 23S10 48 10 48z"/><circle cx="48" cy="48" r="13"/><circle cx="48" cy="48" r="4"/><path d="M48 11v7M18 18l6 6M78 18l-6 6"/>'
		"tracker":
			return '<path d="M31 16c-9 2-14 14-11 25 3 12 12 17 20 12 8-5 8-16 3-25-4-8-7-13-12-12zM63 43c-9 1-15 12-13 23 2 12 11 18 19 14 9-4 10-15 6-25-3-8-7-13-12-12zM24 58l-5 9M35 61l-2 10M55 84l-3 7M67 85l2 6"/>'
	return '<circle cx="48" cy="48" r="25"/><path d="M48 30v36M30 48h36"/>'

static func _equipment(id: String) -> String:
	match id:
		"knife", "throwing_knife":
			return '<path d="M19 77L62 20l15-7-5 16-43 53zM52 40l12 12M25 59l14 14M16 73l9 9"/>'
		"smoke":
			return '<path d="M29 37h38v29H29zM36 30h24v7H36zM41 22h14v8H41zM26 67c-8 2-9 11-2 14 4 3 9 0 10-4M46 70c-6 5-3 13 4 13 6 0 9-6 5-11M65 66c7 3 8 11 2 14"/>'
		"snapshot":
			return '<circle cx="48" cy="48" r="28"/><circle cx="48" cy="48" r="15"/><path d="M48 48l18-18M48 12v8M48 76v8M12 48h8M76 48h8"/><circle cx="48" cy="48" r="3"/>'
		"c4":
			return '<rect x="19" y="26" width="58" height="45" rx="4"/><path d="M29 26v-8h38v8M31 38h12v10H31zM53 38h12v10H53zM31 55h12v8H31zM53 55h12v8H53z"/>'
		"claymore":
			return '<path d="M22 31h52v31H22zM30 62l-9 17M65 62l9 17M31 23h34M38 18h20"/><circle cx="37" cy="46" r="4"/><circle cx="59" cy="46" r="4"/>'
		"molotov":
			return '<path d="M40 29h18l7 44c1 8-32 8-31 0zM42 17h14v12H42zM49 17V8M50 8l12 5-5 10M40 54h20"/>'
		"semtex", "c4":
			return '<rect x="22" y="24" width="52" height="50" rx="5"/><path d="M30 34h36M30 46h36M30 58h36M38 24V15h20v9"/>'
		"flashbang", "stun":
			return '<path d="M32 32h32v43H32zM38 23h20v9H38zM43 15h10v8H43zM48 39l5 10 11 1-8 7 3 11-11-6-10 6 3-11-8-7 11-1z"/>'
		_:
			return '<path d="M32 31h32v45H32zM38 22h20v9H38zM43 14h10v8H43zM55 14l13 7-6 9M39 45h18M39 55h18M39 65h12"/>'

static func _streak(id: String) -> String:
	match id:
		"care_package":
			return '<path d="M18 35h60v43H18zM18 35l12-17h36l12 17M48 18v60M29 52h38"/>'
		"attack_heli", "chopper_gunner", "gunship", "strafe_run":
			return '<path d="M19 51h50l13-12v25H55L42 77H27l8-13H19zM38 50l8-19h12l5 19M15 25h66M48 18v14M9 58h10"/>'
		"nuke":
			return '<circle cx="48" cy="48" r="34"/><circle cx="48" cy="48" r="7"/><path d="M48 41L35 18c9-5 17-5 26 0zM54 52l26 6c-3 12-9 18-19 22zM41 52l-26 6c3 12 9 18 19 22z"/>'
		_:
			return '<circle cx="48" cy="48" r="30"/><circle cx="48" cy="48" r="17"/><path d="M48 48l20-20M48 11v8M48 77v8M11 48h8M77 48h8"/><circle cx="48" cy="48" r="3"/>'
