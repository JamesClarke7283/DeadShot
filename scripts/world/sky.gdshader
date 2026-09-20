shader_type sky;

// Procedural physically-flavoured sky built from each map's exported palette.
// Sky radiance feeds ambient and reflected light, so surfaces pick up the map's
// own colour cast instead of a flat constant.
//
// The authored colours are display tones rather than radiance, so `sky_scale`
// brings the gradient into a range that survives the environment's ACES tone
// map. The sun is a separate additive term: `sun_energy` is deliberately small
// because the disc and its glow sit on top of an already-lit gradient, and a
// large value floods the whole frame through the sky-sourced ambient.
//
// A cloud deck is projected onto the dome and lit by the same sun, which is what
// keeps the sky from reading as a flat gradient — the arenas are open to the sky
// from any position on them, so it fills a large part of every exterior frame.

uniform vec3 zenith_color : source_color = vec3(0.09, 0.24, 0.62);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.72, 0.86);
uniform vec3 ground_color : source_color = vec3(0.08, 0.09, 0.08);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.75);
uniform vec3 sun_direction = vec3(0.5, 1.0, 0.35);
uniform float sun_energy = 12.0;
uniform float horizon_softness = 1.1;
uniform float ground_fade = 0.09;
uniform float ground_mix = 0.08;
uniform float sky_scale = 1.0;
// Cloud cover: `cloud_cover` biases the deck's coverage, `cloud_sharpness` its
// edge definition and `cloud_brightness` the lit side's radiance relative to the
// sky. The deck is static — see the note in sky().
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.52;
uniform float cloud_sharpness : hint_range(0.2, 4.0) = 1.6;
uniform float cloud_brightness = 1.35;
uniform float cloud_height = 0.16;

const float SUN_ANGULAR_RADIUS = 0.0172;

// Cloud cover texture. One fetch replaces the value-noise octaves this used to
// evaluate per radiance texel; `r` is the soft mass, `g` a finer broken layer.
uniform sampler2D cloud_map : filter_linear_mipmap, repeat_enable;

void sky() {
	vec3 view = normalize(EYEDIR);
	float up = view.y;
	// Sky gradient: dense colour at the horizon, deepening towards the zenith.
	float sky_amount = pow(clamp(up, 0.0, 1.0), horizon_softness);
	vec3 radiance = mix(horizon_color, zenith_color, sky_amount) * sky_scale;
	// Below the horizon is haze, not ground: the arenas are only ~180 m across,
	// so a down-angled view past the map edge sees the same atmosphere the
	// terrain sees at its far edge. Tinting it with `ground_color` instead put a
	// hard dark band right at the horizon, where the fogged terrain meets the
	// sky. `ground_mix` keeps only a trace of the map's ground tone.
	float below = smoothstep(0.0, -ground_fade, up);
	vec3 haze = mix(horizon_color, ground_color, ground_mix) * sky_scale;
	radiance = mix(radiance, haze, below);

	vec3 sun_normal = normalize(sun_direction);

	// Cloud deck. Projected onto a flat plane above the viewer and extended
	// towards the horizon, so the deck converges with distance the way a real
	// one does instead of tiling at a constant scale overhead.
	//
	// Deliberately static: the sky's radiance feeds ambient, reflection and
	// SDFGI's sky light, and Godot caches that cubemap only while the sky shader
	// is time-invariant. Drifting the deck with TIME forced the radiance to be
	// re-rendered every frame and measured roughly five times the frame cost of
	// the whole low band. In a shooter a stable sky is also the better read.
	float height = max(up, cloud_height);
	vec2 deck = view.xz / height * 0.02;
	vec3 cover = texture(cloud_map, deck).rgb;
	// The red channel is the large mass, green a finer broken layer; multiplying
	// them keeps the deck's big shapes and breaks their edges.
	float coverage = cover.r * (0.55 + cover.g * 0.9);
	float density = clamp((coverage - (1.0 - cloud_cover)) * cloud_sharpness, 0.0, 1.0);
	// Thin the deck towards the horizon, where it is seen edge-on through the
	// most atmosphere, and stop it entirely at the horizon line.
	density *= smoothstep(0.0, 0.22, up);
	if (density > 0.0) {
		// A cloud's underside is shadowed and its sunward edge is bright. The
		// gradient across the density field is what gives the deck its volume; a
		// constant tone would read as a flat decal.
		float lit = clamp(density * 1.4 - 0.2, 0.0, 1.0);
		vec3 cloud_tone = mix(sun_color * sky_scale * 0.55, sun_color * sky_scale * cloud_brightness, lit);
		// Scatter the sun through the deck's edge, so the sunward side of each
		// cloud glows rather than stopping abruptly.
		float forward = pow(max(dot(view, sun_normal), 0.0), 6.0);
		cloud_tone += sun_color * sun_energy * forward * density * 0.25;
		radiance = mix(radiance, cloud_tone, density);
	}

	float cosine = dot(view, sun_normal);
	float disc = smoothstep(cos(2.6 * SUN_ANGULAR_RADIUS), cos(1.1 * SUN_ANGULAR_RADIUS), cosine);
	// Two-lobe glow: a tight rim around the disc plus a wide atmospheric bloom.
	float glow = pow(max(cosine, 0.0), 650.0) * 0.35 + pow(max(cosine, 0.0), 14.0) * 0.05;
	radiance += sun_color * sun_energy * (disc + glow) * (1.0 - below);

	COLOR = radiance;
}
