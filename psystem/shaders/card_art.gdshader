shader_type canvas_item;
// Генеративный фон иллюстрации карты: вихрь рун и света в цвете карты.

uniform vec4 art_color : source_color = vec4(0.48, 0.41, 0.93, 1.0);
uniform float seed = 0.0;
uniform float animate = 1.0;

float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 4; i++) { v += a * noise(p); p *= 2.1; a *= 0.5; } return v; }

void fragment() {
	vec2 p = UV - 0.5;
	float t = TIME * 0.15 * animate + seed * 7.0;
	float r = length(p);
	float ang = atan(p.y, p.x);
	vec2 q = vec2(ang * 1.2 + t + r * 4.0, r * 3.0 - t);
	float n = fbm(q * 1.6 + seed);
	float swirl = fbm(p * 3.0 + vec2(n * 2.0, t));
	vec3 base = art_color.rgb * (0.18 + 0.55 * swirl);
	base += art_color.rgb * pow(n, 3.0) * 1.4;
	float halo = smoothstep(0.55, 0.0, r);
	base += art_color.rgb * halo * 0.35;
	float sparks = step(0.985, hash(floor(UV * 48.0) + floor(t * 2.0))) * 0.6;
	base += vec3(sparks) * halo;
	float vign = smoothstep(0.75, 0.3, r);
	COLOR = vec4(base * vign + vec3(0.02, 0.02, 0.05), 1.0);
}
