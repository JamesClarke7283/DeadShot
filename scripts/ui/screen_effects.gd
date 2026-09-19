extends Control
## Source ScreenEffects.ts: independent flash/blur timers, one replacing tint,
## and a state-only deafen timer. Stun intensity is already 0.6 * proximity.
var flash_state: Dictionary = {}
var blur_state: Dictionary = {}
var tint_state: Dictionary = {}
var deafen_timer := 0.0
var direct: Dictionary = {}
var tint_layer: ColorRect
var blur_horizontal: ColorRect
var blur_vertical: ColorRect
var blur_copy: BackBufferCopy
var flash_layer: ColorRect

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint_layer = _layer()
	var tint_shader := Shader.new()
	tint_shader.code = """shader_type canvas_item;
uniform vec4 tint_color : source_color;
uniform float tint_opacity = 0.0;
void fragment() {
    // CSS's default farthest-corner ellipse reaches 100% at each corner.
    float radius = length((UV - vec2(0.5)) * sqrt(2.0));
    float gradient = clamp((radius - 0.4) / 0.9, 0.0, 1.0);
    COLOR = vec4(tint_color.rgb, tint_color.a * tint_opacity * gradient);
}"""
	tint_layer.material = ShaderMaterial.new()
	tint_layer.material.shader = tint_shader
	var blur_shader := Shader.new()
	blur_shader.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform vec2 direction = vec2(1.0, 0.0);
uniform float sigma = 0.0;
void fragment() {
    // Separable Gaussian in screen pixels. Prefilter wider sample footprints
    // to avoid gaps in the kernel at a point-blank 12px stun.
    vec2 step_uv = SCREEN_PIXEL_SIZE * direction * sigma * 0.3;
    float lod = log2(max(sigma * 0.3, 1.0));
    vec3 sum = vec3(0.0);
    float weight_sum = 0.0;
    for (int tap = -10; tap <= 10; tap++) {
        float offset = float(tap);
        float weight = exp(-0.5 * offset * offset * 0.09);
        sum += textureLod(screen_tex, SCREEN_UV + step_uv * offset, lod).rgb * weight;
        weight_sum += weight;
    }
    COLOR = vec4(sum / weight_sum, 1.0);
}"""
	blur_horizontal = _layer()
	blur_horizontal.material = ShaderMaterial.new()
	blur_horizontal.material.shader = blur_shader
	blur_horizontal.material.set_shader_parameter("direction", Vector2.RIGHT)
	blur_copy = BackBufferCopy.new()
	blur_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	add_child(blur_copy)
	blur_vertical = _layer()
	blur_vertical.material = ShaderMaterial.new()
	blur_vertical.material.shader = blur_shader
	blur_vertical.material.set_shader_parameter("direction", Vector2.DOWN)
	flash_layer = _layer()
	_render()

func _layer() -> ColorRect:
	var result := ColorRect.new()
	add_child(result)
	result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

func _state(intensity: float, duration: float) -> Dictionary:
	return {"intensity": intensity, "duration": duration, "remaining": duration}

func apply_effect(kind: String, intensity: float, duration: float) -> void:
	if duration <= 0:
		return
	match kind:
		"flash", "flashbang": flash_state = _state(clampf(intensity, 0, 1), duration)
		"blur":
			if intensity > 0: blur_state = _state(intensity, duration)
		"stun":
			if intensity > 0: blur_state = _state(intensity * 20.0, duration)
			_set_tint(Color(120.0 / 255, 160.0 / 255, 1, 0.9), intensity, duration)
		"damage": _set_tint(Color(180.0 / 255, 0, 0), intensity, duration)
		"scavenger": _set_tint(Color(1, 204.0 / 255, 51.0 / 255), intensity, duration)
		"deafen": deafen_timer = maxf(deafen_timer, duration)
	_render()

func _set_tint(color: Color, intensity: float, duration: float) -> void:
	tint_state = _state(clampf(intensity, 0, 1), duration)
	tint_state.color = color

func _strength(state: Dictionary) -> float:
	return float(state.intensity) * maxf(0, float(state.remaining) / float(state.duration)) if not state.is_empty() else 0.0

func update_effects(delta: float) -> void:
	deafen_timer = maxf(0, deafen_timer - delta)
	for state in [flash_state, blur_state, tint_state]:
		if state.is_empty(): continue
		state.remaining -= delta
		if state.remaining <= 0: state.clear()
	_render()

func is_deafened() -> bool:
	return deafen_timer > 0

func set_direct(values: Dictionary) -> void:
	# Legacy HUD callers can supply exact opacity/pixel values. The most recent
	# supplied tint wins, matching the single source tint layer.
	for key in ["flashOpacity", "stunBlur"]:
		if values.has(key): direct[key] = maxf(0, float(values[key]))
	for key in ["stunOpacity", "damageOpacity"]:
		if values.has(key):
			direct.tintOpacity = clampf(float(values[key]), 0, 1)
			direct.tintColor = Color(120.0 / 255, 160.0 / 255, 1, 0.9) if key == "stunOpacity" else Color(180.0 / 255, 0, 0)
	_render()

func _render() -> void:
	if not is_instance_valid(tint_layer): return
	var flash := clampf(float(direct.get("flashOpacity", _strength(flash_state))), 0, 1)
	var blur := roundf(float(direct.get("stunBlur", _strength(blur_state))) * 100.0) / 100.0
	var opacity := float(direct.get("tintOpacity", _strength(tint_state)))
	var color: Color = direct.get("tintColor", tint_state.get("color", Color.WHITE))
	tint_layer.material.set_shader_parameter("tint_color", color)
	tint_layer.material.set_shader_parameter("tint_opacity", opacity)
	tint_layer.visible = opacity > 0
	for layer in [blur_horizontal, blur_vertical]:
		layer.material.set_shader_parameter("sigma", blur)
		layer.visible = blur > 0
	blur_copy.visible = blur > 0
	flash_layer.color = Color(1, 1, 1, flash)
	flash_layer.visible = flash > 0
	visible = flash > 0 or blur > 0 or opacity > 0

func clear() -> void:
	flash_state.clear()
	blur_state.clear()
	tint_state.clear()
	direct.clear()
	deafen_timer = 0
	_render()
