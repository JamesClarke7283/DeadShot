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
	"fabric": {"dust": 0.08, "grime": 0.1, "minLuminance": 0.13, "maxLuminance": 0.44, "saturation": 0.95, "roughness": 0.94, "metallic": 0.0, "specular": 0.2, "tiling": 2.4, "macro": 0.16, "normal": 0.9, "detail": [0.9, 1.05], "macroScale": 0.09},
	"stone": {"dust": 0.14, "grime": 0.22, "minLuminance": 0.1, "maxLuminance": 0.4, "saturation": 0.95, "roughness": 0.88, "metallic": 0.0, "specular": 0.35, "tiling": 0.8, "macro": 0.28, "normal": 0.85, "detail": [0.84, 1.06], "macroScale": 0.06},
	"foliage": {"dust": 0.1, "grime": 0.05, "minLuminance": 0.13, "maxLuminance": 0.26, "saturation": 0.34, "roughness": 0.88, "metallic": 0.0, "specular": 0.3, "tiling": 1.8, "macro": 0.2, "normal": 1.0, "detail": [0.78, 1.1], "macroScale": 0.07},
	"grass": {"dust": 0.08, "grime": 0.04, "minLuminance": 0.14, "maxLuminance": 0.28, "saturation": 0.32, "roughness": 0.92, "metallic": 0.0, "specular": 0.28, "tiling": 3.2, "macro": 0.24, "normal": 1.1, "detail": [0.76, 1.12], "macroScale": 0.09},
	"snow": {"dust": 0.05, "grime": 0.03, "minLuminance": 0.3, "maxLuminance": 0.72, "saturation": 0.8, "roughness": 0.8, "metallic": 0.0, "specular": 0.5, "tiling": 0.5, "macro": 0.2, "normal": 0.9, "detail": [0.9, 1.04], "macroScale": 0.05},
	"skin": {"dust": 0.0, "grime": 0.0, "minLuminance": 0.13, "maxLuminance": 0.46, "saturation": 1.0, "roughness": 0.66, "metallic": 0.0, "specular": 0.45, "tiling": 6.0, "macro": 0.1, "normal": 0.45, "detail": [0.95, 1.03], "macroScale": 0.3},
	"glazed": {"dust": 0.06, "grime": 0.12, "minLuminance": 0.13, "maxLuminance": 0.30, "saturation": 0.42, "roughness": 0.22, "metallic": 0.0, "specular": 0.9, "tiling": 2.0, "macro": 0.12, "normal": 0.4, "detail": [0.94, 1.04], "macroScale": 0.08},
	"glass": {"dust": 0.02, "grime": 0.06, "minLuminance": 0.1, "maxLuminance": 0.55, "saturation": 1.0, "roughness": 0.1, "metallic": 0.0, "specular": 0.95, "tiling": 1.0, "macro": 0.05, "normal": 0.2, "detail": [0.97, 1.02], "macroScale": 0.05},
	"water": {"dust": 0.0, "grime": 0.0, "minLuminance": 0.09, "maxLuminance": 0.3, "saturation": 0.95, "roughness": 0.12, "metallic": 0.1, "specular": 0.9, "tiling": 0.35, "macro": 0.2, "normal": 1.3, "detail": [0.94, 1.05], "macroScale": 0.03},
	"cloth": {"dust": 0.06, "grime": 0.08, "minLuminance": 0.16, "maxLuminance": 0.40, "saturation": 0.85, "roughness": 0.9, "metallic": 0.0, "specular": 0.24, "tiling": 4.5, "macro": 0.14, "normal": 0.75, "detail": [0.9, 1.05], "macroScale": 0.2},
	"camo": {"dust": 0.05, "grime": 0.08, "minLuminance": 0.15, "maxLuminance": 0.36, "saturation": 0.85, "roughness": 0.9, "metallic": 0.0, "specular": 0.25, "tiling": 3.0, "macro": 0.2, "normal": 0.8, "detail": [0.86, 1.06], "macroScale": 0.12},
	"polymer": {"dust": 0.05, "grime": 0.06, "minLuminance": 0.12, "maxLuminance": 0.29, "saturation": 0.85, "roughness": 0.6, "metallic": 0.0, "specular": 0.45, "tiling": 3.4, "macro": 0.16, "normal": 0.5, "detail": [0.93, 1.04], "macroScale": 0.15},
	"rubber": {"dust": 0.08, "grime": 0.1, "minLuminance": 0.11, "maxLuminance": 0.27, "saturation": 0.8, "roughness": 0.95, "metallic": 0.0, "specular": 0.2, "tiling": 2.2, "macro": 0.18, "normal": 0.7, "detail": [0.88, 1.05], "macroScale": 0.12},
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

## Parallax occlusion depth in metres per surface family: how deep the grain
## field is carved. Soft, matted surfaces (fabric, cloth, snow) barely displace,
## coarse mineral ones (sand, gravel, stone, rust) displace most. Only used where
## the band compiles the POM block in; the band's `pom_strength` scales it.
const PARALLAX_DEPTH := {
	"sand": 0.030, "dirt": 0.028, "plaster": 0.012, "concrete": 0.020,
	"wood": 0.026, "fabric": 0.008, "stone": 0.030, "foliage": 0.020,
	"grass": 0.022, "snow": 0.010, "skin": 0.003, "glazed": 0.004,
	"glass": 0.002, "water": 0.010, "cloth": 0.008, "camo": 0.010,
	"polymer": 0.008, "rubber": 0.014, "gun_metal": 0.005,
	"painted_metal": 0.006, "metal": 0.006, "rust": 0.032,
	"vehicle": 0.005, "asphalt": 0.026, "tile": 0.014, "generic": 0.016,
}
const DEFAULT_PARALLAX := 0.014

## Albedo hue variation per family: the two colour casts a family's patches drift
## between, and the amount applied at the low and high ends of the mask. `scale`
## is the world tiling — large enough that several metres of wall span one patch.
## Families whose authored palette must survive (skin, glass, team tints, camo)
## are deliberately absent and get no variation.
const VARIATION := {
	"concrete": {"a": [0.72, 0.70, 0.66], "b": [0.52, 0.52, 0.55], "low": 0.08, "high": 0.30, "scale": 0.22},
	"plaster": {"a": [0.78, 0.73, 0.64], "b": [0.60, 0.57, 0.52], "low": 0.06, "high": 0.26, "scale": 0.20},
	"asphalt": {"a": [0.66, 0.66, 0.68], "b": [0.46, 0.46, 0.50], "low": 0.10, "high": 0.34, "scale": 0.18},
	"sand": {"a": [0.80, 0.72, 0.55], "b": [0.66, 0.59, 0.44], "low": 0.05, "high": 0.22, "scale": 0.16},
	"dirt": {"a": [0.72, 0.66, 0.54], "b": [0.52, 0.47, 0.38], "low": 0.08, "high": 0.30, "scale": 0.22},
	"stone": {"a": [0.74, 0.72, 0.68], "b": [0.56, 0.55, 0.53], "low": 0.08, "high": 0.30, "scale": 0.24},
	"wood": {"a": [0.74, 0.62, 0.44], "b": [0.50, 0.41, 0.29], "low": 0.08, "high": 0.34, "scale": 0.30},
	"rust": {"a": [0.78, 0.52, 0.34], "b": [0.44, 0.36, 0.32], "low": 0.12, "high": 0.44, "scale": 0.20},
	"metal": {"a": [0.70, 0.72, 0.76], "b": [0.54, 0.55, 0.58], "low": 0.04, "high": 0.18, "scale": 0.26},
	"painted_metal": {"a": [0.76, 0.74, 0.70], "b": [0.54, 0.53, 0.50], "low": 0.06, "high": 0.26, "scale": 0.24},
	"vehicle": {"a": [0.74, 0.74, 0.74], "b": [0.56, 0.56, 0.58], "low": 0.04, "high": 0.16, "scale": 0.26},
	"tile": {"a": [0.76, 0.74, 0.70], "b": [0.58, 0.58, 0.58], "low": 0.05, "high": 0.20, "scale": 0.22},
	"grass": {"a": [0.66, 0.74, 0.46], "b": [0.44, 0.54, 0.34], "low": 0.08, "high": 0.32, "scale": 0.18},
	"foliage": {"a": [0.64, 0.74, 0.44], "b": [0.42, 0.52, 0.32], "low": 0.08, "high": 0.30, "scale": 0.20},
	"rubber": {"a": [0.66, 0.66, 0.68], "b": [0.52, 0.52, 0.54], "low": 0.04, "high": 0.16, "scale": 0.26},
	"generic": {"a": [0.74, 0.72, 0.68], "b": [0.56, 0.55, 0.53], "low": 0.05, "high": 0.22, "scale": 0.24},
}

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

## `band` names the quality band explicitly. Threading it in rather than reading
## the global matters: a caller can rebuild the world for a band that is not the
## currently selected one — the tier benchmark does exactly that — and reading
## the global silently produced materials for the wrong band.
static func _shader_variant(flags: int, band: String = "") -> Shader:
	var level := QUALITY.normalize(band) if not band.is_empty() else QUALITY.current()
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
static func create_material(record: Dictionary, _environment: Dictionary = {}, node_name: String = "", band: String = "") -> ShaderMaterial:
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
	var quality := QUALITY.preset(band)
	var base := color_from_array(record.get("color", []), DEFAULT_COLOR)
	var spec_name := str(record.get("surface", ""))
	if spec_name.is_empty() or not PROFILES.has(spec_name):
		spec_name = profile_for(node_name, base)
	var profile: Dictionary = PROFILES[spec_name]
	var flags := 0
	if bool(record.get("doubleSide", false)):
		flags |= 1
	# Foliage and cloth shells are thin sheets: shading them single-sided makes a
	# leaf, canopy or banner disappear from behind. The exported map material does
	# not mark them, so the profile decides.
	if spec_name in ["foliage", "grass", "fabric"]:
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
	material.shader = _shader_variant(flags, band)
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
	# Parallax is scaled by the band's strength, so a band without POM passes
	# zero and the march is skipped even though the block is compiled in.
	material.set_shader_parameter("parallax_depth", float(PARALLAX_DEPTH.get(spec_name, DEFAULT_PARALLAX)) * float(quality.pom_strength))
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
	# Thin organic sheets transmit light; everything else stays opaque. Grass and
	# foliage are the two families where a canopy lit from behind otherwise reads
	# as a dark solid mass.
	if spec_name in ["foliage", "grass"]:
		material.set_shader_parameter("translucency", 0.55)
		material.set_shader_parameter("translucency_color", Vector3(0.42, 0.62, 0.20))
		# Transmission needs the light vector; the fragment stage does not expose
		# the scene's sun, so the map's own direction is supplied here. Converted
		# inline rather than through MapWorld, which preloads this module.
		var source: Array = _environment.get("sunDirection", [0.5, 1.0, 0.35])
		var direction := Vector3(float(source[0]), float(source[1]), float(source[2])).normalized()
		material.set_shader_parameter("sun_direction", direction)
	var texture_size := int(quality.textures)
	# Each surface family gets its own structure (ripples, aggregate, growth
	# rings, weave) rather than one shared noise field, which is what makes a wall
	# resolve as concrete instead of as generic grain. Textures are generated on
	# first use per (family, resolution) and cached, so a match pays only for the
	# families it places.
	material.set_shader_parameter("detail_noise", LIBRARY.detail_noise(texture_size, spec_name))
	material.set_shader_parameter("detail_normal", LIBRARY.detail_normal(texture_size, spec_name))
	material.set_shader_parameter("macro_noise", LIBRARY.macro_noise(texture_size, spec_name))
	material.set_shader_parameter("surface_profile", spec_name)
	# Hue variation. Families without an entry get zero scale, which switches the
	# term off in the shader entirely rather than applying a no-op mix.
	var variation: Dictionary = VARIATION.get(spec_name, {})
	if variation.is_empty():
		material.set_shader_parameter("variation_scale", 0.0)
	else:
		var tint_a: Array = variation.a
		var tint_b: Array = variation.b
		material.set_shader_parameter("variation_tint_a", Vector3(tint_a[0], tint_a[1], tint_a[2]))
		material.set_shader_parameter("variation_tint_b", Vector3(tint_b[0], tint_b[1], tint_b[2]))
		material.set_shader_parameter("variation_range", Vector2(float(variation.low), float(variation.high)))
		material.set_shader_parameter("variation_scale", float(variation.scale))
		material.set_shader_parameter("albedo_variation", LIBRARY.albedo_variation(texture_size, spec_name))
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
