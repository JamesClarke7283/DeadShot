extends RefCounted

const GREEN := Color("cdeb6e")
const MUTED := Color("9fb0c4")
const INK := Color("0a0c10")
const WHITE := Color("e6edf5")
static var _fonts: Dictionary = {}

static func _font_file(filename: String) -> FontFile:
	if not _fonts.has(filename):
		var path := "res://assets/fonts/" + filename + ".ttf"
		var result: FontFile
		# Support both fresh, unimported workspace files and Godot's exported
		# resource remaps, without relying on a Web browser's system fonts.
		if FileAccess.file_exists(path):
			result = FontFile.new()
			result.load_dynamic_font(path)
		else:
			result = load(path)
		if filename == "NotoSansSymbols2-Regular":
			# Symbol glyphs have a much deeper font-wide descent than Noto Sans.
			# Godot includes fallback metrics even for plain Latin text; normalize
			# line metrics so adding symbols does not move every menu control.
			for font_size in range(8, 129):
				result.get_ascent(font_size)
				result.set_cache_ascent(0, font_size, ceilf(1.069 * font_size))
				result.set_cache_descent(0, font_size, ceilf(0.293 * font_size))
		else:
			result.fallbacks = [_font_file("NotoSansSymbols2-Regular")]
		_fonts[filename] = result
	return _fonts[filename]

static func mono_font() -> Font:
	return _font_file("NotoSansMono-Regular")

static func font(weight: int = 600, spacing: int = 0) -> Font:
	# These are the actual installed Noto faces used by the native reference.
	var face := "Regular" if weight <= 450 else "Medium" if weight <= 550 else "Bold" if weight <= 750 else "Black"
	var result := _font_file("NotoSans-" + face)
	if spacing != 0:
		var spaced := FontVariation.new()
		spaced.base_font = result
		spaced.spacing_glyph = spacing
		return spaced
	return result

static func box(color: Color, edge: Color = INK, radius: int = 10, border: int = 2, padding: int = 14) -> StyleBoxFlat:
	var result := StyleBoxFlat.new()
	result.bg_color = color
	result.border_color = edge
	result.set_border_width_all(border)
	result.set_corner_radius_all(radius)
	result.content_margin_left = padding
	result.content_margin_right = padding
	result.content_margin_top = padding
	result.content_margin_bottom = padding
	return result

static func gradient_box(top: Color, bottom: Color) -> StyleBoxTexture:
	var svg := '<svg xmlns="http://www.w3.org/2000/svg" width="64" height="64"><defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#%s"/><stop offset="1" stop-color="#%s"/></linearGradient></defs><rect x="3" y="3" width="60" height="60" rx="8" fill="#0a0c10"/><rect x="1" y="1" width="60" height="60" rx="8" fill="url(#g)" stroke="#0a0c10" stroke-width="2"/></svg>' % [top.to_html(false), bottom.to_html(false)]
	var image := Image.new()
	image.load_svg_from_string(svg)
	var result := StyleBoxTexture.new()
	result.texture = ImageTexture.create_from_image(image)
	result.texture_margin_left = 10
	result.texture_margin_top = 10
	result.texture_margin_right = 10
	result.texture_margin_bottom = 10
	result.content_margin_left = 22
	result.content_margin_right = 22
	result.content_margin_top = 12
	result.content_margin_bottom = 12
	return result

static func make_theme() -> Theme:
	var result := Theme.new()
	result.default_font = font()
	result.default_font_size = 14
	result.set_color("font_color", "Label", WHITE)
	result.set_font_size("font_size", "Button", 16)
	result.set_font("font", "Button", font(600, 1))
	result.set_stylebox("normal", "Button", gradient_box(GREEN, Color("9fd13e")))
	result.set_stylebox("hover", "Button", gradient_box(GREEN.lightened(0.08), Color("9fd13e").lightened(0.08)))
	result.set_stylebox("pressed", "Button", gradient_box(Color("9fd13e"), GREEN))
	result.set_stylebox("focus", "Button", box(Color.TRANSPARENT, GREEN, 8, 2, 0))
	result.set_stylebox("disabled", "Button", gradient_box(Color("42505f"), Color("2c3845")))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		result.set_color(state, "Button", INK)
	result.set_color("font_disabled_color", "Button", MUTED)
	for state in ["normal", "hover", "pressed", "disabled"]:
		result.set_stylebox(state, "CheckBox", box(Color.TRANSPARENT, Color.TRANSPARENT, 0, 0, 0))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		result.set_color(state, "CheckBox", WHITE)
	result.set_font_size("font_size", "CheckBox", 15)
	for type in ["LineEdit", "OptionButton", "SpinBox"]:
		result.set_stylebox("normal", type, box(Color("1c222d"), Color("424a58"), 6, 1, 9))
		result.set_stylebox("focus", type, box(Color.TRANSPARENT, GREEN, 6, 1, 9))
		result.set_color("font_color", type, WHITE)
		result.set_color("font_hover_color", type, WHITE)
		result.set_color("font_pressed_color", type, WHITE)
	result.set_stylebox("hover", "OptionButton", box(Color("293340"), GREEN, 6, 1, 9))
	result.set_stylebox("pressed", "OptionButton", box(Color("293340"), GREEN, 6, 1, 9))
	result.set_stylebox("panel", "PopupMenu", box(Color("161d28"), Color("424a58"), 6, 1, 6))
	result.set_color("font_color", "PopupMenu", WHITE)
	result.set_stylebox("hover", "PopupMenu", box(Color("516931"), GREEN, 3, 0, 5))
	result.set_stylebox("background", "ProgressBar", box(Color("0a0c10b3"), INK, 5, 2, 0))
	result.set_stylebox("fill", "ProgressBar", box(Color("9fd13e"), Color.TRANSPARENT, 3, 0, 0))
	var slider_track := box(Color("374339"), INK, 4, 1, 0)
	slider_track.content_margin_top = 3
	slider_track.content_margin_bottom = 3
	result.set_stylebox("slider", "HSlider", slider_track)
	var slider_fill := box(Color("9fd13e"), Color.TRANSPARENT, 4, 0, 0)
	slider_fill.content_margin_top = 3
	slider_fill.content_margin_bottom = 3
	result.set_stylebox("grabber_area", "HSlider", slider_fill)
	result.set_stylebox("grabber_area_highlight", "HSlider", slider_fill)
	result.set_constant("separation", "VBoxContainer", 10)
	result.set_constant("separation", "HBoxContainer", 10)
	return result

static func background(parent: Control, transparent: bool = false) -> ColorRect:
	var rect := ColorRect.new()
	parent.add_child(rect)
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if transparent:
		rect.color = Color(0.02, 0.03, 0.05, 0.72)
	else:
		var shader := Shader.new()
		shader.code = 'shader_type canvas_item; void fragment(){float d=length((UV-vec2(0.5,0.1))/vec2(1.2));vec3 c=mix(vec3(0.106,0.137,0.188),vec3(0.039,0.047,0.063),smoothstep(0.0,0.7,d));c=mix(c,vec3(0.02,0.027,0.039),smoothstep(0.7,1.0,d));COLOR=vec4(c,1.0);}'
		var material := ShaderMaterial.new()
		material.shader = shader
		rect.material = material
	return rect
