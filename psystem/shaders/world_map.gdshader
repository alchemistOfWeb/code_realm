shader_type canvas_item;
// Глобальная карта в стиле King's Bounty: море с волнами, берег, регионы биомов (Вороной по
// локациям с «рваными» границами), рельеф по карте высот, тон старого пергамента и виньетка.

uniform sampler2D land : filter_linear;            // R — высота 0..1
uniform sampler2D sites : filter_nearest;          // N×1: x, y, индекс биома, 0
uniform int site_count = 0;
uniform vec4 biome_colors[11];
uniform float sea_level = 0.42;
uniform float aspect = 1.6;
uniform vec4 deep_sea : source_color = vec4(0.12, 0.31, 0.47, 1.0);
uniform vec4 shallow_sea : source_color = vec4(0.27, 0.58, 0.68, 1.0);
uniform vec4 sand : source_color = vec4(0.86, 0.78, 0.56, 1.0);
uniform vec4 parchment : source_color = vec4(0.93, 0.86, 0.68, 1.0);

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
	for (int i = 0; i < 5; i++) {
		v += a * noise(p);
		p *= 2.1;
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV;
	float h = texture(land, uv).r + (fbm(uv * 40.0) - 0.5) * 0.03;
	vec3 col;
	if (h < sea_level) {
		float depth = smoothstep(sea_level - 0.25, sea_level, h);
		col = mix(deep_sea.rgb, shallow_sea.rgb, depth);
		// Волны-штрихи у берега и рябь
		float waves = sin((sea_level - h) * 140.0 - TIME * 1.2);
		col += vec3(0.10, 0.12, 0.12) * smoothstep(0.85, 1.0, waves) * depth;
		col += vec3(0.04) * (noise(uv * vec2(260.0, 160.0) + TIME * 0.2) - 0.5);
		// Пена прямо у кромки
		col = mix(col, vec3(0.92, 0.96, 0.95), smoothstep(sea_level - 0.012, sea_level, h) * 0.65);
	} else {
		// Ближайшая локация с искажённым пространством → регион биома
		vec2 p = uv + vec2(fbm(uv * 9.0) - 0.5, fbm(uv * 9.0 + 7.3) - 0.5) * 0.06;
		p.x *= aspect;
		float best = 1e9;
		float second = 1e9;
		int bi = 0;
		for (int i = 0; i < 128; i++) {
			if (i >= site_count) {
				break;
			}
			vec4 s = texelFetch(sites, ivec2(i, 0), 0);
			vec2 sp = vec2(s.x * aspect, s.y);
			float d = distance(p, sp);
			if (d < best) {
				second = best;
				best = d;
				bi = int(s.z + 0.5);
			} else if (d < second) {
				second = d;
			}
		}
		col = biome_colors[bi].rgb;
		// Оттенки внутри региона
		float n = fbm(uv * 28.0);
		col *= 0.86 + n * 0.28;
		// Мягкая граница регионов
		float edge = smoothstep(0.0, 0.018, second - best);
		col = mix(col * 0.82, col, edge);
		// Рельеф: освещение по градиенту высоты
		vec2 e = vec2(1.0 / 384.0, 1.0 / 240.0);
		float hx = texture(land, uv + vec2(e.x, 0.0)).r - texture(land, uv - vec2(e.x, 0.0)).r;
		float hy = texture(land, uv + vec2(0.0, e.y)).r - texture(land, uv - vec2(0.0, e.y)).r;
		col *= 1.0 + clamp((-hx - hy) * 6.0, -0.25, 0.25);
		// Пляж у воды
		col = mix(sand.rgb, col, smoothstep(sea_level, sea_level + 0.025, h));
		// Мазки кисти
		col *= 0.95 + noise(uv * vec2(420.0, 90.0)) * 0.1;
	}
	// Пергамент и виньетка
	float paper = fbm(uv * 60.0);
	col = mix(col, parchment.rgb * (0.85 + paper * 0.2), 0.16);
	vec2 v = uv - 0.5;
	col *= 1.0 - dot(v, v) * 0.9;
	COLOR = vec4(col, 1.0);
}
