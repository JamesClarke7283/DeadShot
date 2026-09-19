shader_type spatial;
render_mode unshaded, cull_front, fog_disabled, shadows_disabled;
vec3 encode_depth(float value) {
	float scaled=value*65536.0;
	float integral=floor(scaled);
	return vec3(floor(integral/256.0)/255.0,fract(integral/256.0)*(256.0/255.0),fract(scaled));
}
vec3 to_linear(vec3 value) {
	return mix(pow((value + 0.055) / 1.055, vec3(2.4)), value / 12.92, lessThanEqual(value, vec3(0.04045)));
}
void fragment() {
	vec3 packed = encode_depth(clamp((-VERTEX.z - 0.5) / 199.5, 0.0, 0.999999));
	ALBEDO = OUTPUT_IS_SRGB ? packed : to_linear(packed);
}
