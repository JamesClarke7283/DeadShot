class_name GraphicsQuality
extends RefCounted
## Selectable graphics tiers: low, medium, high, ultra.
##
## Every tier is a single preset dictionary rather than a pile of independent
## toggles, so the shipped cost of each level is knowable and testable. A tier
## controls three things:
##   * environment/lighting cost   - MSAA, shadow cascades, SSAO, glow
##   * surface shader complexity   - planar vs triplanar sampling, normal map,
##                                   weathering map, grain contrast
##   * texture and geometry budget - procedural texture resolution, omni shadow
##                                   atlas size, 3D render scale
##
## The surface shader carries QUALITY_* markers; `shader_code(level)` strips the
## blocks a tier does not pay for, so a low-tier fragment shader really does skip
## the three-plane projection and the normal rebuild.


## The first-person weapon renders on its own layer so the viewmodel light rig
## can illuminate it without also lighting the world. Layer 1 stays the default
## world layer, and the main camera renders both.
const VIEWMODEL_LAYER := 2

const LEVELS: Array[String] = ["low", "medium", "high", "ultra"]
const DEFAULT_LEVEL := "high"

## `textures` is the procedural noise resolution, `planar` keeps one projection
## instead of three, `normal`/`macro` enable those maps, `contrast` scales how
## strongly the grain modulates albedo, `cascades` selects the PSSM split count.
const PRESETS := {
	"low": {"glow_levels": [], 
		"msaa": 0,
		"shadow_distance": 48.0,
		"shadow_cascades": 1,
		"shadow_blur": 0.0,
		"shadow_size": 1024,
		"omnishadow_atlas": 512,
		"ssao": false,
		"glow": false,
		"fog": true,
		"render_scale": 0.8,
		"textures": 128,
		"normal": false,
		"macro": false,
		"contrast": 0.45,
		"normal_strength": 0.0,
		"glow_intensity": 0.0,
		"ssao_intensity": 0.0,
		"anisotropic": false,
		"viewmodel_detail": 0.75,
	},
	"medium": {"glow_levels": [1, 2, 3], 
		"msaa": 0,
		"shadow_distance": 62.0,
		"shadow_cascades": 1,
		"shadow_blur": 0.5,
		"shadow_size": 2048,
		"omnishadow_atlas": 1024,
		"ssao": false,
		"glow": true,
		"fog": true,
		"render_scale": 0.9,
		"textures": 256,
		"normal": false,
		"macro": true,
		"contrast": 0.7,
		"normal_strength": 0.0,
		"glow_intensity": 0.4,
		"ssao_intensity": 0.0,
		"anisotropic": true,
		"viewmodel_detail": 1.0,
	},
	"high": {"glow_levels": [1, 2, 4, 6], 
		"msaa": 2,
		"shadow_distance": 72.0,
		"shadow_cascades": 2,
		"shadow_blur": 1.0,
		"shadow_size": 2048,
		"omnishadow_atlas": 2048,
		"ssao": true,
		"glow": true,
		"fog": true,
		"render_scale": 1.0,
		"textures": 256,
		"normal": true,
		"macro": true,
		"contrast": 1.0,
		"normal_strength": 1.0,
		"glow_intensity": 0.5,
		"ssao_intensity": 0.85,
		"anisotropic": true,
		"viewmodel_detail": 1.0,
	},
	"ultra": {"glow_levels": [1, 2, 3, 4, 5, 6, 7], 
		"msaa": 4,
		"shadow_distance": 110.0,
		"shadow_cascades": 4,
		"shadow_blur": 1.5,
		"shadow_size": 4096,
		"omnishadow_atlas": 4096,
		"ssao": true,
		"glow": true,
		"fog": true,
		"render_scale": 1.0,
		"textures": 512,
		"normal": true,
		"macro": true,
		"contrast": 1.15,
		"normal_strength": 1.25,
		"glow_intensity": 0.62,
		"ssao_intensity": 1.0,
		"anisotropic": true,
		"viewmodel_detail": 1.0,
	},
}

const SURFACE_SHADER := preload("res://scripts/world/surface.gdshader")

static var _current := DEFAULT_LEVEL
static var _variants: Dictionary = {}

static func normalize(level: String) -> String:
	var lowered := level.to_lower()
	return lowered if LEVELS.has(lowered) else DEFAULT_LEVEL

static func current() -> String:
	return _current

static func set_current(level: String) -> String:
	_current = normalize(level)
	return _current

static func preset(level: String = "") -> Dictionary:
	return PRESETS[normalize(level if not level.is_empty() else _current)]

## Strips the QUALITY_* blocks a tier does not pay for. Results are cached per
## (flags, level) pair because materials share shader variants.
static func shader_code(level: String, flags: int) -> String:
	var key := "%s_%d" % [normalize(level), flags]
	if _variants.has(key):
		return _variants[key]
	var settings: Dictionary = PRESETS[normalize(level)]
	var code := SURFACE_SHADER.code
	# Normal mapping samples all three planes, so it replaces the planar block.
	# Stripping PLANAR first keeps the two grain assignments mutually exclusive.
	if bool(settings.normal):
		code = _strip(code, "PLANAR")
	else:
		code = _strip(code, "TRIPLANAR")
		code = _strip(code, "NORMAL")
	if not bool(settings.macro):
		code = _strip(code, "MACRO")
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

## Applies the lighting half of a tier to a map's environment and sun.
static func apply_environment(environment: Environment, sun: DirectionalLight3D, level: String = "") -> void:
	var settings := preset(level)
	environment.ssao_enabled = bool(settings.ssao)
	if bool(settings.ssao):
		environment.ssao_intensity = base_number("ssao_intensity") * float(settings.ssao_intensity)
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

## MSAA, the omni shadow atlas and 3D render scale are viewport settings.
static func apply_viewport(viewport: Viewport, level: String = "") -> void:
	if viewport == null:
		return
	var settings := preset(level)
	match int(settings.msaa):
		0: viewport.msaa_3d = Viewport.MSAA_DISABLED
		2: viewport.msaa_3d = Viewport.MSAA_2X
		_: viewport.msaa_3d = Viewport.MSAA_4X
	viewport.positional_shadow_atlas_size = int(settings.omnishadow_atlas)
	viewport.scaling_3d_scale = float(settings.render_scale)
