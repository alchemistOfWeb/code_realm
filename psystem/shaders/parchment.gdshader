shader_type canvas_item;
// Пергамент свитка: шумовая текстура бумаги, потемнение краёв, лёгкие пятна.

uniform vec4 paper_color : source_color = vec4(0.91, 0.84, 0.68, 1.0);
uniform vec4 edge_color : source_color = vec4(0.55, 0.40, 0.22, 1.0);
uniform vec2 size_px = vec2(600.0, 500.0);

float hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm(vec2 p) { float v = 0.0; float a = 0.5; for (int i = 0; i < 5; i++) { v += a * noise(p); p *= 2.03; a *= 0.5; } return v; }

void fragment() {
	vec2 px = UV * size_px;
	float grain = fbm(px * 0.02) * 0.6 + noise(px * 0.35) * 0.15;
	float stains = smoothstep(0.55, 0.75, fbm(px * 0.006 + 3.0));
	vec2 e = min(UV, 1.0 - UV) * size_px;
	float edge = 1.0 - smoothstep(0.0, 38.0 + fbm(px * 0.03) * 30.0, min(e.x, e.y));
	vec3 col = paper_color.rgb * (0.86 + grain * 0.22);
	col = mix(col, edge_color.rgb, stains * 0.18);
	col = mix(col, edge_color.rgb * 0.7, edge * 0.75);
	float fibers = smoothstep(0.62, 0.7, noise(vec2(px.x * 0.02, px.y * 0.6))) * 0.05;
	col -= fibers;
	COLOR = vec4(col, COLOR.a);
}
