class_name MapMaterial
extends RefCounted
## Realistic surface palette shared by maps, models, props and equipment.
##
## The ported geometry carries one flat base colour per material plus the node
## name it belongs to, so a surface profile is chosen from that name (with a
## colour fallback) and drives grain, roughness, specular and weathering.
##
## The exported palettes were authored for an unlit toon look: weapon and prop
## tones sit between 0.008 and 0.09 linear, which is far darker than any real
## blued steel or polymer when shaded. Those families are therefore remapped with
## a gamma curve into a physically plausible albedo range. Natural surfaces (sand,
## plaster, foliage, cloth) keep their exported tones exactly.

const SURFACE: Shader = preload("res://scripts/world/surface.gdshader")
const UNLIT: Shader = preload("res://scripts/world/unlit.gdshader")
const LIBRARY = preload("res://scripts/world/surface_library.gd")
const QUALITY = preload("res://scripts/world/graphics_quality.gd")
const DEFAULT_COLOR := Color(0.5, 0.5, 0.5)

## Minimum and maximum luminance, albedo saturation, roughness, metallic,
## specular, detail
## tiling per metre, macro strength, normal strength, the noise range mapped
## into the detail multiplier, and the weathering tiling.
##
## The exported palettes were authored for an unlit toon look, so several
## families contain near-black variants (shadowed building walls, dark tree
## canopies) that lose all material detail once real lighting is applied.
## `minLuminance` and `maxLuminance` pull both ends of that range into a
## plausible reflectance while keeping each tone's hue and channel ratio.
const PROFILES := {
	"sand": {"dust": 0.22, "grime": 0.05, "minLuminance": 0.1, "maxLuminance": 0.34, "saturation": 0.9, "roughness": 0.97, "metallic": 0.0, "specular": 0.22, "tiling": 0.45, "macro": 0.26, "normal": 1.0, "detail": [0.86, 1.06], "macroScale": 0.05},
	"dirt": {"dust": 0.18, "grime": 0.08, "minLuminance": 0.09, "maxLuminance": 0.24, "saturation": 0.9, "roughness": 0.95, "metallic": 0.0, "specular": 0.25, "tiling": 0.5, "macro": 0.3, "normal": 0.95, "detail": [0.84, 1.06], "macroScale": 0.055},
	"plaster": {"dust": 0.16, "grime": 0.22, "minLuminance": 0.13, "maxLuminance": 0.55, "saturation": 0.92, "roughness": 0.9, "metallic": 0.0, "specular": 0.35, "tiling": 0.7, "macro": 0.22, "normal": 0.6, "detail": [0.9, 1.04], "macroScale": 0.05},
	"concrete": {"dust": 0.18, "grime": 0.2, "minLuminance": 0.12, "maxLuminance": 0.38, "saturation": 0.9, "roughness": 0.85, "metallic": 0.0, "specular": 0.42, "tiling": 0.6, "macro": 0.24, "normal": 0.7, "detail": [0.88, 1.05], "macroScale": 0.045},
	"wood": {"dust": 0.1, "grime": 0.18, "minLuminance": 0.1, "maxLuminance": 0.3, "saturation": 1.0, "roughness": 0.7, "metallic": 0.0, "specular": 0.38, "tiling": 1.1, "macro": 0.22, "normal": 0.8, "detail": [0.86, 1.06], "macroScale": 0.07},
	"fabric": {"dust": 0.08, "grime": 0.1, "minLuminance": 0.09, "maxLuminance": 0.34, "saturation": 0.95, "roughness": 0.94, "metallic": 0.0, "specular": 0.2, "tiling": 2.4, "macro": 0.16, "normal": 0.9, "detail": [0.9, 1.05], "macroScale": 0.09},
	"stone": {"dust": 0.14, "grime": 0.22, "minLuminance": 0.1, "maxLuminance": 0.4, "saturation": 0.95, "roughness": 0.88, "metallic": 0.0, "specular": 0.35, "tiling": 0.8, "macro": 0.28, "normal": 0.85, "detail": [0.84, 1.06], "macroScale": 0.06},
	"foliage": {"dust": 0.1, "grime": 0.05, "minLuminance": 0.13, "maxLuminance": 0.26, "saturation": 0.34, "roughness": 0.88, "metallic": 0.0, "specular": 0.3, "tiling": 1.8, "macro": 0.2, "normal": 1.0, "detail": [0.78, 1.1], "macroScale": 0.07},
	"grass": {"dust": 0.08, "grime": 0.04, "minLuminance": 0.14, "maxLuminance": 0.28, "saturation": 0.32, "roughness": 0.92, "metallic": 0.0, "specular": 0.28, "tiling": 3.2, "macro": 0.24, "normal": 1.1, "detail": [0.76, 1.12], "macroScale": 0.09},
	"snow": {"dust": 0.05, "grime": 0.03, "minLuminance": 0.3, "maxLuminance": 0.72, "saturation": 0.8, "roughness": 0.8, "metallic": 0.0, "specular": 0.5, "tiling": 0.5, "macro": 0.2, "normal": 0.9, "detail": [0.9, 1.04], "macroScale": 0.05},
	"skin": {"dust": 0.0, "grime": 0.0, "minLuminance": 0.13, "maxLuminance": 0.46, "saturation": 1.0, "roughness": 0.66, "metallic": 0.0, "specular": 0.45, "tiling": 6.0, "macro": 0.1, "normal": 0.45, "detail": [0.95, 1.03], "macroScale": 0.3},
	"glazed": {"dust": 0.06, "grime": 0.12, "minLuminance": 0.13, "maxLuminance": 0.30, "saturation": 0.42, "roughness": 0.22, "metallic": 0.0, "specular": 0.9, "tiling": 2.0, "macro": 0.12, "normal": 0.4, "detail": [0.94, 1.04], "macroScale": 0.08},
	"glass": {"dust": 0.02, "grime": 0.06, "minLuminance": 0.1, "maxLuminance": 0.55, "saturation": 1.0, "roughness": 0.1, "metallic": 0.0, "specular": 0.95, "tiling": 1.0, "macro": 0.05, "normal": 0.2, "detail": [0.97, 1.02], "macroScale": 0.05},
	"water": {"dust": 0.0, "grime": 0.0, "minLuminance": 0.09, "maxLuminance": 0.3, "saturation": 0.95, "roughness": 0.12, "metallic": 0.1, "specular": 0.9, "tiling": 0.35, "macro": 0.2, "normal": 1.3, "detail": [0.94, 1.05], "macroScale": 0.03},
	"cloth": {"dust": 0.06, "grime": 0.08, "minLuminance": 0.11, "maxLuminance": 0.28, "saturation": 0.85, "roughness": 0.9, "metallic": 0.0, "specular": 0.24, "tiling": 4.5, "macro": 0.14, "normal": 0.75, "detail": [0.9, 1.05], "macroScale": 0.2},
	"camo": {"dust": 0.05, "grime": 0.08, "minLuminance": 0.1, "maxLuminance": 0.24, "saturation": 0.85, "roughness": 0.9, "metallic": 0.0, "specular": 0.25, "tiling": 3.0, "macro": 0.2, "normal": 0.8, "detail": [0.86, 1.06], "macroScale": 0.12},
	"polymer": {"dust": 0.05, "grime": 0.06, "minLuminance": 0.11, "maxLuminance": 0.24, "saturation": 0.85, "roughness": 0.6, "metallic": 0.0, "specular": 0.45, "tiling": 3.4, "macro": 0.16, "normal": 0.5, "detail": [0.93, 1.04], "macroScale": 0.15},
	"rubber": {"dust": 0.08, "grime": 0.1, "minLuminance": 0.09, "maxLuminance": 0.2, "saturation": 0.8, "roughness": 0.95, "metallic": 0.0, "specular": 0.2, "tiling": 2.2, "macro": 0.18, "normal": 0.7, "detail": [0.88, 1.05], "macroScale": 0.12},
	"gun_metal": {"dust": 0.06, "grime": 0.1, "minLuminance": 0.16, "maxLuminance": 0.3, "saturation": 0.8, "roughness": 0.36, "metallic": 0.8, "specular": 0.7, "tiling": 2.6, "macro": 0.18, "normal": 0.45, "detail": [0.92, 1.04], "macroScale": 0.15},
	"painted_metal": {"dust": 0.12, "grime": 0.16, "minLuminance": 0.14, "maxLuminance": 0.26, "saturation": 0.5, "roughness": 0.5, "metallic": 0.25, "specular": 0.6, "tiling": 1.2, "macro": 0.24, "normal": 0.5, "detail": [0.92, 1.04], "macroScale": 0.06},
	"metal": {"dust": 0.1, "grime": 0.14, "minLuminance": 0.15, "maxLuminance": 0.4, "saturation": 0.7, "roughness": 0.4, "metallic": 0.85, "specular": 0.65, "tiling": 1.4, "macro": 0.2, "normal": 0.5, "detail": [0.9, 1.04], "macroScale": 0.06},
	"rust": {"dust": 0.16, "grime": 0.26, "minLuminance": 0.12, "maxLuminance": 0.3, "saturation": 0.75, "roughness": 0.82, "metallic": 0.5, "specular": 0.4, "tiling": 1.6, "macro": 0.34, "normal": 0.85, "detail": [0.82, 1.06], "macroScale": 0.08},
	"vehicle": {"dust": 0.1, "grime": 0.12, "minLuminance": 0.12, "maxLuminance": 0.28, "saturation": 0.55, "roughness": 0.32, "metallic": 0.6, "specular": 0.75, "tiling": 1.0, "macro": 0.2, "normal": 0.35, "detail": [0.94, 1.03], "macroScale": 0.05},
	"asphalt": {"dust": 0.14, "grime": 0.16, "minLuminance": 0.09, "maxLuminance": 0.2, "saturation": 0.85, "roughness": 0.88, "metallic": 0.0, "specular": 0.3, "tiling": 0.9, "macro": 0.26, "normal": 0.8, "detail": [0.86, 1.05], "macroScale": 0.05},
	"tile": {"dust": 0.1, "grime": 0.14, "minLuminance": 0.11, "maxLuminance": 0.38, "saturation": 0.88, "roughness": 0.35, "metallic": 0.0, "specular": 0.7, "tiling": 1.6, "macro": 0.18, "normal": 0.55, "detail": [0.92, 1.04], "macroScale": 0.07},
	"generic": {"dust": 0.12, "grime": 0.16, "minLuminance": 0.11, "maxLuminance": 0.34, "saturation": 0.85, "roughness": 0.78, "metallic": 0.0, "specular": 0.45, "tiling": 0.9, "macro": 0.2, "normal": 0.6, "detail": [0.9, 1.04], "macroScale": 0.05},
}

## Node-name keywords, longest first so "painted" wins over "metal".
const NAME_PROFILES := [
	["painted", "painted_metal"],
	["radar", "metal"],
	["crane", "painted_metal"],
	["barrier", "painted_metal"],
	["water_tower", "metal"],
	["tower", "metal"],
	["mosque", "plaster"],
	["building", "plaster"],
	["bunker", "concrete"],
	["concrete", "concrete"],
	["desert", "sand"],
	["forest", "grass"],
	["urban", "concrete"],
	["pier", "wood"],
	["dock", "concrete"],
	["crate", "wood"],
	["cargo", "painted_metal"],
	["container", "painted_metal"],
	["stall", "fabric"],
	["awning", "fabric"],
	["canvas", "fabric"],
	["car", "vehicle"],
	["truck", "vehicle"],
	["terrain", "sand"],
	["ground", "dirt"],
	["sand", "sand"],
	["trees", "foliage"],
	["tree", "foliage"],
	["leaves", "foliage"],
	["grass", "grass"],
	["bush", "foliage"],
	["water", "water"],
	["glass", "glass"],
	["window", "glass"],
	["rock", "stone"],
	["stone", "stone"],
]

static var _variants: Dictionary = {}

static func color_from_array(values: Array, fallback: Color = Color.WHITE) -> Color:
	if values.size() < 3:
		return fallback
	return Color(float(values[0]), float(values[1]), float(values[2]), 1.0)

static func _rgb(values: Variant, fallback: Color) -> Vector3:
	var color := color_from_array(values as Array, fallback) if values is Array else fallback
	return Vector3(color.r, color.g, color.b)

static func profile_for(node_name: String, base: Color) -> String:
	var lowered := node_name.to_lower()
	# The forest arena tints its terrain green through the material rather than
	# the node name, so the tone has to win over the generic "terrain" keyword.
	if lowered.contains("terrain") and base.g > base.r * 1.5 and base.g > base.b * 1.5 and base.g > 0.08:
		return "grass"
	# Likewise the mosque's dome is glazed tile while the mosque walls are
	# plaster; the strongly blue material must beat the "mosque" keyword.
	if base.b > base.r * 2.0 and base.b > base.g * 1.5:
		return "glazed"
	for entry: Array in NAME_PROFILES:
		if lowered.contains(entry[0]):
			return entry[1]
	return "generic"

static func _shader_variant(flags: int) -> Shader:
	var level := QUALITY.current()
	var key := "%s_%d" % [level, flags]
	if _variants.has(key):
		return _variants[key]
	# The quality system owns the render-mode flags and the QUALITY_* block
	# stripping, so the tier decides how much work the fragment shader does.
	var shader := Shader.new()
	shader.code = QUALITY.shader_code(level, flags)
	_variants[key] = shader
	return shader

## Drops cached shader variants so the next material picks up a new tier.
static func clear_variants() -> void:
	_variants.clear()

## `record.surface` names a profile explicitly; `node_name` is the fallback hint
## used by map geometry, where one material is shared by many differently named
## nodes.
static func create_material(record: Dictionary, _environment: Dictionary = {}, node_name: String = "") -> ShaderMaterial:
	if bool(record.get("outline", false)):
		# Exported outline hulls are the cartoon look. Callers skip these nodes
		# outright; this is the safety net for any that still reach material
		# creation, so a stray hull can never draw.
		var hidden := ShaderMaterial.new()
		var hidden_code := UNLIT.code.replace("render_mode unshaded, cull_back, shadows_disabled;", "render_mode unshaded, cull_back, shadows_disabled, depth_draw_never;")
		hidden.shader = Shader.new()
		hidden.shader.code = hidden_code.replace("// TRANSPARENT_ALPHA", "ALPHA = 0.0;")
		hidden.set_shader_parameter("color", Vector3.ZERO)
		hidden.set_shader_parameter("energy", 0.0)
		hidden.set_shader_parameter("opacity", 0.0)
		hidden.render_priority = -2
		return hidden
	var quality := QUALITY.preset()
	var base := color_from_array(record.get("color", []), DEFAULT_COLOR)
	var spec_name := str(record.get("surface", ""))
	if spec_name.is_empty() or not PROFILES.has(spec_name):
		spec_name = profile_for(node_name, base)
	var profile: Dictionary = PROFILES[spec_name]
	var flags := 0
	if bool(record.get("doubleSide", false)):
		flags |= 1
	if not bool(record.get("depthTest", true)):
		flags |= 2
	if not bool(record.get("depthWrite", true)):
		flags |= 4
	if bool(record.get("additive", false)):
		flags |= 8
	var opacity := float(record.get("opacity", 1.0))
	if bool(record.get("transparent", false)):
		flags |= 16
	var material := ShaderMaterial.new()
	material.shader = _shader_variant(flags)
	material.set_shader_parameter("albedo_color", Vector3(base.r, base.g, base.b))
	material.set_shader_parameter("albedo_saturation", float(record.get("albedoSaturation", profile.saturation)))
	material.set_shader_parameter("min_luminance", float(record.get("minLuminance", profile.minLuminance)))
	material.set_shader_parameter("max_luminance", float(record.get("maxLuminance", profile.maxLuminance)))
	material.set_shader_parameter("dust_strength", float(record.get("dust", profile.dust)))
	material.set_shader_parameter("grime_strength", float(record.get("grime", profile.grime)))
	material.set_shader_parameter("roughness_value", float(record.get("roughness", profile.roughness)))
	material.set_shader_parameter("metallic_value", float(record.get("metallic", profile.metallic)))
	material.set_shader_parameter("specular_value", float(record.get("specular", profile.specular)))
	material.set_shader_parameter("texture_scale", float(record.get("textureScale", profile.tiling)))
	material.set_shader_parameter("macro_strength", float(record.get("macroStrength", profile.macro)))
	material.set_shader_parameter("macro_scale", float(record.get("macroScale", profile.macroScale)))
	material.set_shader_parameter("normal_strength", float(record.get("normalStrength", profile.normal)) * float(quality.normal_strength))
	material.set_shader_parameter("detail_contrast", float(quality.contrast))
	var detail: Array = record.get("detail", profile.detail)
	material.set_shader_parameter("detail_min", float(detail[0]))
	material.set_shader_parameter("detail_max", float(detail[1]))
	material.set_shader_parameter("emissive_color", _rgb(record.get("emissive", [0, 0, 0]), Color.BLACK))
	var emissive: Variant = record.get("emissive", [0, 0, 0])
	material.set_shader_parameter("emissive_energy", float(record.get("emissiveEnergy", 0.0 if emissive == [0, 0, 0] else 0.7)))
	material.set_shader_parameter("alpha_value", opacity)
	material.set_shader_parameter("wind_strength", float(record.get("windStrength", 0.0)))
	material.set_shader_parameter("wind_time", 0.0)
	var texture_size := int(quality.textures)
	material.set_shader_parameter("detail_noise", LIBRARY.detail_noise(texture_size))
	material.set_shader_parameter("detail_normal", LIBRARY.detail_normal(texture_size))
	material.set_shader_parameter("macro_noise", LIBRARY.macro_noise(texture_size))
	material.set_shader_parameter("surface_profile", spec_name)
	return material

## Flat emissive material for VFX, tracers, decals and lamps. `energy` above one
## pushes the surface into the environment's glow pass.
static func create_unlit(color: Color, energy: float = 1.0, opacity: float = 1.0, additive: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var code := UNLIT.code
	if additive:
		code = code.replace("render_mode unshaded,", "render_mode unshaded, blend_add,")
	code = code.replace("// TRANSPARENT_ALPHA", "ALPHA = opacity;" if opacity < 1.0 else "")
	material.shader = Shader.new()
	material.shader.code = code
	material.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	material.set_shader_parameter("energy", energy)
	material.set_shader_parameter("opacity", opacity)
	return material

## Unlit but non-emissive flat colour: bullet holes, impact dust and smoke. These
## should read as dark or grey surfaces, not as light sources.
static func create_flat(color: Color, opacity: float = 1.0, additive: bool = false) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	var code := UNLIT.code
	if additive:
		code = code.replace("render_mode unshaded,", "render_mode unshaded, blend_add,")
	code = code.replace("// TRANSPARENT_ALPHA", "ALPHA = opacity;" if opacity < 1.0 else "")
	material.shader = Shader.new()
	material.shader.code = code
	material.set_shader_parameter("color", Vector3(color.r, color.g, color.b))
	material.set_shader_parameter("energy", 0.0)
	material.set_shader_parameter("albedo_weight", 1.0)
	material.set_shader_parameter("opacity", opacity)
	return material

## Retints a material produced by create_material without disturbing its surface
## response. Used for team colours, weapon camos and objective ownership.
static func retint(material: ShaderMaterial, color: Color) -> void:
	material.set_shader_parameter("albedo_color", Vector3(color.r, color.g, color.b))

static func surface_profile(material: ShaderMaterial) -> String:
	if material == null or material.shader != SURFACE:
		return ""
	return str(material.get_shader_parameter("surface_profile"))
