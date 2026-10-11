shader_type canvas_item;
// Рамка карты: свечение по редкости. Для легендарных — бегущий золотой блик (shimmer).
// Рисуется на ColorRect поверх карты; центр прозрачный.

uniform vec4 frame_color : source_color = vec4(0.6, 0.62, 0.65, 1.0);
uniform float border = 0.035;        // толщина рамки в долях ширины
uniform float corner = 0.06;         // радиус скругления
uniform float shimmer = 0.0;         // 1 — анимированный блик (legendary)
uniform float glow = 0.4;            // яркость внешнего свечения
uniform vec2 size_px = vec2(200.0, 280.0);

float rounded_box(vec2 p, vec2 b, float r) {
	vec2 q = abs(p) - b + r;
	return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

void fragment() {
	float aspect = size_px.y / size_px.x;
	vec2 p = (UV - 0.5) * vec2(1.0, aspect);
	vec2 half_size = vec2(0.5, 0.5 * aspect) - vec2(0.012);
	float d = rounded_box(p, half_size, corner);
	float bw = border;
	float ring = smoothstep(0.004, 0.0, abs(d + bw * 0.5) - bw * 0.5);
	float outer = exp(-max(d, 0.0) * 60.0) * step(0.0, d) * glow;
	vec3 col = frame_color.rgb;
	if (shimmer > 0.0) {
		float diag = UV.x * 0.8 + UV.y * 0.6;
		float band = fract(diag - TIME * 0.35);
		float sh = smoothstep(0.0, 0.08, band) * (1.0 - smoothstep(0.08, 0.2, band));
		col = mix(col, vec3(1.0, 0.97, 0.8), sh * 0.85);
		outer *= 1.0 + 0.4 * sin(TIME * 2.0);
	}
	float inner_line = smoothstep(0.003, 0.0, abs(d + bw * 1.8) - 0.0015) * 0.35;
	float a = max(ring, max(outer, inner_line));
	COLOR = vec4(col * (1.0 + ring * 0.2), a);
}
