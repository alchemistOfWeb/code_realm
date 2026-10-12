shader_type spatial;
// Стилизованная земля (King's Bounty / WoW): пятна нескольких оттенков по мировым координатам,
// мягкие переходы, «мазки» поверх. Опционально — маска тропы (path_tex: R = тропа).
// Крутые склоны холмов вокруг полян окрашиваются в каменистый цвет (rock_color).

uniform vec4 color_a : source_color = vec4(0.36, 0.55, 0.20, 1.0);
uniform vec4 color_b : source_color = vec4(0.47, 0.66, 0.25, 1.0);
uniform vec4 color_c : source_color = vec4(0.30, 0.45, 0.17, 1.0);
uniform vec4 path_color : source_color = vec4(0.62, 0.50, 0.33, 1.0);
uniform float scale = 0.08;
uniform float detail = 0.9;
uniform bool use_path = false;
uniform sampler2D path_tex : filter_linear, repeat_disable;
uniform vec4 path_rect = vec4(0.0, 0.0, 64.0, 64.0); // x, z, width, depth в мировых координатах
uniform float roughness_value = 0.95;
uniform vec4 rock_color : source_color = vec4(0.42, 0.39, 0.32, 1.0);
uniform float rock_amount = 1.0;

varying vec3 world_pos;
varying vec3 world_normal;

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

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz * scale;
	float n1 = fbm(p);
	float n2 = fbm(p * 2.7 + 17.0);
	vec3 col = mix(color_a.rgb, color_b.rgb, smoothstep(0.35, 0.65, n1));
	col = mix(col, color_c.rgb, smoothstep(0.55, 0.8, n2) * 0.7);
	// «Мазки кисти»: вытянутый мелкий шум
	float strokes = noise(world_pos.xz * vec2(3.0, 9.0) * detail);
	col *= 0.93 + strokes * 0.12;
	if (use_path) {
		vec2 warp = vec2(fbm(world_pos.xz * 0.35) - 0.5, fbm(world_pos.xz * 0.35 + 9.1) - 0.5) * 1.4;
		vec2 uv = (world_pos.xz + warp - path_rect.xy) / path_rect.zw;
		float m = texture(path_tex, uv).r;
		float edge = fbm(world_pos.xz * 0.9) * 0.35;
		m = smoothstep(0.35 + edge * 0.5, 0.7 + edge * 0.5, m);
		vec3 pc = path_color.rgb * (0.88 + noise(world_pos.xz * 4.0) * 0.2);
		col = mix(col, pc, m);
	}
	// Склоны: чем круче, тем больше камня; на вершинах холмов снова трава
	float slope = 1.0 - clamp(world_normal.y, 0.0, 1.0);
	float rock = smoothstep(0.22, 0.5, slope + (noise(world_pos.xz * 0.7) - 0.5) * 0.2) * rock_amount;
	vec3 rc = rock_color.rgb * (0.85 + noise(world_pos.xz * vec2(1.5, 5.0) + world_pos.y) * 0.3);
	col = mix(col, rc, rock);
	col *= 1.0 - slope * 0.18;
	ALBEDO = col;
	ROUGHNESS = roughness_value;
	SPECULAR = 0.2;
}
