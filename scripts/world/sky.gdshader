shader_type sky;

// Procedural physically-flavoured sky built from each map's exported palette.
// Sky radiance also feeds ambient and reflected light, so surfaces pick up the
// map's own colour cast instead of a flat constant.

uniform vec3 zenith_color : source_color = vec3(0.09, 0.24, 0.62);
uniform vec3 horizon_color : source_color = vec3(0.62, 0.72, 0.86);
uniform vec3 ground_color : source_color = vec3(0.08, 0.09, 0.08);
uniform vec3 sun_color : source_color = vec3(1.0, 0.9, 0.75);
uniform vec3 sun_direction = vec3(0.5, 1.0, 0.35);
uniform float sun_energy = 12.0;
uniform float horizon_softness = 1.1;
uniform float ground_fade = 0.09;
uniform float ground_mix = 0.08;

const float SUN_ANGULAR_RADIUS = 0.0172;

void sky() {
	vec3 view = normalize(EYEDIR);
	float up = view.y;
	// Sky gradient: dense colour at the horizon, deepening towards the zenith.
	float sky_amount = pow(clamp(up, 0.0, 1.0), horizon_softness);
	vec3 radiance = mix(horizon_color, zenith_color, sky_amount);
	// Below the horizon, haze rather than a hard dark band: the arenas are only
	// 180m across, so down-angled views do see under the map edge.
	float below = smoothstep(0.0, -ground_fade, up);
	radiance = mix(radiance, mix(horizon_color, ground_color, ground_mix), below);

	float cosine = dot(view, normalize(sun_direction));
	float disc = smoothstep(cos(2.6 * SUN_ANGULAR_RADIUS), cos(1.1 * SUN_ANGULAR_RADIUS), cosine);
	// Two-lobe glow: a tight rim around the disc plus a wide atmospheric bloom.
	float glow = pow(max(cosine, 0.0), 650.0) * 0.35 + pow(max(cosine, 0.0), 14.0) * 0.05;
	radiance += sun_color * sun_energy * (disc + glow) * (1.0 - below);

	COLOR = radiance;
}
