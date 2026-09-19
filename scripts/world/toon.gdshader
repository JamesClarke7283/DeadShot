shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_disabled, ambient_light_disabled, fog_disabled;

// Source colors are already linear, as stored by THREE.Color.
uniform vec3 base_color = vec3(1.0);
uniform vec3 emissive_color = vec3(0.0);
uniform vec3 hemisphere_sky = vec3(0.520, 0.768, 1.0);
uniform vec3 hemisphere_ground = vec3(0.068, 0.102, 0.042);
uniform float hemisphere_intensity = 1.0;
uniform float bands = 3.0;
uniform float opacity = 1.0;
uniform float wind_strength = 0.0;
uniform float wind_time = 0.0;
uniform bool unlit = false;
uniform bool raw_unlit = false;
uniform bool receive_shadows = true;
uniform vec3 fog_color = vec3(0.5);
uniform float fog_near = 70.0;
uniform float fog_far = 260.0;
uniform float exposure = 1.05;
uniform bool source_shadow_enabled=false;
uniform sampler2D source_shadow_texture : filter_nearest, repeat_disable;
uniform mat4 source_shadow_view;
varying vec3 source_shadow_coord;
uniform int source_light_count = 0;
uniform vec4 source_light_positions[32];
uniform vec4 source_light_colors[32];
varying vec3 world_position;
varying vec3 world_normal;
varying float view_depth;
varying float source_shadow_factor;
varying vec3 source_point_radiance;

vec3 source_aces(vec3 color) {
	mat3 aces_input = mat3(vec3(0.59719, 0.07600, 0.02840), vec3(0.35458, 0.90834, 0.13383), vec3(0.04823, 0.01566, 0.83777));
	mat3 aces_output = mat3(vec3(1.60475, -0.10208, -0.00327), vec3(-0.53108, 1.10813, -0.07276), vec3(-0.07367, -0.00605, 1.07602));
	color = aces_input * (color * exposure / 0.6);
	color = (color * (color + 0.0245786) - 0.000090537) / (color * (0.983729 * color + 0.4329510) + 0.238081);
	return clamp(aces_output * color, vec3(0.0), vec3(1.0));
}

vec3 to_srgb(vec3 value) {
	return mix(1.055 * pow(max(value, vec3(0.0)), vec3(1.0 / 2.4)) - 0.055, value * 12.92, lessThanEqual(value, vec3(0.0031308)));
}

vec3 to_linear(vec3 value) {
	return mix(pow((value + 0.055) / 1.055, vec3(2.4)), value / 12.92, lessThanEqual(value, vec3(0.04045)));
}

vec3 source_display(vec3 radiance, float depth) {
	// Three r180 applies ACES, then linear->sRGB, then blends depth fog.
	return mix(to_srgb(source_aces(radiance)), to_srgb(fog_color), smoothstep(fog_near, fog_far, depth));
}

vec3 source_output(vec3 radiance, float depth) {
	// DIFFUSE_LIGHT is linear in both Godot 4.7 renderers, including Compatibility.
	return to_linear(source_display(radiance, depth));
}

float depth_compare(vec2 uv,float depth) {
	vec3 packed=texture(source_shadow_texture,uv).rgb;
	float stored=dot(packed,vec3(255.0/256.0,255.0/65536.0,1.0/65536.0));
	return step(depth,stored);
}
float source_shadow(vec3 coordinate) {
	if (coordinate.x<0.0 || coordinate.x>1.0 || coordinate.y<0.0 || coordinate.y>1.0 || coordinate.z>1.0) return 1.0;
	float dx=1.0/2048.0;
	float dy=dx;
	vec2 texel=vec2(dx,dy);
	vec2 uv=coordinate.xy;
	vec2 f=fract(uv*2048.0+0.5);
	uv-=f*texel;
	float z=coordinate.z-0.0005;
	return (
		depth_compare(uv,z)+depth_compare(uv+vec2(dx,0.0),z)+depth_compare(uv+vec2(0.0,dy),z)+depth_compare(uv+texel,z)+
		mix(depth_compare(uv+vec2(-dx,0.0),z),depth_compare(uv+vec2(2.0*dx,0.0),z),f.x)+
		mix(depth_compare(uv+vec2(-dx,dy),z),depth_compare(uv+vec2(2.0*dx,dy),z),f.x)+
		mix(depth_compare(uv+vec2(0.0,-dy),z),depth_compare(uv+vec2(0.0,2.0*dy),z),f.y)+
		mix(depth_compare(uv+vec2(dx,-dy),z),depth_compare(uv+vec2(dx,2.0*dy),z),f.y)+
		mix(mix(depth_compare(uv+vec2(-dx,-dy),z),depth_compare(uv+vec2(2.0*dx,-dy),z),f.x),
			mix(depth_compare(uv+vec2(-dx,2.0*dy),z),depth_compare(uv+vec2(2.0*dx,2.0*dy),z),f.x),f.y)
	)/9.0;
}

void vertex() {
	// Exact source Foliage.ts displacement, applied in local mesh space.
	float sway = sin(wind_time * 1.6 + MODEL_MATRIX[3].x * 0.7 + MODEL_MATRIX[3].z * 0.5) * wind_strength;
	float h = smoothstep(0.0, 2.0, VERTEX.y);
	VERTEX.x += sway * h;
	VERTEX.z += sway * 0.5 * h;
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	vec3 shadow_position=(source_shadow_view*vec4(world_position+world_normal*0.04,1.0)).xyz;
	source_shadow_coord=vec3(shadow_position.x/80.0+0.5,0.5-shadow_position.y/80.0,(-shadow_position.z-0.5)/199.5);
	view_depth = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	// Godot already flips double-sided normals before fragment().
	ALBEDO = vec3(1.0);
	// Compatibility expects display-space EMISSION, but linear DIFFUSE_LIGHT.
	vec3 unlit_output = raw_unlit ? base_color : source_display(base_color, -VERTEX.z);
	EMISSION = unlit ? (OUTPUT_IS_SRGB ? unlit_output : to_linear(unlit_output)) : vec3(0.0);
	ROUGHNESS = 1.0;
	SPECULAR = 0.0;
	vec3 source_normal=normalize((INV_VIEW_MATRIX*vec4(NORMAL,0.0)).xyz);
	source_shadow_factor=(receive_shadows && source_shadow_enabled) ? source_shadow(source_shadow_coord) : 1.0;
	source_point_radiance = vec3(0.0);
	for (int i = 0; i < (unlit ? 0 : source_light_count); i++) {
		vec3 offset = source_light_positions[i].xyz - world_position;
		float distance = length(offset);
		float cutoff = source_light_positions[i].w;
		float attenuation = 1.0 / max(pow(distance, source_light_colors[i].w), 0.01);
		if (cutoff > 0.0) attenuation *= pow(clamp(1.0 - pow(distance / cutoff, 4.0), 0.0, 1.0), 2.0);
		float coordinate = clamp(dot(source_normal, offset / max(distance, 0.00001)) * 0.5 + 0.5, 0.0, 1.0);
		float index = min(floor(coordinate * bands), bands - 1.0);
		float point_ramp = floor(pow(index / max(bands - 1.0, 1.0), 0.8) * 255.0 + 0.5) / 255.0;
		source_point_radiance += source_light_colors[i].rgb * attenuation * point_ramp;
	}
	// ALPHA is inserted only in the transparent material variant.
}

void light() {
	// Source ramp uses nearest-filtered Uint8 values biased by pow(t, .8).
	float ramp_coordinate = clamp(dot(NORMAL, LIGHT) * 0.5 + 0.5, 0.0, 1.0);
	float step_index = min(floor(ramp_coordinate * bands), bands - 1.0);
	float ramp = floor(pow(step_index / max(bands - 1.0, 1.0), 0.8) * 255.0 + 0.5) / 255.0;
	float shadow = receive_shadows ? (source_shadow_enabled ? source_shadow_factor : ATTENUATION) : 1.0;
	vec3 source_normal = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float hemisphere_mix = dot(source_normal, vec3(0.0, 1.0, 0.0)) * 0.5 + 0.5;
	vec3 hemisphere = mix(hemisphere_ground, hemisphere_sky, hemisphere_mix) * hemisphere_intensity;

	vec3 radiance = base_color * (hemisphere + ramp * LIGHT_COLOR * shadow + source_point_radiance) / PI + emissive_color;
	DIFFUSE_LIGHT += unlit ? vec3(0.0) : source_output(radiance, view_depth);
}
