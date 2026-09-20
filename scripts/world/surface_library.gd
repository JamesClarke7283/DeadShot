class_name SurfaceLibrary
extends RefCounted
## Procedural detail maps shared by every realistic material.
##
## One pair of greyscale fields served every surface family before this file:
## sand, plaster, blued steel and tree bark all carried the same noise, so once
## the lighting was good enough to resolve it the maps read as generic grain
## rather than as materials. Each family now gets its own height field, built
## from that family's actual structure:
##
##   sand      wind ripples          concrete   aggregate in cement
##   asphalt   graded aggregate      stone      chiselled blocks and mortar
##   wood      growth rings + pores  fabric     plain warp/weft weave
##   foliage   leaf lobes            rust       pitted, flaking steel
##   metal     fine isotropic brush  plaster    trowel sweeps
##
## The height field is authored once and everything else derives from it: the
## normal map is the field converted to tangent space, and the parallax march
## reads the field directly. That is what keeps displacement and shading
## consistent instead of merely correlated.
##
## Cost control. Three things keep generation off the frame budget:
##   * a shared seamless-noise bank per resolution, so the expensive synthesis
##     runs four times instead of once per family per octave;
##   * the family is resolved to an integer `kind` once, outside the pixel loop
##     — matching on the family *string* per pixel was the dominant cost of the
##     first formulation, which took 24 s at 1024²;
##   * fields are cached per (family, resolution) and generated on first use, so
##     a match pays only for the families it places, and `_resolution` caps the
##     work at the point the extra texels stop being resolvable.

const NORMAL_STRENGTH := 4.0

## Shared seamless noise fields, keyed "<tag>_<size>". Sampling one bank across
## families is what keeps synthesis cost independent of family count.
const BANK_FREQUENCIES := {"coarse": 0.018, "mid": 0.055, "fine": 0.14, "micro": 0.32}

## Family -> integer kind, resolved before the pixel loop.
const KINDS := {
	"sand": 1, "dirt": 2, "grass": 2, "concrete": 3, "asphalt": 4, "stone": 5,
	"tile": 6, "plaster": 7, "wood": 8, "fabric": 9, "cloth": 9, "camo": 9,
	"foliage": 10, "rust": 11,
	"gun_metal": 12, "metal": 12, "painted_metal": 12, "vehicle": 12,
	"polymer": 12, "glazed": 12, "glass": 12,
	"rubber": 13, "snow": 14, "skin": 15, "water": 16,
}

static var _bank: Dictionary = {}
static var _height_cache: Dictionary = {}
static var _grain_cache: Dictionary = {}
static var _normal_cache: Dictionary = {}
static var _macro_cache: Dictionary = {}
static var _cloud_cache: Dictionary = {}
static var _albedo_cache: Dictionary = {}

static func _resolution(size: int) -> int:
	# 256 texels over the metre-scale tiles these profiles use is already several
	# texels per centimetre, and the maps tile many times per metre, so the extra
	# octaves above it cost time without adding resolvable detail.
	return clampi(size, 64, 256)

static func _bank_field(tag: String, size: int) -> PackedByteArray:
	var key := "%s_%d" % [tag, size]
	if not _bank.has(key):
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = float(BANK_FREQUENCIES[tag])
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 4 if tag != "micro" else 3
		noise.fractal_lacunarity = 2.0
		noise.fractal_gain = 0.5
		var image := noise.get_seamless_image(size, size) as Image
		image.convert(Image.FORMAT_RGB8)
		_bank[key] = image.get_data()
	return _bank[key]

## One fused pass building a family's height field. `kind` dispatches with
## integer comparisons, and every term that does not vary per pixel is hoisted.
static func _height_bytes(family: String, size: int) -> PackedByteArray:
	var kind := int(KINDS.get(family, 0))
	var coarse := _bank_field("coarse", size)
	var mid := _bank_field("mid", size)
	var fine := _bank_field("fine", size)
	var micro := _bank_field("micro", size)
	var output := PackedByteArray()
	output.resize(size * size * 3)
	var tau := TAU
	var scale := 1.0 / float(size)
	var index := 0
	for y in range(size):
		var v := float(y) * scale
		# Terms that depend only on the row.
		var v_rings := v * 13.0 * tau
		var v_row := v * 9.0
		var v_blocks := absf(fposmod(v * 3.0, 1.0) - 0.5) * 2.0
		var v_tiles := absf(fposmod(v * 6.0, 1.0) - 0.5) * 2.0
		var v_weft := sin(v * 128.0) * 0.5 + 0.5
		var v_pore := sin(v * 9.0)
		for x in range(size):
			var u := float(x) * scale
			var c := float(coarse[index]) * (1.0 / 255.0)
			var m := float(mid[index]) * (1.0 / 255.0)
			var f := float(fine[index]) * (1.0 / 255.0)
			var z := float(micro[index]) * (1.0 / 255.0)
			var value := c * 0.5 + m * 0.28 + f * 0.22
			if kind == 1:
				# Long low ridges one way, broken by drift so they do not read as
				# a printed stripe.
				value = 0.5 + sin((u * 9.0 + sin(v * 3.0 + c * 2.0) * 0.6) * tau) * 0.16 + (c - 0.5) * 0.22 + (m - 0.5) * 0.18
			elif kind == 2:
				value = c * 0.62 + m * 0.24 + f * 0.14
			elif kind == 3:
				# Cement matrix with discrete aggregate proud of it.
				var stones := sin(u * 47.0 + v * 11.0) * sin(v * 41.0 - u * 7.0) + sin(u * 23.0 + v * 31.0) * 0.7
				value = c * 0.4 + m * 0.2 + (0.5 + stones * 0.22) * 0.4
			elif kind == 4:
				var chips := sin(u * 71.0 + v * 13.0) * sin(v * 67.0 - u * 11.0) + sin(u * 37.0 - v * 43.0) * 0.6
				value = c * 0.34 + (0.5 + chips * 0.3) * 0.5 + m * 0.16
			elif kind == 5:
				# Blocks with chiselled faces and eroded mortar between them.
				var ux := absf(fposmod(u * 4.0, 1.0) - 0.5) * 2.0
				var seam := minf(smoothstep(0.86, 1.0, ux), smoothstep(0.84, 1.0, v_blocks))
				value = 0.34 + seam * 0.3 + c * 0.2 + m * 0.16
			elif kind == 6:
				var tx := absf(fposmod(u * 6.0, 1.0) - 0.5) * 2.0
				value = lerpf(0.35, 0.9, smoothstep(0.88, 1.0, minf(tx, v_tiles))) * 0.85 + m * 0.15
			elif kind == 7:
				value = c * 0.55 + m * 0.3 + f * 0.15
			elif kind == 8:
				# Growth rings across one axis; pores as short dashes following the
				# grain, which is what separates timber from rock.
				var ring := sin(v_rings + sin(u * 1.6 + c * 1.5) * 0.5 * tau) * 0.5 + 0.5
				var pore := sin(u * 118.0) * v_pore * 0.5 + 0.5
				value = (0.45 + ring * 0.32) * 0.7 + c * 0.1 + (pore * 0.7 + z * 0.3) * 0.2
			elif kind == 9:
				# Plain weave: alternating warp and weft, plus fibre fuzz.
				var warp := sin(u * 128.0) * 0.5 + 0.5
				var over := sin(u * 6.0) * sin(v * 6.0)
				value = (0.36 + (warp if over > 0.0 else v_weft) * 0.28) * 0.78 + f * 0.14 + z * 0.08
			elif kind == 10:
				var lobe := sin(u * 5.0 + sin(v * 7.0) * 1.2) * sin(v * 6.0 - sin(u * 5.0) * 1.1)
				value = c * 0.4 + (0.5 + lobe * 0.3) * 0.44 + m * 0.16
			elif kind == 11:
				# Laminar flakes over deep pits.
				var pit := sin(u * 97.0 + v * 53.0) * sin(v * 89.0 - u * 59.0)
				value = c * 0.42 + m * 0.18 + (0.5 + pit * 0.42) * 0.4
			elif kind == 12:
				# Machined surfaces: near-flat with a fine isotropic brush, so the
				# highlight stays tight instead of shattering.
				value = 0.5 + sin(u * 220.0 + sin(v * 3.0) * 0.4) * 0.06 + (m - 0.5) * 0.1 + (f - 0.5) * 0.06
			elif kind == 13:
				value = m * 0.6 + f * 0.25 + z * 0.15
			elif kind == 14:
				value = c * 0.62 + m * 0.22 + z * 0.16
			elif kind == 15:
				# Pores and fine creases; shallow so faces do not read as bark.
				value = 0.5 + sin(u * 180.0) * sin(v * 172.0) * 0.07 + (m - 0.5) * 0.14 + (f - 0.5) * 0.1
			elif kind == 16:
				value = 0.5 + sin(u * 12.0 + sin(v * 9.0 + c * 3.0)) * 0.2 + (c - 0.5) * 0.3
			var byte := int(clampf(value, 0.0, 1.0) * 255.0)
			output[index] = byte
			output[index + 1] = byte
			output[index + 2] = byte
			index += 3
	return output

static func _image_from_bytes(size: int, bytes: PackedByteArray) -> Image:
	return Image.create_from_data(size, size, false, Image.FORMAT_RGB8, bytes)

static func _texture(image: Image) -> ImageTexture:
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

## The raw height field, shared by the displacement march and the normal map.
static func detail_height(size: int = 256, family: String = "generic") -> Image:
	var resolved := _resolution(size)
	var key := "%s_%d" % [family, resolved]
	if not _height_cache.has(key):
		_height_cache[key] = _image_from_bytes(resolved, _height_bytes(family, resolved))
	return _height_cache[key]

## Fine grain. Every band samples this.
static func detail_noise(size: int = 256, family: String = "generic") -> Texture2D:
	var resolved := _resolution(size)
	var key := "%s_%d" % [family, resolved]
	if not _grain_cache.has(key):
		var height := detail_height(resolved, family)
		# The grain map is the height field itself; the surface profile's
		# `detail_min`/`detail_max` range maps it into an albedo multiplier.
		_grain_cache[key] = _texture(height.duplicate())
	return _grain_cache[key]

static func detail_normal(size: int = 256, family: String = "generic") -> Texture2D:
	var resolved := _resolution(size)
	var key := "%s_%d" % [family, resolved]
	if not _normal_cache.has(key):
		var image := detail_height(resolved, family).duplicate() as Image
		image.bump_map_to_normal_map(NORMAL_STRENGTH)
		_normal_cache[key] = _texture(image)
	return _normal_cache[key]

## Macro weathering: run-off staining and sun bleaching over tens of metres.
## Phase-shifted per family so neighbouring surfaces do not stain identically.
static func macro_noise(size: int = 256, family: String = "generic") -> Texture2D:
	var resolved := _resolution(size)
	var key := "%s_%d" % [family, resolved]
	if not _macro_cache.has(key):
		var phase := float(posmod(family.hash(), 1024)) / 1024.0
		var noise := FastNoiseLite.new()
		noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		noise.frequency = 0.004
		noise.fractal_type = FastNoiseLite.FRACTAL_FBM
		noise.fractal_octaves = 5
		noise.fractal_lacunarity = 2.4
		noise.fractal_gain = 0.5
		noise.offset = Vector3(phase * 64.0, phase * 37.0, 0.0)
		var base := noise.get_seamless_image(resolved, resolved) as Image
		base.convert(Image.FORMAT_RGB8)
		# A second field, squashed across one axis, reads as vertical run-off
		# drips rather than as blobs — what makes grime streak down a wall.
		var streak := noise.get_seamless_image(resolved, 16) as Image
		streak.convert(Image.FORMAT_RGB8)
		streak.resize(resolved, resolved, Image.INTERPOLATE_BILINEAR)
		var base_bytes := base.get_data()
		var streak_bytes := streak.get_data()
		var output := PackedByteArray()
		output.resize(resolved * resolved * 3)
		var index := 0
		for pixel in range(resolved * resolved):
			var byte := int(clampf(float(base_bytes[index]) * 0.72 + float(streak_bytes[index]) * 0.28, 0.0, 255.0))
			output[index] = byte
			output[index + 1] = byte
			output[index + 2] = byte
			index += 3
		_macro_cache[key] = _texture(_image_from_bytes(resolved, output))
	return _macro_cache[key]

## Seamless cloud cover for the sky. The sky shader is evaluated per texel of the
## radiance cubemap rather than per screen pixel, so a procedural deck built from
## value-noise hashes (16 transcendental ops per texel) dominated the frame cost.
## Baking the same field into a texture turns that into a handful of fetches.
##
## Two channels carry two scales: `r` is the large soft mass, `g` a finer broken
## layer multiplied into it. That is enough structure for a deck seen through
## kilometres of haze, which is all a sky dome can resolve anyway.
static func cloud_cover(size: int = 256) -> Texture2D:
	var resolved := clampi(size, 64, 512)
	var key := "clouds_%d" % resolved
	if not _cloud_cache.has(key):
		var mass := FastNoiseLite.new()
		mass.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		mass.frequency = 0.010
		mass.fractal_type = FastNoiseLite.FRACTAL_FBM
		mass.fractal_octaves = 5
		mass.fractal_lacunarity = 2.3
		mass.fractal_gain = 0.55
		var break_up := FastNoiseLite.new()
		break_up.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		break_up.frequency = 0.038
		break_up.fractal_type = FastNoiseLite.FRACTAL_FBM
		break_up.fractal_octaves = 4
		break_up.fractal_lacunarity = 2.0
		var mass_image := mass.get_seamless_image(resolved, resolved) as Image
		mass_image.convert(Image.FORMAT_RGB8)
		var break_image := break_up.get_seamless_image(resolved, resolved) as Image
		break_image.convert(Image.FORMAT_RGB8)
		var mass_bytes := mass_image.get_data()
		var break_bytes := break_image.get_data()
		var output := PackedByteArray()
		output.resize(resolved * resolved * 3)
		var index := 0
		for pixel in range(resolved * resolved):
			var base := float(mass_bytes[index])
			# The finer layer is multiplied in, so it breaks the mass's edges
			# rather than replacing them.
			var detail := float(break_bytes[index]) / 255.0
			var blended := clampf(base * (0.72 + detail * 0.56), 0.0, 255.0)
			var byte := int(blended)
			output[index] = byte
			output[index + 1] = base * 0.5 + blended * 0.5
			output[index + 2] = 255
			index += 3
		var image := Image.create_from_data(resolved, resolved, false, Image.FORMAT_RGB8, output)
		_cloud_cache[key] = _texture(image)
	return _cloud_cache[key]

## Albedo variation: two decorrelated low-frequency fields plus a patch mask, for
## surfaces that must not read as one painted hue. Cheaper than the height field
## and generated lazily like the rest.
static func albedo_variation(size: int = 256, family: String = "generic") -> Texture2D:
	var resolved := _resolution(size)
	var key := "%s_%d" % [family, resolved]
	if not _albedo_cache.has(key):
		var phase := float(posmod(family.hash(), 512)) / 512.0
		var tint := FastNoiseLite.new()
		tint.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		tint.frequency = 0.016
		tint.fractal_type = FastNoiseLite.FRACTAL_FBM
		tint.fractal_octaves = 3
		tint.offset = Vector3(phase * 40.0, phase * 17.0, 0.0)
		var patch := FastNoiseLite.new()
		patch.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		patch.frequency = 0.045
		patch.fractal_type = FastNoiseLite.FRACTAL_FBM
		patch.fractal_octaves = 2
		patch.offset = Vector3(phase * 91.0, phase * 53.0, 0.0)
		var tint_image := tint.get_seamless_image(resolved, resolved) as Image
		tint_image.convert(Image.FORMAT_RGB8)
		var patch_image := patch.get_seamless_image(resolved, resolved) as Image
		patch_image.convert(Image.FORMAT_RGB8)
		var tint_bytes := tint_image.get_data()
		var patch_bytes := patch_image.get_data()
		var output := PackedByteArray()
		output.resize(resolved * resolved * 3)
		var index := 0
		for pixel in range(resolved * resolved):
			# Two fields at the same scale but decorrelated phases; the shader can
			# then combine them without the result looking like one noise band.
			output[index] = tint_bytes[index]
			output[index + 1] = tint_bytes[index + 1]
			output[index + 2] = patch_bytes[index]
			index += 3
		_albedo_cache[key] = _texture(_image_from_bytes(resolved, output))
	return _albedo_cache[key]

static func release() -> void:
	_bank.clear()
	_height_cache.clear()
	_grain_cache.clear()
	_normal_cache.clear()
	_macro_cache.clear()
	_cloud_cache.clear()
	_albedo_cache.clear()
