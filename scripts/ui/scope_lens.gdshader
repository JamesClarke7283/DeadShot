shader_type canvas_item;

// The eyepiece picture of a magnified scope: the black tube around a round
// lens, the fall-off of light toward the lens rim, a thin coating sheen just
// inside it and a faint reflection across the glass. Distances are in units of
// screen height so the lens stays round at any aspect ratio. The reticle is
// drawn over this by `sight_overlay.gd`.

uniform float amount : hint_range(0.0, 1.0) = 1.0;
uniform vec2 center = vec2(0.5);
uniform float radius = 0.47;
uniform float aspect = 1.7777778;

void fragment() {
	vec2 p = (UV - center) * vec2(aspect, 1.0);
	float d = length(p);
	// Resolve the lens edge over about a pixel and a half at any resolution.
	float edge = fwidth(d) * 1.5;
	float lens = 1.0 - smoothstep(radius - edge, radius + edge, d);
	// Real eyepieces darken toward the rim, then go black over the last few
	// percent: the soft ring every scope picture has.
	float rim = smoothstep(radius * 0.62, radius, d);
	float shade = rim * rim * 0.92;
	float sheen = smoothstep(radius * 0.86, radius * 0.95, d) * (1.0 - smoothstep(radius * 0.95, radius * 0.995, d));
	// A broad, very faint reflection from the upper left of the glass.
	vec2 q = p / max(radius, 0.0001);
	float glint = smoothstep(0.55, 0.0, abs(q.x + q.y + 0.55)) * smoothstep(1.0, 0.25, length(q + vec2(0.35, 0.35)));
	vec3 tint = vec3(0.05, 0.10, 0.13) * sheen * 0.5 + vec3(0.85, 0.92, 1.0) * glint * 0.035;
	float alpha = mix(1.0, max(shade, glint * 0.035), lens);
	COLOR = vec4(tint * lens / max(alpha, 0.0001), alpha * amount);
}
