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
// per-band variants. Each block declares everything it needs, so any combination
// of the features compiles:
//   PLANAR     one world-space projection, no triplanar helpers
//   TRIPLANAR  three projections blended by the geometric normal
//   NORMAL     tangent-space normal-map rebuild (implies triplanar sampling)
//   MACRO      large-scale weathering lookup
//   POM        parallax occlusion march into the height field (implies TRIPLANAR)
// A band that disables a feature pays neither the samples nor the instructions.

uniform vec3 albedo_color = vec3(0.35);
uniform float albedo_saturation = 1.0;
uniform float min_luminance = 0.06;
uniform float max_luminance = 1.0;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.8;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.0;
uniform float specular_value : hint_range(0.0, 1.0) = 0.5;
uniform sampler2D detail_noise : filter_linear_mipmap_anisotropic, repeat_enable;
// Albedo variation texture: `r`/`g` carry two decorrelated low-frequency fields
// and `b` a patch mask. Real surfaces are not one flat hue — concrete varies
// panel to panel, render is patched and re-rendered, asphalt has old and new
// repairs, rust spreads unevenly. Grain alone only moves brightness, which
// leaves a wall reading as a single painted tone no matter how it is lit.
uniform sampler2D albedo_variation : filter_linear_mipmap_anisotropic, repeat_enable;
uniform vec3 variation_tint_a : source_color = vec3(0.6, 0.55, 0.45);
uniform vec3 variation_tint_b : source_color = vec3(0.35, 0.36, 0.4);
uniform vec2 variation_range = vec2(0.06, 0.2);
uniform float variation_scale = 0.28;
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
// the weathering map, so they cost nothing extra on a band without MACRO.
uniform float dust_strength = 0.0;
uniform float grime_strength = 0.0;
uniform vec3 dust_color = vec3(0.6, 0.55, 0.45);
// Per-band multiplier on the sampled detail contrast: the low band flattens the
// grain so cheaper, lower-resolution noise does not shimmer.
uniform float detail_contrast = 1.0;
uniform vec3 emissive_color = vec3(0.0);
uniform float emissive_energy = 0.0;
uniform float alpha_value : hint_range(0.0, 1.0) = 1.0;
uniform float wind_strength = 0.0;
uniform float wind_time = 0.0;
// Parallax occlusion depth in metres, scaled by the band's `pom_strength`. Zero
// disables the march even when the block is compiled in.
uniform float parallax_depth = 0.0;
// Foliage transmits light: a leaf lit from behind glows rather than going dark.
// `translucency` scales that transmitted component, and `translucency_color`
// tints it — the warm yellow-green real leaves transmit. Zero leaves the surface
// opaque, which is what every non-vegetation family uses.
uniform float translucency = 0.0;
uniform vec3 translucency_color : source_color = vec3(0.35, 0.55, 0.18);
// World-space direction the sun's light travels *from* (i.e. towards the sun).
// Transmission needs the light vector, which the fragment stage does not expose,
// so the map's own sun direction is supplied with the material.
uniform vec3 sun_direction = vec3(0.5, 1.0, 0.35);

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
	vec3 view_direction = normalize(INV_VIEW_MATRIX[3].xyz - world_position);

	// Parallax occlusion: march the view ray against the grain's own height
	// field so the surface reads as having depth rather than as a picture of
	// depth. The offset is applied to the projection position before every
	// sample, so grain, normal and weathering all agree on the same surface.
	vec3 sample_position = world_position;
	// QUALITY_POM_BEGIN
	if (parallax_depth > 0.0) {
		// The dominant axis keeps the march in one plane: stepping a blend of
		// three projections at different rates samples incoherent heights and
		// tears the surface at the seams.
		vec3 pom_axis = step(vec3(0.5), abs(geometric));
		vec2 pom_uv = pom_axis.z > 0.5 ? world_position.xy : (pom_axis.y > 0.5 ? world_position.xz : world_position.zy);
		vec2 pom_view = pom_axis.z > 0.5 ? view_direction.xy : (pom_axis.y > 0.5 ? view_direction.xz : view_direction.zy);
		// The component of the view direction along the plane's own normal, which
		// is what sets how far the ray travels across the height field.
		float pom_normal_view = pom_axis.z > 0.5 ? view_direction.z : (pom_axis.y > 0.5 ? view_direction.y : view_direction.x);
		// Grazing views travel further across the height field, so the step
		// length scales with the tangent; the floor keeps it finite at the
		// horizon.
		vec2 pom_travel = pom_view / max(abs(pom_normal_view), 0.25) * parallax_depth;
		vec2 pom_step = pom_travel * 0.125;
		// The height field is the grain itself: the march descends through it and
		// stops where the ray passes below the stored height.
		vec2 pom_shift = vec2(0.0);
		float pom_t = 0.0;
		float pom_previous_t = 0.0;
		float pom_previous_h = 1.0;
		float pom_h = 1.0;
		for (int step_index = 1; step_index <= 8; step_index++) {
			pom_previous_t = pom_t;
			pom_previous_h = pom_h;
			pom_t = float(step_index) * 0.125;
			pom_shift += pom_step;
			pom_h = texture(detail_noise, (pom_uv + pom_shift) * texture_scale).r;
			if (pom_h <= 1.0 - pom_t) break;
		}
		// Refine between the bracketing layers so the offset is continuous rather
		// than quantised to the march's eight steps.
		float pom_before = pom_previous_h - (1.0 - pom_previous_t);
		float pom_after = pom_h - (1.0 - pom_t);
		float pom_fraction = clamp(pom_before / max(pom_before - pom_after, 0.0001), 0.0, 1.0);
		vec2 pom_final = pom_step * ((pom_previous_t + pom_fraction * (pom_t - pom_previous_t)) * 8.0);
		vec3 pom_offset = pom_axis.z > 0.5 ? vec3(pom_final, 0.0) : (pom_axis.y > 0.5 ? vec3(pom_final.x, 0.0, pom_final.y) : vec3(0.0, pom_final.x, pom_final.y));
		sample_position += pom_offset;
	}
	// QUALITY_POM_END

	// Grain. Cheapest band takes one planar projection; full quality blends three.
	//
	// The grain is sampled at two very different scales and blended by a
	// low-frequency mask, which is what stops a tiled noise from reading as a
	// visible repeat. A single projection at one scale makes the tile period
	// legible from a few metres away, and no amount of extra octaves inside that
	// one tile fixes it — the repeat is the problem, not the detail.
	float grain = 0.5;
	// QUALITY_PLANAR_BEGIN
	grain = texture(detail_noise, sample_position.xz * texture_scale).r;
	grain = mix(grain, texture(detail_noise, sample_position.xz * texture_scale * 0.31).r, 0.42);
	// QUALITY_PLANAR_END
	// QUALITY_TRIPLANAR_BEGIN
	grain = triplanar_field(detail_noise, triplanar_uvs(sample_position), triplanar_weight(geometric));
	// The second scale is offset and rotated so its tile boundaries never line up
	// with the first, which is what makes the blend hide the period instead of
	// merely softening it.
	vec3 second_scale = sample_position * texture_scale * 0.29;
	vec2 alternate_uvs[3] = vec2[3](second_scale.zy + vec2(0.37, 0.11), second_scale.xz + vec2(0.63, 0.29), second_scale.xy + vec2(0.19, 0.71));
	grain = mix(grain, triplanar_field(detail_noise, alternate_uvs, triplanar_weight(geometric)), 0.42);
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
	vec2 normal_uvs[3] = triplanar_uvs(sample_position);
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
	// Hue variation: patch the wall's own tint from two colour casts, weighted
	// by a mask, so one panel of concrete is not the same tone as the next. This
	// is the difference between a surface that is *painted one colour* and one
	// that *is* a material — grain moves brightness within a panel, this moves
	// the panel's colour. Scaled by variation_scale so a family whose authored
	// palette must survive (skin, glass, team colours) can switch it off.
	if (variation_scale > 0.0) {
		vec3 variation = texture(albedo_variation, sample_position.xz * variation_scale).rgb
			+ texture(albedo_variation, sample_position.zy * variation_scale * 0.61).rgb;
		float field = clamp(variation.r * 0.5 + variation.g * 0.3 + variation.b * 0.2, 0.0, 1.0);
		vec3 patch = mix(variation_tint_a, variation_tint_b, clamp(variation.b * 1.6 - 0.2, 0.0, 1.0));
		float amount = mix(variation_range.x, variation_range.y, field);
		base = mix(base, base * patch * 2.0, amount);
	}
	// Grime first (it darkens and settles), then dust over the top of it.
	base = mix(base, base * 0.55, grime_amount);
	base = mix(base, dust_color, dust_amount);
	ALBEDO = base;
	// Grain also breaks up the specular response, so flat surfaces stop reading
	// as single smooth values. Dust and grime are rougher than the surface under
	// them, which is what stops a wet-looking metal from staying glossy once
	// it is filthy.
	ROUGHNESS = clamp(roughness_value * mix(0.94, 1.12, grain) + dust_amount * 0.25 + grime_amount * 0.15, 0.03, 1.0);
	METALLIC = metallic_value;
	SPECULAR = specular_value;
	EMISSION = emissive_color * emissive_energy;
	// Leaves are thin: light striking the back of a leaf is transmitted out of
	// the front, so a canopy lit from behind glows instead of reading as a dark
	// mass. The wrap-around term approximates transmission without a shadow
	// lookup, and the normal is bent towards the light so canopy shells self-shade
	// less than a solid surface would.
	if (translucency > 0.0) {
		vec3 to_sun = normalize(sun_direction);
		// Transmitted light peaks when the surface is lit from behind: the sun is
		// on the far side of the leaf from the viewer.
		float backlight = pow(max(dot(-view_direction, to_sun), 0.0), 1.5);
		EMISSION += translucency_color * translucency * backlight * 2.2;
	}
	// TRANSPARENT_ALPHA
}
