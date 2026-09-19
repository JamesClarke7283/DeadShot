extends Control
## Pixel-positioned HUD matching the browser canvas overlay.
const UI := preload("res://scripts/ui/ui_theme.gd")
var state: Dictionary = {"health": 100, "maxHealth": 100, "mag": 30, "reserve": 90, "weaponName": "M4A1", "blue": 0, "red": 0, "mode": "tdm", "timeLeft": 600, "spread": 4, "alive": true}
var hardcore := false
var kills: Array = []
var hit_time := 0.0
var hit_headshot := false
var damage_time := 0.0
var damage_angle := 0.0
var damage_arcs: Array = []
var regular := UI.font(600)
var heavy := UI.font(800)
var streak_gradient := GradientTexture2D.new()
var ready_gradient := GradientTexture2D.new()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for texture in [streak_gradient, ready_gradient]:
		texture.width = 160
		texture.height = 6
		texture.gradient = Gradient.new()
		texture.gradient.colors = PackedColorArray([Color("ffe27a") if texture == ready_gradient else Color("9fd13e"), UI.GREEN])

func _process(delta: float) -> void:
	hit_time = maxf(0, hit_time - delta)
	damage_time = maxf(0, damage_time - delta)
	for arc in damage_arcs:
		arc.life -= delta
	damage_arcs = damage_arcs.filter(func(arc): return arc.life > 0)
	for entry in kills:
		entry.life -= delta
	kills = kills.filter(func(e): return e.life > 0)
	if visible:
		queue_redraw()

func update_state(values: Dictionary) -> void:
	state.merge(values, true)
	queue_redraw()

func hit_marker(headshot: bool) -> void:
	hit_headshot = headshot
	hit_time = 0.15

func damage_from(angle: float) -> void:
	damage_angle = angle
	damage_time = 0.7
	damage_arcs.append({"angle": angle, "life": 1.2})

func add_kill(event: Dictionary) -> void:
	var entry := event.duplicate(true)
	entry.life = 6.4
	kills.push_front(entry)
	if kills.size() > 5:
		kills.pop_back()

func label_at(text: String, position: Vector2, font_size: int = 14, color: Color = UI.WHITE, centered: bool = false, bold: bool = true) -> void:
	var face: Font = heavy if bold else regular
	if centered:
		position.x -= face.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x * 0.5
	draw_string(face, position, text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)

func panel(rect: Rect2, fill: Color = Color("0a0c10b3"), edge: Color = UI.INK, radius: int = 8) -> void:
	UI.box(fill, edge, radius, 2, 0).draw(get_canvas_item(), rect)

func bar(rect: Rect2, fraction: float, color: Color = Color("9fd13e")) -> void:
	panel(rect)
	var inset := rect.grow(-2)
	inset.size.x *= clampf(fraction, 0, 1)
	if inset.size.x > 0:
		UI.box(color, Color.TRANSPARENT, 3, 0, 0).draw(get_canvas_item(), inset)

func _draw() -> void:
	var center := size * 0.5
	var alive: bool = state.get("alive", true)
	if not hardcore:
		_draw_score()
		_draw_health_ammo()
		_draw_radar()
		_draw_streaks()
		_draw_kills()
		if alive:
			var spread: float = maxf(0, state.get("spread", 4))
			for dir in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
				draw_line(center + dir * spread, center + dir * (spread + 7), UI.INK, 4)
				draw_line(center + dir * spread, center + dir * (spread + 7), UI.WHITE, 2)
			draw_rect(Rect2(center - Vector2.ONE, Vector2(2, 2)), UI.WHITE)
	if hit_time > 0:
		var color := Color("ff4d4d") if hit_headshot else Color.WHITE
		color.a = hit_time / 0.15
		var scale_factor := 1.5 if hit_headshot else 1.1
		for dir in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
			draw_line(center + dir * 4 * scale_factor, center + dir * 10 * scale_factor, color, 2)
	for arc in damage_arcs:
		for radius in range(85, 151, 6):
			var radial_alpha: float = maxf(0, 1 - absf(radius - 112) / 36.0)
			for segment in 14:
				var angle_start: float = arc.angle - PI * 0.5 + deg_to_rad(-35 + segment * 5)
				var angular_alpha := sin(float(segment + 0.5) / 14 * PI)
				var alpha: float = radial_alpha * angular_alpha * 0.85 * arc.life / 1.2
				draw_arc(center, radius, angle_start, angle_start + deg_to_rad(5), 2, Color(1, 0.157, 0.157, alpha), 7, true)
	var prompt: String = state.get("prompt", "")
	if not prompt.is_empty():
		var width := heavy.get_string_size(prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 15).x + 32
		panel(Rect2(Vector2(center.x - width / 2, size.y * 0.58), Vector2(width, 36)), Color("0a0c10c7"), UI.GREEN, 10)
		label_at(prompt, Vector2(center.x, size.y * 0.58 + 24), 15, UI.WHITE, true)
	if not alive:
		label_at(state.get("deathText", "YOU WERE ELIMINATED"), center + Vector2(0, 76), 28, Color("ff7a7a"), true)
	if state.get("killcam", false):
		panel(Rect2(Vector2(center.x - 150, 100), Vector2(300, 58)))
		label_at("KILLCAM", Vector2(center.x, 126), 22, Color("ff7a7a"), true)
		label_at(state.get("killcamText", "Press SPACE to skip"), Vector2(center.x, 148), 12, UI.MUTED, true)
	if state.get("reloading", false):
		label_at("RELOADING", center + Vector2(0, 48), 15, UI.GREEN, true)
	if state.get("fps", 0) > 0:
		label_at("%d FPS" % state.fps, Vector2(8, 18), 12, Color("b6ff5e"))

func _draw_score() -> void:
	var mode: String = state.get("mode", "tdm")
	var text := "BLUE  %d  —  %d  RED" % [state.get("blue", 0), state.get("red", 0)]
	if mode == "ffa":
		text = "FFA   LEADER: %d" % state.get("blue", 0)
	var width := heavy.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 20).x + 36
	var objective: Dictionary = state.get("objective", {}) if state.get("objective") is Dictionary else {}
	panel(Rect2(Vector2((size.x - width) / 2, 14), Vector2(width, 103 if not objective.is_empty() else 56)))
	label_at(text, Vector2(size.x / 2, 40), 20, UI.WHITE, true)
	var time := maxi(0, int(state.get("timeLeft", 0)))
	label_at("%d:%02d" % [time / 60, time % 60], Vector2(size.x / 2, 59), 14, UI.GREEN, true)
	if objective.is_empty():
		return
	var points: Array = objective.get("points", objective.get("flags", []))
	var x := size.x / 2 - points.size() * 38
	for item in points:
		var text_value: String = item.get("label", str(item.get("team", "")).to_upper() + " " + str(item.get("status", "")))
		var color := team_color(item.get("owner", item.get("team", "neutral")))
		panel(Rect2(Vector2(x, 72), Vector2(70, 22)), color)
		label_at(text_value, Vector2(x + 35, 87), 11, UI.INK, true)
		x += 76
	label_at("%d — %d  ·  first to %d" % [objective.get("blue", 0), objective.get("red", 0), objective.get("cap", 200)], Vector2(size.x / 2, 111), 12, UI.MUTED, true)

func _draw_health_ammo() -> void:
	var hp: float = state.get("health", 100)
	var maximum: float = maxf(1, state.get("maxHealth", 100))
	var fraction := hp / maximum
	label_at("HEALTH", Vector2(20, size.y - 48), 11, UI.MUTED)
	# Source hsl(round(120*ratio),75%,52%) converted exactly to HSV.
	var hp_color := Color.from_hsv(roundf(120 * clampf(fraction, 0, 1)) / 360.0, 0.8181818, 0.88)
	bar(Rect2(Vector2(20, size.y - 42), Vector2(240, 20)), fraction, hp_color)
	label_at(str(maxi(0, roundi(hp))), Vector2(140, size.y - 27), 13, UI.INK, true)
	var weapon: String = str(state.get("weaponName", "")).to_upper()
	var weapon_width := heavy.get_string_size(weapon, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
	label_at(weapon, Vector2(size.x - 24 - weapon_width, size.y - 69), 13, UI.MUTED)
	var reserve := "/ %d" % state.get("reserve", 90)
	var reserve_width := heavy.get_string_size(reserve, HORIZONTAL_ALIGNMENT_LEFT, -1, 18).x
	label_at(reserve, Vector2(size.x - 24 - reserve_width, size.y - 24), 18, UI.MUTED)
	var mag := str(state.get("mag", 30))
	var mag_width := heavy.get_string_size(mag, HORIZONTAL_ALIGNMENT_LEFT, -1, 40).x
	label_at(mag, Vector2(size.x - 30 - reserve_width - mag_width, size.y - 22), 40, UI.INK)
	label_at(mag, Vector2(size.x - 32 - reserve_width - mag_width, size.y - 24), 40, Color("ff4d4d") if mag == "0" else UI.WHITE)
	var score: float = state.get("streakScore", 0)
	var cost: float = maxf(1, float(state.get("nextStreakCost", 500))) if state.get("nextStreakCost", 500) != null else 1.0
	var next_name: String = str(state.get("nextStreakName", "UAV")) if state.get("nextStreakName", "UAV") != null else ""
	label_at("NEXT: %s (%d/%d)" % [next_name.to_upper(), score, cost] if not next_name.is_empty() else "MAX STREAK READY", Vector2(20, size.y - 84), 11, UI.GREEN)
	bar(Rect2(Vector2(20, size.y - 78), Vector2(240, 8)), score / cost if not next_name.is_empty() else 1.0)
	if state.get("gunGameTier", 0) > 0:
		var tier: int = state.gunGameTier
		var max_tier: int = maxi(1, state.get("gunGameMaxTier", 19))
		label_at("GUN GAME  TIER %d/%d  —  %s" % [tier, max_tier, str(state.get("gunGameWeapon", weapon)).to_upper()], Vector2(20, size.y - 112), 12, Color("ff9d3a"))
		bar(Rect2(Vector2(20, size.y - 106), Vector2(240, 10)), float(tier) / max_tier, Color("ff9d3a"))

func _draw_radar() -> void:
	var center := Vector2(size.x - 96, 94)
	# CSS box shadows sit outside the translucent disc rather than making its
	# background opaque. Draw only the exposed lower-right shadow edge.
	draw_arc(center + Vector2(1.5, 1.5), 80.5, -PI / 4, PI * 0.75, 64, UI.INK, 3, true)
	draw_circle(center, 80, Color("0a1210b3"))
	draw_circle(center, 78, Color(10.0 / 255, 22.0 / 255, 18.0 / 255, 0.8))
	draw_arc(center, 79, 0, TAU, 64, UI.INK, 2, true)
	for radius in [24.42, 48.84, 74.0]:
		draw_arc(center, radius, 0, TAU, 64, Color(120.0 / 255, 200.0 / 255, 140.0 / 255, 0.25), 1, true)
	draw_line(center + Vector2(-74, 0), center + Vector2(74, 0), Color("78c88c40"))
	draw_line(center + Vector2(0, -74), center + Vector2(0, 74), Color("78c88c40"))
	var radar: Dictionary = state.get("minimap", {})
	if radar.get("jammed", false):
		draw_circle(center, 78, Color("1e0c0cd9"))
		for i in 240:
			var point := Vector2(randf_range(-76, 76), randf_range(-76, 76))
			if point.length() < 76:
				draw_rect(Rect2(center + point, Vector2(2, 2)), Color(1, 1, 1, randf() * 0.25))
		label_at("NO SIGNAL", center + Vector2(0, 4), 14, Color("ff4d4d"), true)
		return
	var player: Dictionary = radar.get("player", {"x": 0, "z": 0, "yaw": 0})
	var yaw: float = player.get("yaw", 0)
	var bounds: Dictionary = radar.get("bounds", {})
	if not bounds.is_empty():
		var corners := PackedVector2Array()
		for point in [Vector2(bounds.minX, bounds.minZ), Vector2(bounds.maxX, bounds.minZ), Vector2(bounds.maxX, bounds.maxZ), Vector2(bounds.minX, bounds.maxZ), Vector2(bounds.minX, bounds.minZ)]:
			var offset: Vector2 = (point - Vector2(player.get("x", 0), player.get("z", 0))).rotated(-yaw) * 1.2
			offset.y = -offset.y
			corners.append(offset)
		for index in 4:
			_radar_line(center, corners[index], corners[index + 1])
	for blip in radar.get("blips", []):
		if not blip.get("enemy", true):
			continue
		var offset := (Vector2(blip.get("x", 0), blip.get("z", 0)) - Vector2(player.get("x", 0), player.get("z", 0))).rotated(-yaw) * 1.2
		offset.y = -offset.y
		if offset.length() < 74:
			draw_circle(center + offset, 3.5, Color("ff4d4d"))
	var arrow := PackedVector2Array([center + Vector2(0, -7), center + Vector2(5, 6), center + Vector2(0, 3), center + Vector2(-5, 6), center + Vector2(0, -7)])
	draw_colored_polygon(arrow, UI.GREEN)
	draw_polyline(arrow, UI.INK, 1.5, true)

func _radar_line(center: Vector2, start: Vector2, end: Vector2) -> void:
	# Clip each edge against the radar circle, like the source canvas clip path.
	# Clamping corners would turn distant rectangular boundaries into trapezoids.
	var direction := end - start
	var quadratic_a := direction.length_squared()
	if quadratic_a < 0.001:
		return
	var quadratic_b := 2 * start.dot(direction)
	var quadratic_c := start.length_squared() - 76 * 76
	var discriminant := quadratic_b * quadratic_b - 4 * quadratic_a * quadratic_c
	if discriminant < 0:
		return
	var lower := maxf(0, (-quadratic_b - sqrt(discriminant)) / (2 * quadratic_a))
	var upper := minf(1, (-quadratic_b + sqrt(discriminant)) / (2 * quadratic_a))
	if upper >= lower:
		draw_line(center + start + direction * lower, center + start + direction * upper, Color("78c88c66"), 1.5, true)

func _draw_streaks() -> void:
	var y := 188.0
	for entry in state.get("streaks", []):
		var available: bool = entry.get("available", false)
		var style := UI.box(Color("0a0c1099"), UI.GREEN if available else UI.INK, 7, 2, 0)
		if available:
			var pulse := (1 - cos(float(Time.get_ticks_msec()) / 1000.0 * TAU / 1.2)) * 0.5
			style.shadow_color = Color(UI.GREEN, lerpf(0.5, 0.95, pulse))
			style.shadow_size = roundi(lerpf(4, 14, pulse))
		style.draw(get_canvas_item(), Rect2(Vector2(size.x - 192, y), Vector2(176, 35)))
		var text: String = str(entry.get("name", "")).to_upper()
		var score: float = entry.get("score", 0)
		var cost: float = maxf(1, entry.get("cost", 1))
		text += " ✓" if available else "  %d/%d" % [mini(score, cost), cost]
		label_at(text, Vector2(size.x - 183, y + 16), 10)
		var track := Rect2(Vector2(size.x - 183, y + 22), Vector2(158, 6))
		UI.box(Color("0a0c10cc"), Color.TRANSPARENT, 4, 0, 0).draw(get_canvas_item(), track)
		track.size.x *= clampf(score / cost, 0, 1)
		if track.size.x > 0:
			draw_texture_rect(ready_gradient if available else streak_gradient, track, false)
		y += 41

func _draw_kills() -> void:
	var y := 126.0
	for entry in kills:
		var killer: String = entry.get("killer", "☠")
		var victim: String = entry.get("victim", "")
		var weapon := " ▸ %s%s ▸ " % [str(entry.get("weaponId", "—")).to_upper(), " ☠" if entry.get("headshot", false) else ""]
		var widths := [heavy.get_string_size(killer, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, heavy.get_string_size(weapon, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x, heavy.get_string_size(victim, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x]
		var x: float = size.x - 16 - widths[0] - widths[1] - widths[2] - 16
		panel(Rect2(Vector2(x, y), Vector2(widths[0] + widths[1] + widths[2] + 16, 26)), Color("0a0c10b3"), Color("ffffff1f"), 5)
		label_at(killer, Vector2(x + 8, y + 18), 13, team_color(entry.get("killerTeam", "ffa")))
		label_at(weapon, Vector2(x + 8 + widths[0], y + 18), 13, Color("ff4d4d") if entry.get("headshot", false) else UI.MUTED)
		label_at(victim, Vector2(x + 8 + widths[0] + widths[1], y + 18), 13, team_color(entry.get("victimTeam", "ffa")))
		y += 31

static func team_color(team: String) -> Color:
	return Color("3a86ff") if team == "blue" else Color("ff4d4d") if team == "red" else Color("ffcc33") if team == "ffa" else UI.MUTED
