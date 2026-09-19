shader_type spatial;
render_mode unshaded, cull_back, shadows_disabled;

// Flat surfaces for glows, tracers, impacts, decals and smoke.
//
// `energy` drives EMISSION, which feeds the environment's glow pass so muzzle
// flashes and lamps read as light sources. `albedo_weight` instead drives ALBEDO,
// giving an unlit but non-emissive flat colour for surfaces that should simply
// be dark or grey: bullet holes, impact dust and smoke.

uniform vec3 color = vec3(1.0);
uniform float energy = 1.0;
uniform float albedo_weight = 0.0;
uniform float opacity : hint_range(0.0, 1.0) = 1.0;

void fragment() {
	ALBEDO = color * albedo_weight;
	EMISSION = color * energy;
	// TRANSPARENT_ALPHA
}
