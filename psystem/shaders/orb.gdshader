shader_type canvas_item;
// Светящаяся сфера специализации с кольцом прогресса.

uniform vec4 orb_color : source_color = vec4(0.29, 0.62, 1.0, 1.0);
uniform vec4 ring_color : source_color = vec4(0.0, 0.83, 0.67, 1.0);
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform float hover : hint_range(0.0, 1.0) = 0.0;
uniform float seed = 0.0;
uniform bool show_ring = true;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
		mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 4; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	float R = 0.56;
	float t = TIME + seed * 13.0;
	float pulse = 0.5 + 0.5 * sin(t * 1.7);

	// Внешнее свечение
	float glow = exp(-max(r - R, 0.0) * (7.5 - hover * 2.5)) * (0.42 + 0.18 * pulse + 0.35 * hover);
	glow *= smoothstep(1.0, 0.8, r);
	vec3 col = orb_color.rgb * (1.2 + hover * 0.5);
	float alpha = glow;

	// Сфера
	if (r < R + 0.02) {
		vec2 q = p / R;
		float z = sqrt(max(1.0 - dot(q, q), 0.0));
		vec3 n = vec3(q, z);
		vec3 L = normalize(vec3(-0.45, -0.55, 0.7));
		float diff = max(dot(n, L), 0.0);
		float e = fbm(q * 2.4 + vec2(t * 0.16, -t * 0.11) + seed);
		float e2 = fbm(q * 4.0 - vec2(t * 0.09, t * 0.13) + seed * 3.0);
		vec3 base = orb_color.rgb * (0.25 + 0.9 * e) + orb_color.rgb * pow(e2, 3.0) * 1.2;
		vec3 c = base * (0.3 + 0.95 * diff);
		c += orb_color.rgb * pow(1.0 - z, 2.2) * (1.3 + hover * 0.6);
		c += vec3(1.0) * pow(max(dot(reflect(-L, n), vec3(0.0, 0.0, 1.0)), 0.0), 20.0) * 0.55;
		float edge = smoothstep(R, R - 0.02, r);
		col = mix(col, c, edge);
		alpha = mix(alpha, 1.0, edge);
	}

	// Кольцо прогресса (по часовой стрелке от верха)
	if (show_ring) {
		float ring_r = 0.74;
		float w = 0.032;
		float ring = smoothstep(w, w - 0.014, abs(r - ring_r));
		float a01 = fract(atan(p.x, -p.y) / 6.2831853 + 1.0);
		float filled = step(a01, progress) * step(0.001, progress);
		vec3 rc = mix(orb_color.rgb * 0.35, ring_color.rgb * 1.3, filled);
		float ra = ring * mix(0.45, 1.0, filled);
		col = mix(col, rc, ra);
		alpha = max(alpha, ra);
	}

	COLOR = vec4(col, clamp(alpha, 0.0, 1.0) * COLOR.a);
}
