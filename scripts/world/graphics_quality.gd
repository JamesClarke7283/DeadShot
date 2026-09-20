class_name GraphicsQuality
extends RefCounted
## Continuous graphics detail, with four named anchor tiers along it.
##
## The shipped control is a single **detail** value, 0–100, that trades
## performance for looks. The four named tiers (Low, Medium, High, Ultra) are
## anchor points on that slider rather than separate code paths:
##
##   detail  =  0   33   66   100
##   tier    = low  med  high ultra
##
## Everything the tiers used to control is either interpolated along the slider
## or steps at the anchor where its feature band changes:
##
##   * environment/lighting cost   - MSAA, screen-space AA, shadow cascades and
##                                   distance, SSAO, SSIL, SSR, SDFGI, volumetric
##                                   fog, glow
##   * surface shader complexity   - planar vs triplanar sampling, normal map,
##                                   weathering map, parallax occlusion mapping,
##                                   grain contrast
##   * texture and geometry budget - procedural texture resolution, omni shadow
##                                   atlas size, 3D render scale, light budget
##
## Continuous values interpolate between neighbouring anchors, so dragging the
## slider gives a graded cost curve instead of four cliffs. Discrete features
## (a shader block, a boolean pass) stay at the lower anchor and switch on once
## the slider reaches the anchor that owns them — that is also what keeps the
## shader variant count at four instead of a recompile per slider step.
##
## The surface shader carries QUALITY_* markers; `shader_code(level)` strips the
## blocks a band does not pay for, so a low-band fragment shader really does skip
## the three-plane projection, the normal rebuild and the parallax march.


## The first-person weapon renders on its own layer so the viewmodel light rig
## can illuminate it without also lighting the world. Layer 1 stays the default
## world layer, and the main camera renders both.
const VIEWMODEL_LAYER := 2

const LEVELS: Array[String] = ["low", "medium", "high", "ultra"]
const DEFAULT_LEVEL := "high"

## Slider position each named tier sits at. `low` is zero so every detail value
## resolves to a band.
const LEVEL_DETAIL := {"low": 0.0, "medium": 33.0, "high": 66.0, "ultra": 100.0}

## Anchor presets. Numeric values interpolate between neighbouring anchors;
## booleans and arrays step at the anchor. `textures` is the procedural detail
## map resolution, `cascades` the PSSM split count, `msaa`/`screen_aa` the
## antialiasing, `pom` the parallax occlusion march, `lights` the concurrent
## dynamic VFX light budget.
const PRESETS := {
	"low": {
		"glow_levels": [],
		"msaa": 0,
		"screen_aa": 0,
		"taa": false,
		"shadow_distance": 48.0,
		"shadow_cascades": 1,
		"shadow_blur": 0.0,
		"shadow_size": 1024,
		"omnishadow_atlas": 512,
		"ssao": false,
		"ssil": false,
		"ssr": false,
		"sdfgi": false,
		"glow": false,
		"fog": true,
		"volumetric_fog": false,
		"render_scale": 0.8,
		"textures": 128,
		"normal": false,
		"macro": false,
		"pom": false,
		"contrast": 0.45,
		"normal_strength": 0.0,
		"pom_strength": 0.0,
		"glow_intensity": 0.0,
		"ssao_intensity": 0.0,
		"ssil_intensity": 0.0,
		"sdfgi_energy": 0.0,
		"volumetric_density": 0.0,
		"anisotropic": false,
		"viewmodel_detail": 0.75,
		"lights": 2,
	},
	"medium": {
		"glow_levels": [2, 3],
		"msaa": 0,
		"screen_aa": 1,
		"taa": false,
		"shadow_distance": 62.0,
		"shadow_cascades": 1,
		"shadow_blur": 0.5,
		"shadow_size": 2048,
		"omnishadow_atlas": 1024,
		"ssao": false,
		"ssil": false,
		"ssr": false,
		"sdfgi": false,
		"glow": true,
		"fog": true,
		"volumetric_fog": false,
		"render_scale": 0.9,
		"textures": 256,
		"normal": false,
		"macro": true,
		"pom": false,
		"contrast": 0.7,
		"normal_strength": 0.0,
		"pom_strength": 0.0,
		"glow_intensity": 0.4,
		"ssao_intensity": 0.0,
		"ssil_intensity": 0.0,
		"sdfgi_energy": 0.0,
		"volumetric_density": 0.0,
		"anisotropic": true,
		"viewmodel_detail": 1.0,
		"lights": 4,
	},
	"high": {
		"glow_levels": [1, 2, 4, 6],
		"msaa": 2,
		"screen_aa": 0,
		"taa": false,
		"shadow_distance": 72.0,
		"shadow_cascades": 2,
		"shadow_blur": 1.0,
		"shadow_size": 2048,
		"omnishadow_atlas": 2048,
		"ssao": true,
		"ssil": true,
		"ssr": true,
		"sdfgi": false,
		"glow": true,
		"fog": true,
		"volumetric_fog": true,
		"render_scale": 1.0,
		"textures": 512,
		"normal": true,
		"macro": true,
		"pom": true,
		"contrast": 1.0,
		"normal_strength": 1.0,
		"pom_strength": 0.6,
		"glow_intensity": 0.5,
		"ssao_intensity": 0.85,
		"ssil_intensity": 0.7,
		"sdfgi_energy": 0.0,
		"volumetric_density": 0.004,
		"anisotropic": true,
		"viewmodel_detail": 1.0,
		"lights": 8,
	},
	"ultra": {
		"glow_levels": [1, 2, 3, 4, 5, 6, 7],
		"msaa": 4,
		"screen_aa": 0,
		"taa": true,
		"shadow_distance": 110.0,
		"shadow_cascades": 4,
		"shadow_blur": 1.5,
		"shadow_size": 4096,
		"omnishadow_atlas": 4096,
		"ssao": true,
		"ssil": true,
		"ssr": true,
		"sdfgi": true,
		"glow": true,
		"fog": true,
		"volumetric_fog": true,
		"render_scale": 1.0,
		"textures": 1024,
		"normal": true,
		"macro": true,
		"pom": true,
		"contrast": 1.15,
		"normal_strength": 1.25,
		"pom_strength": 1.0,
		"glow_intensity": 0.62,
		"ssao_intensity": 1.0,
		"ssil_intensity": 1.0,
		"sdfgi_energy": 1.0,
		"volumetric_density": 0.008,
		"anisotropic": true,
		"viewmodel_detail": 1.0,
		"lights": 12,
	},
}

## Keys whose value is a continuous quantity and therefore interpolates between
## anchors. Everything else steps at the anchor that defines it.
const NUMERIC_KEYS: Array[String] = [
	"shadow_distance", "shadow_blur", "render_scale", "contrast", "normal_strength",
	"pom_strength", "glow_intensity", "ssao_intensity", "ssil_intensity",
	"sdfgi_energy", "volumetric_density", "viewmodel_detail",
]

const SURFACE_SHADER := preload("res://scripts/world/surface.gdshader")

static var _detail := LEVEL_DETAIL[DEFAULT_LEVEL]
static var _variants: Dictionary = {}
static var _preset_cache: Dictionary = {}

static func normalize(level: String) -> String:
	var lowered := level.to_lower()
	return lowered if LEVELS.has(lowered) else DEFAULT_LEVEL

## The band a detail value falls in: the highest anchor the slider has reached.
## This is what selects the shader variant, so a band's features are only paid
## for once the slider is fully at that anchor.
static func level_for_detail(detail: float) -> String:
	var resolved := DEFAULT_LEVEL
	for level: String in LEVELS:
		if detail >= float(LEVEL_DETAIL[level]):
			resolved = level
	return resolved

static func detail() -> float:
	return _detail

## Sets the slider. Returns the resolved band.
static func set_detail(detail: float) -> String:
	_detail = clampf(detail, 0.0, 100.0)
	_preset_cache.clear()
	return level_for_detail(_detail)

static func detail_for_level(level: String) -> float:
	return float(LEVEL_DETAIL[normalize(level)])

## Convenience bridge for callers that speak tiers: moves the slider to that
## tier's anchor, which is exactly the old behaviour.
static func set_current(level: String) -> String:
	return set_detail(detail_for_level(level))

static func current() -> String:
	return level_for_detail(_detail)

## Interpolated preset for a slider value.
static func preset_for_detail(detail: float) -> Dictionary:
	var clamped := clampf(detail, 0.0, 100.0)
	var key := "%.3f" % clamped
	if _preset_cache.has(key):
		return _preset_cache[key]
	var lower := "low"
	var upper := "low"
	for level: String in LEVELS:
		if float(LEVEL_DETAIL[level]) <= clamped:
			lower = level
			upper = level
	for level: String in LEVELS:
		if float(LEVEL_DETAIL[level]) > clamped:
			upper = level
			break
	var low_preset: Dictionary = PRESETS[lower]
	var high_preset: Dictionary = PRESETS[upper]
	var span := float(LEVEL_DETAIL[upper]) - float(LEVEL_DETAIL[lower])
	var weight := 0.0 if span <= 0.0 else (clamped - float(LEVEL_DETAIL[lower])) / span
	var result: Dictionary = {}
	for name: String in low_preset:
		var low_value: Variant = low_preset[name]
		var high_value: Variant = high_preset[name]
		if NUMERIC_KEYS.has(name) and low_value is float and high_value is float:
			result[name] = lerpf(float(low_value), float(high_value), weight)
		else:
			# Discrete features and integer budgets stay at the lower anchor.
			result[name] = low_value
	_preset_cache[key] = result
	return result

static func preset(level: String = "") -> Dictionary:
	if not level.is_empty():
		return preset_for_detail(detail_for_level(level))
	return preset_for_detail(_detail)

## Strips the QUALITY_* blocks a band does not pay for. Results are cached per
## (flags, band) pair because materials share shader variants.
static func shader_code(level: String, flags: int) -> String:
	var key := "%s_%d" % [normalize(level), flags]
	if _variants.has(key):
		return _variants[key]
	var settings: Dictionary = PRESETS[normalize(level)]
	var code := SURFACE_SHADER.code
	# Parallax occlusion sampling needs the triplanar basis; the normal rebuild
	# replaces the planar grain projection. Stripping PLANAR first keeps the two
	# grain assignments mutually exclusive.
	if bool(settings.normal):
		code = _strip(code, "PLANAR")
	else:
		code = _strip(code, "TRIPLANAR")
		code = _strip(code, "NORMAL")
	if not bool(settings.macro):
		code = _strip(code, "MACRO")
	if not bool(settings.pom):
		code = _strip(code, "POM")
	# flags: 1 double-sided, 2 no depth test, 4 no depth write, 8 additive,
	# 16 transparent alpha.
	if flags & 1:
		code = code.replace("cull_back", "cull_disabled")
	var modes := PackedStringArray()
	if flags & 2:
		modes.append("depth_test_disabled")
	if flags & 4:
		modes.append("depth_draw_never")
	if flags & 8:
		modes.append("blend_add")
	if not modes.is_empty():
		code = code.replace("render_mode cull_back,", "render_mode cull_back, " + ", ".join(modes) + ",")
	if flags & 16:
		code = code.replace("// TRANSPARENT_ALPHA", "ALPHA = alpha_value;")
	else:
		code = code.replace("// TRANSPARENT_ALPHA", "")
	if not bool(settings.anisotropic):
		code = code.replace("filter_linear_mipmap_anisotropic", "filter_linear_mipmap")
	# Enabled features keep their markers, which are comments the compiler ignores
	# but which make the produced variant hard to read. Drop them once stripping
	# is done.
	var lines := PackedStringArray()
	for line in code.split("\n"):
		if not line.strip_edges().begins_with("// QUALITY_"):
			lines.append(line)
	code = "\n".join(lines)
	_variants[key] = code
	return code

## Removes every block with this marker. A feature can contribute more than one
## block (triplanar sampling declares helpers and then uses them), so a single
## pass would leave a call to a function that no longer exists.
static func _strip(code: String, block: String) -> String:
	var begin_marker := "// QUALITY_%s_BEGIN" % block
	var end_marker := "// QUALITY_%s_END" % block
	var result := code
	while true:
		var begin := result.find(begin_marker)
		if begin < 0:
			break
		var end := result.find(end_marker)
		if end < 0:
			break
		# Drop the block and the newline that terminates its END marker, leaving
		# the surrounding lines intact.
		var resume := end + end_marker.length()
		if result.substr(resume, 1) == "\n":
			resume += 1
		result = result.substr(0, begin) + result.substr(resume)
	return result

## True when the renderer can execute the screen-space and global-illumination
## passes. The Compatibility renderer (the Web build) ignores them, and pushing
## those values there only produces engine warnings.
static func advanced_lighting_supported() -> bool:
	return RenderingServer.get_current_rendering_method() == "forward_plus"

## Applies the lighting half of the slider to a map's environment and sun.
static func apply_environment(environment: Environment, sun: DirectionalLight3D, level: String = "") -> void:
	var settings := preset(level)
	var advanced := advanced_lighting_supported()
	environment.ssao_enabled = bool(settings.ssao)
	if bool(settings.ssao):
		environment.ssao_intensity = base_number("ssao_intensity") * float(settings.ssao_intensity)
	if advanced:
		# Indirect light from off-screen and unshadowed geometry. SSIL is the
		# cheaper half — it reads the depth buffer — so it turns on a band before
		# SDFGI, which voxelises the scene.
		environment.ssil_enabled = bool(settings.ssil)
		if bool(settings.ssil):
			environment.ssil_intensity = float(settings.ssil_intensity)
			environment.ssil_radius = lerpf(4.0, 9.0, float(settings.ssil_intensity))
			environment.ssil_sharpness = 0.98
			environment.ssil_normal_rejection = 1.0
		environment.ssr_enabled = bool(settings.ssr)
		if bool(settings.ssr):
			environment.ssr_max_steps = 64
			environment.ssr_fade_in = 0.15
			environment.ssr_fade_out = 2.0
			environment.ssr_depth_tolerance = 0.2
		# Voxel GI grounds the scene with real bounce light and single-bounce
		# reflections; it is the single most expensive feature here, so it is the
		# last thing the slider buys.
		environment.sdfgi_enabled = bool(settings.sdfgi)
		if bool(settings.sdfgi):
			environment.sdfgi_cascades = 4
			environment.sdfgi_min_cell_size = 0.2
			environment.sdfgi_cascade0_distance = 12.8
			environment.sdfgi_max_distance = 200.0
			environment.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_50_PERCENT
			environment.sdfgi_energy = float(settings.sdfgi_energy)
			environment.sdfgi_bounce_feedback = 0.5
			environment.sdfgi_read_sky_light = true
			environment.sdfgi_use_occlusion = true
			environment.sdfgi_normal_bias = 1.1
			environment.sdfgi_probe_bias = 1.1
		# Volumetric fog gives the sun real god rays and makes the depth fog a
		# participating medium rather than a per-pixel tint.
		#
		# The injection terms are the difference between atmosphere and fog soup.
		# Ambient and sky injection feed the scene's radiance back into the
		# medium, and with a sky-sourced ambient that is a large quantity, so the
		# volume lit itself from every direction and washed the frame flat — far
		# and sky regions measured 0.476 luminance with the volume against 0.210
		# without, while the sun's contribution was invisible under it. Real haze
		# scatters mostly the sun; a little ambient keeps shadowed haze from
		# going black. Density is deliberately low for the same reason: the
		# arenas are daylight exteriors, not night streets.
		environment.volumetric_fog_enabled = bool(settings.volumetric_fog)
		if bool(settings.volumetric_fog):
			environment.volumetric_fog_density = float(settings.volumetric_density)
			environment.volumetric_fog_albedo = Color(1, 1, 1)
			environment.volumetric_fog_emission = Color(0, 0, 0)
			environment.volumetric_fog_emission_energy = 0.0
			environment.volumetric_fog_gi_inject = 0.0
			environment.volumetric_fog_anisotropy = 0.35
			environment.volumetric_fog_length = 96.0
			environment.volumetric_fog_detail_spread = 2.0
			environment.volumetric_fog_ambient_inject = 0.06
			environment.volumetric_fog_sky_affect = 0.05
			environment.volumetric_fog_temporal_reprojection_enabled = true
			environment.volumetric_fog_temporal_reprojection_amount = 0.9
		# Reflections come from the sky or the probes; a stronger probe blend is
		# only truthful once one of those exists.
		environment.reflected_light_source = Environment.REFLECTION_SOURCE_SKY if not bool(settings.sdfgi) else Environment.REFLECTION_SOURCE_SKY
	environment.glow_enabled = bool(settings.glow)
	if bool(settings.glow):
		environment.glow_intensity = base_number("glow_intensity") * float(settings.glow_intensity)
		# Only the listed blur levels stay enabled; the rest are switched off so
		# the renderer skips their passes entirely.
		var wanted: Array = settings.glow_levels
		for index in range(1, 8):
			environment.set("glow_levels/%d" % index, 1.0 if wanted.has(index) else 0.0)
	environment.fog_enabled = bool(settings.fog)
	if sun != null:
		sun.directional_shadow_max_distance = float(settings.shadow_distance)
		sun.shadow_blur = float(settings.shadow_blur)
		match int(settings.shadow_cascades):
			1: sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
			2: sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
			_: sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS

## Baseline intensities the shipped environment is authored with; tiers scale
## these rather than hard-coding their own values, so the look stays consistent.
static var _baseline: Dictionary = {}

static func capture_baseline(environment: Environment) -> void:
	_baseline = {"ssao_intensity": environment.ssao_intensity, "glow_intensity": environment.glow_intensity}

static func base_number(key: String, fallback: float = 1.0) -> float:
	return float(_baseline.get(key, fallback))

## MSAA, the antialiasing mode, the omni shadow atlas, the shadow atlas size and
## 3D render scale are viewport settings.
static func apply_viewport(viewport: Viewport, level: String = "") -> void:
	if viewport == null:
		return
	var settings := preset(level)
	match int(settings.msaa):
		0: viewport.msaa_3d = Viewport.MSAA_DISABLED
		2: viewport.msaa_3d = Viewport.MSAA_2X
		_: viewport.msaa_3d = Viewport.MSAA_4X
	match int(settings.screen_aa):
		0: viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
		1: viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
		_: viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	# TAA resolves the sub-pixel detail the parallax and normal maps add, and
	# steadies SDFGI's voxel noise. It is only truthful once those features are on.
	viewport.use_taa = bool(settings.taa) and advanced_lighting_supported()
	viewport.positional_shadow_atlas_size = int(settings.omnishadow_atlas)
	viewport.scaling_3d_scale = float(settings.render_scale)
