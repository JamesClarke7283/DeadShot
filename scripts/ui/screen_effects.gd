extends Control
## Screen-effect compositor. Flash/blur/tint timers stay independent and the
## deafen state is still state-only, but every effect now carries a lingering
## second layer so the falloff reads like light and pressure rather than a fade.
##
## Layer order bottom to top: tint wash, colour grade, separable blur, chromatic
## split, additive layers (the white-out, its residual halo and the suppression
## vignette), then the concussive edge. All of them share one BackBufferCopy,
## which is visible whenever a screen-reading pass runs, so the worst frame costs
## five extra quads and an idle frame costs none.
##
## The pinned states keep their linear envelopes exactly (flash, blur, tint): the
## residual layers are additive and separate, which is what lets a flash blow out
## to near-white and still leave a coloured halo behind without reshaping any
## existing decay.
var flash_state: Dictionary = {}
var blur_state: Dictionary = {}
var tint_state: Dictionary = {}
var deafen_timer := 0.0
var direct: Dictionary = {}
var tint_layer: ColorRect
var grade_layer: ColorRect
var blur_horizontal: ColorRect
var blur_vertical: ColorRect
var chroma_layer: ColorRect
var bloom_layer: ColorRect
var vignette_layer: ColorRect
var blur_copy: BackBufferCopy
var flash_layer: ColorRect
## Bloom halo left by a flashbang, and the slow tail a wash keeps after its own
## envelope has run out. Both are separate states so neither reshapes a pinned one.
var bloom_state: Dictionary = {}
var tail_state: Dictionary = {}
## Muffled-audio state in seconds, so a mixer can follow a state change instead of
## re-deriving it from the flash timer, which is the only effect part that lasts.
var audio_muffle_time := 0.0
var _time := 0.0
var _last_muffle_request := -1.0
var _muffle_watchdog := 0.0

## The white-out is a near-total white that the pinned linear envelope carries
## off; the halo underneath is the desaturated blue-white that outlives it.
const FLASH_COLOR=Color(0.94,0.97,1.0)
const BLOOM_COLOR=Color(0.62,0.74,1.0)
const BLOOM_GAIN=0.7
## Extra seconds the halo keeps glowing once the white-out's own timer expires.
const BLOOM_TAIL=1.6
## Extra seconds a tint wash keeps after its envelope, and how strongly.
const TAIL_SPAN=0.5
const TAIL_GAIN=0.55
## Disorientation: the split pulls a sixth of the way to the frame's edge, and the
## body roll sweeps at most a couple of degrees before winding back the other way.
const CHROMA_SPLIT=0.006
const DRIFT_SWING=2.2
const DRIFT_PERIOD=3.2
const DESATURATE=0.75
const GRADE_STRENGTH=0.6
## The HUD pushes direct values through `set_direct` on its refresh, so its key
## lists are constants rather than fresh arrays on every call.
const DIRECT_RAW_KEYS=["flashOpacity","stunBlur"]
const DIRECT_TINT_KEYS=["stunOpacity","damageOpacity","suppressOpacity","concussOpacity"]
## The suppression and concussive vignettes reach this far in from the short edge.
const VIGNETTE_RADIUS=0.62
const SUPPRESS_COLOR=Color(150.0 / 255, 156.0 / 255, 168.0 / 255)

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
	grade_layer = _layer()
	var grade_shader := Shader.new()
	grade_shader.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float desaturate = 0.0;
uniform float grade = 0.0;
void fragment() {
    // Shock drains colour and a near miss only thins it; `grade` is how much of
    // the drain this frame actually takes.
    vec3 source = texture(screen_tex, SCREEN_UV).rgb;
    float luma = dot(source, vec3(0.2126, 0.7152, 0.0722));
    COLOR = vec4(mix(source, vec3(luma), desaturate * grade), 1.0);
}"""
	grade_layer.material = ShaderMaterial.new()
	grade_layer.material.shader = grade_shader
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
	chroma_layer = _layer()
	var chroma_shader := Shader.new()
	chroma_shader.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float split = 0.0;
uniform float drift = 0.0;
void fragment() {
    // Disorientation, not a camera move: the plate is pulled off centre and the
    // channels are split along that pull, so the scene itself stays put while the
    // frame slides out from under the player's eye.
    vec2 centre = vec2(0.5) + vec2(0.0, drift);
    vec2 offset = SCREEN_UV - centre;
    float radius = max(length(offset), 0.0001);
    vec2 pull = vec2(offset.x, -offset.y) / radius * split;
    vec2 sample_uv = centre + offset * (1.0 - split * 0.35);
    float left = texture(screen_tex, sample_uv + pull).g;
    float middle = texture(screen_tex, sample_uv).g;
    float right = texture(screen_tex, sample_uv - pull).g;
    COLOR = vec4(left, middle, right, 1.0);
}"""
	chroma_layer.material = ShaderMaterial.new()
	chroma_layer.material.shader = chroma_shader
	bloom_layer = _layer()
	var bloom_shader := Shader.new()
	bloom_shader.code = """shader_type canvas_item;
uniform sampler2D screen_tex : hint_screen_texture, repeat_disable, filter_linear;
uniform float opacity = 0.0;
uniform vec4 bloom_color : source_color = vec4(1.0);
void fragment() {
    // The halo keeps the light the white-out blew out rather than flooding the
    // frame again, so what lingers reads as brightness still coming off the eye.
    float radius = length((UV - vec2(0.5)) * sqrt(2.0));
    float falloff = 1.0 - clamp((radius - 0.35) / 1.1, 0.0, 1.0);
    float luma = smoothstep(0.15, 0.95, dot(texture(screen_tex, SCREEN_UV).rgb, vec3(0.2126, 0.7152, 0.0722)));
    COLOR = vec4(bloom_color.rgb, bloom_color.a * opacity * falloff * (0.55 + 0.45 * luma));
}"""
	bloom_layer.material = ShaderMaterial.new()
	bloom_layer.material.shader = bloom_shader
	bloom_layer.material.set_shader_parameter("bloom_color", BLOOM_COLOR)
	vignette_layer = _layer()
	var vignette_shader := Shader.new()
	vignette_shader.code = """shader_type canvas_item;
uniform float opacity = 0.0;
uniform vec4 vignette_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float radius = 0.62;
void fragment() {
    // Short-edge normalised so the band closes in identically on any aspect.
    vec2 centred = UV - vec2(0.5);
    vec2 scaled = centred * vec2(SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x, 1.0) * 2.0;
    COLOR = vec4(vignette_color.rgb, vignette_color.a * opacity * smoothstep(radius, 1.15, length(scaled)));
}"""
	vignette_layer.material = ShaderMaterial.new()
	vignette_layer.material.shader = vignette_shader
	vignette_layer.material.set_shader_parameter("radius", VIGNETTE_RADIUS)
	flash_layer = _layer()
	_render()

func _layer() -> ColorRect:
	var result := ColorRect.new()
	add_child(result)
	result.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	result.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return result

## `curve` names the falloff a state decays along, so every timer stays the same
## shape of object and `_strength` remains the one place they are all read.
func _state(intensity: float, duration: float, curve: String = "linear") -> Dictionary:
	return {"intensity": intensity, "duration": duration, "remaining": duration, "curve": curve}

func apply_effect(kind: String, intensity: float, duration: float) -> void:
	if duration <= 0:
		return
	match kind:
		# A flashbang is a blowout plus an afterimage, not just a brightening: the
		# white-out rides the pinned envelope and the halo rides its own longer
		# timer, so the light is still there after the frame has cleared.
		"flash", "flashbang":
			flash_state = _state(clampf(intensity, 0, 1), duration)
			bloom_state = _state(clampf(intensity, 0, 1), duration + BLOOM_TAIL, "linger")
			audio_muffle_time = maxf(audio_muffle_time, duration)
			_request_muffle(duration)
		"blur":
			if intensity > 0: blur_state = _state(intensity, duration)
		"stun":
			# The blur is the pinned quantity; the split, the roll and the drain
			# ride the same timer, and the kind tells `_render` to draw them.
			if intensity > 0:
				blur_state = _state(intensity * 20.0, duration)
				blur_state.kind = "stun"
			_set_tint(Color(120.0 / 255, 160.0 / 255, 1, 0.9), intensity, duration)
		# A hit lands at full strength on the frame it lands and then keeps a
		# slow tail behind its own envelope instead of dropping straight away.
		"damage": _set_tint(Color(180.0 / 255, 0, 0), intensity, duration, "damage")
		"scavenger": _set_tint(Color(1, 204.0 / 255, 51.0 / 255), intensity, duration)
		"deafen": deafen_timer = maxf(deafen_timer, duration)
		# Rounds passing close: colour drains out of the frame and the edges close
		# in, both released along one short tail.
		"suppress", "suppression": _set_tint(SUPPRESS_COLOR, clampf(intensity, 0, 1), duration, "suppress")
		# Concussion from a lethal the player threw themselves: the edge closes in
		# hard and holds longer than the wash it arrives with.
		"concuss": _set_tint(Color(0, 0, 0), clampf(intensity, 0, 1), duration, "concuss")
	_render()

## `kind` decides what the wash also drives: the suppression drain, the
## concussive edge, or the extra tail this one leaves behind.
func _set_tint(color: Color, intensity: float, duration: float, kind: String = "") -> void:
	tint_state = _state(clampf(intensity, 0, 1), duration)
	tint_state.color = color
	tint_state.kind = kind
	# The tail is the slowly-released part of the same wash, so it carries the
	# same colour and fades over a longer span than the pinned envelope.
	tail_state = _state(clampf(intensity, 0, 1) * TAIL_GAIN, duration * (1.0 + TAIL_SPAN), "linger")
	tail_state.color = color
	tail_state.kind = kind

## Normalised remaining time: 1 at the start of an effect, 0 when it expires.
func _decay(state: Dictionary) -> float:
	var duration := float(state.duration)
	if duration <= 0: return 0.0
	var fraction := clampf(float(state.remaining) / duration, 0.0, 1.0)
	# A lingering layer spends its time differently from the envelope it trails:
	# most of the light is still there halfway through a tail, which is what makes
	# an afterimage read as an afterimage rather than a slower fade.
	if str(state.curve) == "linger": return sqrt(fraction)
	return fraction

func _strength(state: Dictionary) -> float:
	return float(state.intensity) * _decay(state) if not state.is_empty() else 0.0

func update_effects(delta: float) -> void:
	deafen_timer = maxf(0, deafen_timer - delta)
	audio_muffle_time = maxf(0, audio_muffle_time - delta)
	_time += delta
	# Stepped one at a time rather than over an array literal: this runs every
	# frame, and a literal here would allocate a fresh Array per frame.
	_advance(flash_state, delta)
	_advance(blur_state, delta)
	_advance(tint_state, delta)
	_advance(bloom_state, delta)
	_advance(tail_state, delta)
	_pump_audio_hook(delta)
	_render()

func _advance(state: Dictionary, delta: float) -> void:
	if state.is_empty(): return
	state.remaining -= delta
	if state.remaining <= 0: state.clear()

func is_deafened() -> bool:
	return deafen_timer > 0

## Muffled-audio state a mixer can follow. `deafen` holds it for the blast and the
## flash's own wash holds it for as long as the world is still blown out.
func is_audio_muffled() -> bool:
	return audio_muffle_time > 0 or deafen_timer > 0

func audio_muffle() -> float:
	return clampf(maxf(audio_muffle_time, deafen_timer) / 4.0, 0.0, 1.0)

func set_direct(values: Dictionary) -> void:
	# Legacy HUD callers can supply exact opacity/pixel values. The most recent
	# supplied tint wins, matching the single source tint layer.
	for key in DIRECT_RAW_KEYS:
		if values.has(key): direct[key] = maxf(0, float(values[key]))
	for key in DIRECT_TINT_KEYS:
		if values.has(key):
			direct.tintOpacity = clampf(float(values[key]), 0, 1)
			direct.tintColor = Color(120.0 / 255, 160.0 / 255, 1, 0.9) if key == "stunOpacity" else (Color(180.0 / 255, 0, 0) if key == "damageOpacity" else SUPPRESS_COLOR if key == "suppressOpacity" else Color(0, 0, 0))
			direct.tintKind = "" if key == "stunOpacity" or key == "damageOpacity" else ("suppress" if key == "suppressOpacity" else "concuss")
	_render()

func _render() -> void:
	if not is_instance_valid(tint_layer): return
	var flash := clampf(float(direct.get("flashOpacity", _strength(flash_state))), 0, 1)
	var blur := roundf(float(direct.get("stunBlur", _strength(blur_state))) * 100.0) / 100.0
	# The wash is its envelope plus the tail it trails, so a hit keeps a trace of
	# colour after the envelope itself has expired.
	var opacity := clampf(float(direct.get("tintOpacity", _strength(tint_state) + _strength(tail_state))), 0, 1)
	var color: Color = direct.get("tintColor", tint_state.get("color", tail_state.get("color", Color.WHITE)))
	var kind := str(direct.get("tintKind", tint_state.get("kind", tail_state.get("kind", ""))))
	var stun := 0.0 if direct.has("stunBlur") else (_strength(blur_state) if str(blur_state.get("kind", "")) == "stun" else 0.0)
	var suppressed := opacity if kind == "suppress" else 0.0
	var concuss := opacity if kind == "concuss" else 0.0
	var grade := maxf(clampf(stun / 20.0, 0.0, 1.0) * DESATURATE * GRADE_STRENGTH, suppressed)
	var split := clampf(stun / 20.0, 0.0, 1.0) * CHROMA_SPLIT
	var bloom := 0.0 if direct.has("flashOpacity") else _strength(bloom_state) * BLOOM_GAIN
	tint_layer.material.set_shader_parameter("tint_color", color)
	tint_layer.material.set_shader_parameter("tint_opacity", opacity)
	# The concussive edge is a black wash, and the vignette layer already draws
	# that frame better; skipping the flat tint keeps it from crushing the centre.
	tint_layer.visible = opacity > 0 and kind != "concuss"
	grade_layer.material.set_shader_parameter("desaturate", DESATURATE)
	grade_layer.material.set_shader_parameter("grade", grade)
	grade_layer.visible = grade > 0
	# Set explicitly rather than over an array literal, for the same per-frame
	# allocation reason as the timers above.
	blur_horizontal.material.set_shader_parameter("sigma", blur)
	blur_horizontal.visible = blur > 0
	blur_vertical.material.set_shader_parameter("sigma", blur)
	blur_vertical.visible = blur > 0
	chroma_layer.material.set_shader_parameter("split", split)
	# The roll sweeps one way as the stun lands and back the other as it releases,
	# which is the part of a stun that reads as the player's own balance going.
	chroma_layer.material.set_shader_parameter("drift", clampf(stun / 20.0, 0.0, 1.0) * sin(_time * TAU / DRIFT_PERIOD) * DRIFT_SWING / 720.0)
	chroma_layer.visible = split > 0
	bloom_layer.material.set_shader_parameter("opacity", bloom)
	bloom_layer.visible = bloom > 0
	vignette_layer.material.set_shader_parameter("opacity", maxf(suppressed, concuss))
	vignette_layer.visible = maxf(suppressed, concuss) > 0
	flash_layer.color = Color(FLASH_COLOR.r, FLASH_COLOR.g, FLASH_COLOR.b, flash)
	flash_layer.visible = flash > 0
	# The screen-reading passes share one copy of the frame, so it is live whenever
	# the grade, the blur or the split needs to read it.
	blur_copy.visible = grade > 0 or blur > 0 or split > 0
	visible = flash > 0 or bloom > 0 or blur > 0 or opacity > 0 or grade > 0 or suppressed > 0 or concuss > 0

## Pushes the muffled-audio state to an AudioManager when one is reachable. It is
## found by walking up from this layer rather than being wired in, because the
## effect layer is built before the match exists; the request dedupes on the
## duration it would send, so a steady state costs one comparison a second.
func _pump_audio_hook(delta: float) -> void:
	_muffle_watchdog -= delta
	if _muffle_watchdog > 0.0: return
	# The mixer's deafen is a tween back toward full volume, so it has to be
	# re-requested while the state is still running or the muffle decays off
	# before the wash does.
	_muffle_watchdog = 1.0
	var wanted := maxf(audio_muffle_time, deafen_timer)
	if absf(wanted - _last_muffle_request) > 0.25:
		_last_muffle_request = wanted
		_request_muffle(wanted)

func _request_muffle(duration: float) -> void:
	if duration <= 0.0: return
	var audio := _find_audio_manager()
	if audio != null: audio.deafen(duration)

func _find_audio_manager() -> Node:
	var node: Node = self
	while node != null:
		var found := node.get_node_or_null("AudioManager")
		if found != null and found.has_method("deafen"): return found
		node = node.get_parent()
	return null

func clear() -> void:
	flash_state.clear()
	blur_state.clear()
	tint_state.clear()
	bloom_state.clear()
	tail_state.clear()
	direct.clear()
	deafen_timer = 0
	audio_muffle_time = 0
	_muffle_watchdog = 0.0
	_last_muffle_request = -1.0
	_render()
