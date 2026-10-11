shader_type spatial;
render_mode cull_disabled;
// Стилизованная вода: волны в вершинах, полосы пены, глубокий бирюзовый цвет.

uniform vec4 shallow : source_color = vec4(0.25, 0.70, 0.78, 1.0);
uniform vec4 deep : source_color = vec4(0.07, 0.30, 0.48, 1.0);
uniform vec4 foam : source_color = vec4(0.92, 0.97, 1.0, 1.0);
uniform float speed = 0.6;
uniform float alpha = 0.88;

varying vec3 world_pos;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += sin(world_pos.x * 1.3 + TIME * speed * 2.0) * 0.04 + cos(world_pos.z * 1.1 + TIME * speed * 1.7) * 0.04;
}

void fragment() {
	vec2 p = world_pos.xz;
	float n = noise(p * 0.6 + vec2(TIME * speed * 0.3, TIME * speed * 0.2));
	float n2 = noise(p * 1.7 - vec2(TIME * speed * 0.4, 0.0));
	vec3 col = mix(deep.rgb, shallow.rgb, n * 0.7 + 0.15);
	float f = smoothstep(0.72, 0.78, n2 * 0.6 + n * 0.5);
	col = mix(col, foam.rgb, f * 0.6);
	ALBEDO = col;
	ROUGHNESS = 0.15;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = alpha;
}
