extends Control
## The view through the aimed sight. A magnified scope fills the screen with its
## eyepiece picture (`scope_lens.gdshader`) and a reticle for that optic; a
## reflex sight keeps the weapon in view and projects its red dot or holographic
## ring at the point of aim, but only where the see-through window cut in the
## sight's housing (`Combatant._update_sight_window`) actually covers it, as a
## real projected reticle is only visible through the glass.
##
## The overlay is a child of the HUD drawn behind it (`show_behind_parent`), so
## it hides with the HUD and the radar, ammo and markers stay readable over a
## scope. Reticles are vector lines rather than textures, so they stay sharp at
## any resolution.
const LENS_SHADER := preload("res://scripts/ui/scope_lens.gdshader")
const RED := Color(1.0, 0.16, 0.1)
const INK := Color(0.015, 0.015, 0.018)
var sight: Dictionary = {}
var lens: ColorRect
var lens_material := ShaderMaterial.new()

func _ready() -> void:
	name = "SightOverlay"
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	show_behind_parent = true
	lens = ColorRect.new()
	lens.name = "ScopeLens"
	lens.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lens.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	lens.show_behind_parent = true
	lens_material.shader = LENS_SHADER
	lens.material = lens_material
	lens.visible = false
	add_child(lens)

func update_sight(value: Dictionary) -> void:
	if value == sight:
		return
	sight = value.duplicate()
	_apply_lens()
	queue_redraw()

func _notification(what: int) -> void:
	# The lens is laid out in screen proportions; a resize while holding a still
	# scope sends no new sight state, so re-lay it out here.
	if what == NOTIFICATION_RESIZED and lens:
		_apply_lens()
		queue_redraw()

func _apply_lens() -> void:
	var amount := scope_amount()
	lens.visible = amount > 0.0
	if lens.visible:
		lens_material.set_shader_parameter("amount", amount)
		lens_material.set_shader_parameter("center", scope_center() / size.max(Vector2.ONE))
		lens_material.set_shader_parameter("radius", scope_radius() / maxf(size.y, 1.0))
		lens_material.set_shader_parameter("aspect", size.x / maxf(size.y, 1.0))

func scope_amount() -> float:
	return float(sight.get("scope", 0.0)) if str(sight.get("kind", "")) == "scope" else 0.0

## The eyepiece picture grows as the eye closes on it, and dips with each shot's
## kick, the scope shadow of a rifle moving against the eye. The reticle stays
## on the point of aim, where the shot goes.
func scope_center() -> Vector2:
	return size * 0.5 + Vector2(0.0, float(sight.get("kick", 0.0)) * size.y * 0.012)

func scope_radius() -> float:
	var amount := scope_amount()
	return size.y * lerpf(0.3, 0.47, 1.0 - pow(1.0 - amount, 3.0))

func _draw() -> void:
	var kind := str(sight.get("kind", ""))
	var aim := size * 0.5
	if kind == "scope":
		var amount := scope_amount()
		if amount > 0.0:
			_draw_scope(str(sight.get("reticle", "")), aim, scope_radius(), amount)
	elif kind == "reflex" and sight.has("window"):
		var window: Vector3 = sight.window
		_draw_reflex(str(sight.get("reticle", "")), aim, Vector2(window.x, window.y) * size, window.z * size.y)

## The window's rim gets a soft dark edge, which also hides the stair-stepping of
## the cut through the housing, and the glass a faint coating tint. The reticle
## fades in only once the whole of it lies inside the window.
func _draw_reflex(style: String, aim: Vector2, center: Vector2, radius: float) -> void:
	if radius < 2.0:
		return
	var open := clampf((radius - 2.0) / 10.0, 0.0, 1.0)
	draw_circle(center, radius, Color(0.55, 0.78, 0.86, 0.045 * open))
	draw_arc(center, radius - 1.0, 0.0, TAU, 96, Color(0.0, 0.0, 0.0, 0.5 * open), 3.0, true)
	draw_arc(center, radius - 3.5, 0.0, TAU, 96, Color(0.55, 0.85, 0.75, 0.10 * open), 1.0, true)
	var reach := size.y * (0.034 if style == "holo" else 0.006)
	var inside := clampf((radius - aim.distance_to(center) - reach) / maxf(radius * 0.15, 1.0), 0.0, 1.0)
	if inside <= 0.0:
		return
	var glow := Color(RED, 0.22 * inside)
	var core := Color(RED, inside)
	var dot := maxf(1.6, size.y * 0.0032)
	if style == "holo":
		var ring := size.y * 0.03
		var width := maxf(1.4, size.y * 0.0022)
		draw_arc(aim, ring, 0.0, TAU, 72, glow, width * 3.0, true)
		draw_arc(aim, ring, 0.0, TAU, 72, core, width, true)
		for direction: Vector2 in [Vector2.UP, Vector2.DOWN, Vector2.LEFT, Vector2.RIGHT]:
			draw_line(aim + direction * (ring - width * 2.5), aim + direction * (ring + width * 2.5), core, width, true)
	draw_circle(aim, dot * 2.6, glow)
	draw_circle(aim, dot, core)

func _draw_scope(style: String, aim: Vector2, radius: float, amount: float) -> void:
	var ink := Color(INK, amount)
	var red := Color(RED, amount)
	var glow := Color(RED, 0.25 * amount)
	var thin := maxf(1.2, radius * 0.0042)
	match style:
		"sniper":
			# Duplex crosshair: heavy posts that lead the eye in, fine lines across
			# the centre with mil-dots for holdover, and a lit centre dot.
			var post := radius * 0.42
			var heavy := maxf(3.0, radius * 0.024)
			for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN, Vector2.UP]:
				draw_line(aim + direction * post, aim + direction * radius, ink, heavy, true)
				draw_line(aim, aim + direction * post, ink, thin, true)
				for step in range(1, 5):
					draw_circle(aim + direction * post * step / 5.0, maxf(1.6, radius * 0.0085), ink)
			draw_circle(aim, maxf(2.4, radius * 0.008), glow)
			draw_circle(aim, maxf(1.3, radius * 0.0045), red)
		"marksman":
			# Fine crosshair broken at the centre around a lit dot, posts from the
			# rim and short range marks on the lower stadia.
			var gap := radius * 0.035
			for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.DOWN, Vector2.UP]:
				draw_line(aim + direction * gap, aim + direction * radius, ink, thin, true)
				draw_line(aim + direction * radius * 0.62, aim + direction * radius, ink, maxf(2.6, radius * 0.018), true)
			for step in range(1, 4):
				var y := gap + radius * 0.09 * step
				var half := radius * (0.05 - 0.01 * step)
				draw_line(aim + Vector2(-half, y), aim + Vector2(half, y), ink, thin, true)
			draw_circle(aim, maxf(3.0, radius * 0.012), glow)
			draw_circle(aim, maxf(1.6, radius * 0.006), red)
		_:
			# ACOG-style: a lit chevron whose tip is the point of aim, bullet-drop
			# marks below it and side bars from the rim.
			var tall := radius * 0.075
			var wide := radius * 0.06
			var chevron := PackedVector2Array([aim + Vector2(-wide, tall), aim, aim + Vector2(wide, tall)])
			draw_polyline(chevron, glow, maxf(5.0, radius * 0.03), true)
			draw_polyline(chevron, red, maxf(2.2, radius * 0.011), true)
			var top := tall * 1.5
			var bottom := radius * 0.6
			draw_line(aim + Vector2(0.0, top), aim + Vector2(0.0, bottom), ink, thin, true)
			for step in range(1, 6):
				var y := top + (bottom - top) * step / 6.0
				var half := radius * (0.075 - 0.011 * step)
				draw_line(aim + Vector2(-half, y), aim + Vector2(half, y), ink, thin, true)
			draw_line(aim + Vector2(-radius, 0.0), aim + Vector2(-radius * 0.42, 0.0), ink, thin * 1.6, true)
			draw_line(aim + Vector2(radius * 0.42, 0.0), aim + Vector2(radius, 0.0), ink, thin * 1.6, true)
