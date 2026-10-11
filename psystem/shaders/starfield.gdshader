shader_type canvas_item;
// Фон: градиент + медленно дрейфующая туманность + мерцающие звёзды.

uniform vec4 bg_top : source_color = vec4(0.035, 0.035, 0.085, 1.0);
uniform vec4 bg_bottom : source_color = vec4(0.07, 0.045, 0.12, 1.0);
uniform vec4 nebula_a : source_color = vec4(0.48, 0.41, 0.93, 1.0);
uniform vec4 nebula_b : source_color = vec4(0.0, 0.83, 0.67, 1.0);
uniform float nebula_strength = 0.2;
uniform float star_brightness = 1.0;

float hash(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return v;
}

float stars(vec2 uv, float density, float size, float t, float rarity) {
	vec2 g = uv * density;
	vec2 id = floor(g);
	vec2 f = fract(g) - 0.5;
	float h = hash(id);
	vec2 off = vec2(hash(id + 1.3), hash(id + 7.1)) - 0.5;
	float d = length(f - off * 0.7);
	float tw = 0.55 + 0.45 * sin(t * (0.8 + h * 4.0) + h * 100.0);
	return step(h, rarity) * smoothstep(size, 0.0, d) * tw;
}

void fragment() {
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 p = vec2(UV.x * aspect, UV.y);
	float t = TIME;
	vec3 col = mix(bg_top.rgb, bg_bottom.rgb, UV.y);

	float n1 = fbm(p * 1.4 + vec2(t * 0.010, t * 0.004));
	float n2 = fbm(p * 2.2 - vec2(t * 0.006, -t * 0.008) + 10.0);
	col += nebula_a.rgb * pow(n1, 3.0) * nebula_strength * 2.6;
	col += nebula_b.rgb * pow(n2, 4.0) * nebula_strength * 1.4;

	float s = stars(p, 70.0, 0.09, t, 0.07)
		+ stars(p + 3.7, 140.0, 0.12, t * 1.3, 0.05) * 0.55
		+ stars(p + 9.1, 32.0, 0.05, t * 0.7, 0.06) * 1.3;
	col += vec3(0.85, 0.88, 1.0) * s * star_brightness;

	float v = smoothstep(1.25, 0.3, length(UV - 0.5) * 1.5);
	col *= mix(0.55, 1.0, v);
	COLOR = vec4(col, 1.0);
}
