class_name SurfaceLibrary
extends RefCounted
## Procedural detail textures shared by every realistic material.
##
## Textures are generated once on first use. Detail noise is tiled many times per
## metre so its contrast carries the fine grain; the macro map is tiled once per
## tens of metres and carries large-scale weathering. Both are raw grayscale
## fields: each surface profile maps them into the range it wants, so one pair of
## textures serves sand, plaster, concrete and foliage without duplication.

const NORMAL_STRENGTH := 7.0

static var _detail: Dictionary = {}
static var _normal: Dictionary = {}
static var _macro: Dictionary = {}

static func _noise_image(frequency: float, octaves: int, size: int, lacunarity: float = 2.0) -> Image:
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = frequency
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = octaves
	noise.fractal_lacunarity = lacunarity
	noise.fractal_gain = 0.5
	var image := noise.get_seamless_image(size, size) as Image
	if image.get_format() != Image.FORMAT_RGB8:
		image.convert(Image.FORMAT_RGB8)
	return image

static func _texture(image: Image) -> ImageTexture:
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

static func detail_noise(size: int = 256) -> Texture2D:
	if not _detail.has(size):
		_detail[size] = _texture(_noise_image(0.014, 4, size))
	return _detail[size]

static func detail_normal(size: int = 256) -> Texture2D:
	if not _normal.has(size):
		var image := _noise_image(0.022, 4, size)
		image.bump_map_to_normal_map(NORMAL_STRENGTH)
		_normal[size] = _texture(image)
	return _normal[size]

static func macro_noise(size: int = 256) -> Texture2D:
	if not _macro.has(size):
		_macro[size] = _texture(_noise_image(0.004, 5, size, 2.4))
	return _macro[size]

static func release() -> void:
	_detail.clear()
	_normal.clear()
	_macro.clear()
