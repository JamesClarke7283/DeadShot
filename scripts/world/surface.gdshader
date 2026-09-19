shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// Realistic world-space surface shading.
//
// Source geometry keeps per-primitive 0..1 UVs, so textures are projected in
// world space rather than through the mesh UVs. `albedo_color` carries the base
// tone (linear, as exported); the noise maps only modulate it:
//   detail -> fine grain        macro -> large-scale weathering / staining
//
// The QUALITY_* markers below are stripped by `graphics_quality.gd` to build the
// per-tier variants. Each block declares everything it needs, so any combination
// of the three features compiles:
//   PLANAR     one world-space projection, no triplanar helpers
//   TRIPLANAR  three projections blended by the geometric normal
//   NORMAL     tangent-space normal-map rebuild (implies triplanar sampling)
//   MACRO      large-scale weathering lookup
// A tier that disables a feature pays neither the samples nor the instructions.

uniform vec3 albedo_color = vec3(0.35);
uniform float albedo_saturation = 1.0;
uniform float min_luminance = 0.06;
uniform float max_luminance = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.8;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float specular_value : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D detail_noise : filter_linear_mipmap_anisotropic, repeat_enable;
// QUALITY_NORMAL_BEGIN
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
// QUALITY_NORMAL_END
// QUALITY_MACRO_BEGIN
uniform sampler2D macro_noise : filter_linear_mipmap_anisotropic, repeat_enable;
// QUALITY_MACRO_END
// Tiles per metre.
uniform float texture_scale = 0.4;
uniform float macro_scale = 0.02;
uniform float detail_min = 0.88;
uniform float detail_max = 1.0;
uniform float macro_strength = 0.3;
uniform float normal_strength = 0.6;
// Surface treatments. Dust settles on upward-facing surfaces and lightens them;
// grime darkens vertical faces and streaks downward under gravity. Both reuse
// the weathering map, so they cost nothing extra on a tier without MACRO.
uniform float dust_strength = 0.0;
uniform float grime_strength = 0.0;
uniform vec3 dust_color = vec3(0.6, 0.55, 0.45);
// Per-tier multiplier on the sampled detail contrast: the low tier flattens the
// grain so cheaper, lower-resolution noise does not shimmer.
uniform float detail_contrast = 1.0;
uniform vec3 emissive_color = vec3(0.0);
uniform float emissive_energy = 0.0;
uniform float alpha_value : hint_range(0.0, 1.0) = 1.0;
uniform float wind_strength = 0.0;
uniform float wind_time = 0.0;

varying vec3 world_position;

// QUALITY_TRIPLANAR_BEGIN
vec3 triplanar_weight(vec3 normal) {
	vec3 weight = pow(abs(normal), vec3(4.0));
	return weight / max(dot(weight, vec3(1.0)), 0.0001);
}

float triplanar_field(sampler2D field, vec2 uvs[3], vec3 weight) {
	return texture(field, uvs[0]).r * weight.x
		+ texture(field, uvs[1]).r * weight.y
		+ texture(field, uvs[2]).r * weight.z;
}

vec2[3] triplanar_uvs(vec3 position) {
	vec3 scaled = position * texture_scale;
	return vec2[3](scaled.zy, scaled.xz, scaled.xy);
}
// QUALITY_TRIPLANAR_END

void vertex() {
	// Source foliage sway, kept in local mesh space so instanced canopies move
	// independently. Godot applies this vertex stage to the shadow pass too.
	float sway = sin(wind_time * 1.6 + MODEL_MATRIX[3].x * 0.7 + MODEL_MATRIX[3].z * 0.5) * wind_strength;
	float height = smoothstep(0.0, 2.0, VERTEX.y);
	VERTEX.x += sway * height;
	VERTEX.z += sway * 0.5 * height;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 geometric = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);

	// Grain. Cheapest tier takes one planar projection; full quality blends three.
	float grain = 0.5;
	// QUALITY_PLANAR_BEGIN
	grain = texture(detail_noise, world_position.xz * texture_scale).r;
	// QUALITY_PLANAR_END
	// QUALITY_TRIPLANAR_BEGIN
	grain = triplanar_field(detail_noise, triplanar_uvs(world_position), triplanar_weight(geometric));
	// QUALITY_TRIPLANAR_END

	// Weathering, independent of the detail projection.
	float weathering = 1.0;
	float dust_amount = 0.0;
	float grime_amount = 0.0;
	// QUALITY_MACRO_BEGIN
	weathering = texture(macro_noise, world_position.xz * macro_scale).r;
	float upward = smoothstep(0.2, 1.0, geometric.y);
	// Stretched vertically so the noise reads as run-off streaks down a wall.
	float streak = texture(macro_noise, vec2(world_position.x * macro_scale * 3.0, world_position.y * macro_scale * 0.15)).r;
	dust_amount = dust_strength * upward * (0.4 + 0.6 * weathering);
	grime_amount = grime_strength * (1.0 - upward) * (1.0 - streak);
	// QUALITY_MACRO_END

	// Shaded normal from the three tangent-space samples; defaults to the
	// geometric normal so the block is optional.
	vec3 shaded_normal = geometric;
	// QUALITY_NORMAL_BEGIN
	vec3 normal_weight = triplanar_weight(geometric);
	vec2 normal_uvs[3] = triplanar_uvs(world_position);
	vec3 sample_x = texture(detail_normal, normal_uvs[0]).xyz * 2.0 - 1.0;
	vec3 sample_y = texture(detail_normal, normal_uvs[1]).xyz * 2.0 - 1.0;
	vec3 sample_z = texture(detail_normal, normal_uvs[2]).xyz * 2.0 - 1.0;
	vec3 normal_x = vec3(sample_x.xy + geometric.zy, abs(sample_x.z) * geometric.x);
	vec3 normal_y = vec3(sample_y.xy + geometric.xz, abs(sample_y.z) * geometric.y);
	vec3 normal_z = vec3(sample_z.xy + geometric.xy, abs(sample_z.z) * geometric.z);
	vec3 bumped = normalize(normal_x.zyx * normal_weight.x + normal_y.xzy * normal_weight.y + normal_z.xyz * normal_weight.z);
	shaded_normal = normalize(mix(geometric, bumped, normal_strength));
	// QUALITY_NORMAL_END
	NORMAL = normalize((VIEW_MATRIX * vec4(shaded_normal, 0.0)).xyz);

	// The exported palettes were authored for an unlit toon look and include both
	// near-black variants of normally light surfaces (a shadowed wall, a dark
	// canopy) and very bright tones that blow out once the sun and ambient add
	// to them. Both ends are pulled into a plausible reflectance range while the
	// hue is preserved: only the brightness scale moves, never the channel ratio.
	vec3 base = albedo_color;
	float energy = dot(base, vec3(0.2126, 0.7152, 0.0722));
	base *= clamp(min_luminance / max(energy, 0.0001), 1.0, max_luminance / max(energy, 0.0001));
	// Toon palettes are authored saturated; the remap above can push that
	// further, so chroma is scaled around the post-remap luminance.
	energy = dot(base, vec3(0.2126, 0.7152, 0.0722));
	base = clamp(mix(vec3(energy), base, albedo_saturation), vec3(0.0), vec3(1.0));

	float detail = mix(detail_min, detail_max, mix(0.5, grain, detail_contrast));
	base *= detail * (1.0 - macro_strength * (1.0 - weathering));
	// Grime first (it darkens and settles), then dust over the top of it.
	base = mix(base, base * 0.55, grime_amount);
	base = mix(base, dust_color, dust_amount);
	ALBEDO = base;
	// Grain also breaks up the specular response, so flat surfaces stop reading
	// as single smooth values.
	ROUGHNESS = clamp(roughness_value * mix(0.94, 1.12, grain) + dust_amount * 0.25 + grime_amount * 0.15, 0.03, 1.0);
	METALLIC = metallic_value;
	SPECULAR = specular_value;
	EMISSION = emissive_color * emissive_energy;
	// TRANSPARENT_ALPHA
}
