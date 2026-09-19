shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled, fog_disabled;

uniform vec3 base_color = vec3(0.00303527);
uniform float thickness = 0.03;

void vertex() {
	VERTEX += normalize(NORMAL) * thickness;
}

void fragment() {
	// Source ShaderMaterial writes linear uColor directly to the display target.
	ALBEDO = mix(pow((base_color + 0.055) / 1.055, vec3(2.4)), base_color / 12.92, lessThanEqual(base_color, vec3(0.04045)));
}
