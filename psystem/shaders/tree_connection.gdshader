shader_type canvas_item;
// Линия связи дерева (для Line2D с texture_mode = STRETCH).
// Цвет берётся из Line2D.default_color; альфа цвета = «активность» связи (0..1):
// неактивные — тусклые, активные — яркие с бегущими импульсами.

uniform float speed = 0.35;
uniform float pulse_count = 2.0;

void fragment() {
	float across = abs(UV.y - 0.5) * 2.0;
	float core = 1.0 - smoothstep(0.0, 1.0, across);
	float inner = 1.0 - smoothstep(0.0, 0.35, across);
	float active = COLOR.a;
	float f = fract(UV.x * pulse_count - TIME * speed);
	float pulse = smoothstep(0.0, 0.06, f) * (1.0 - smoothstep(0.06, 0.3, f));
	float a = (core * 0.35 + inner * 0.65) * (0.22 + 0.78 * active);
	vec3 c = COLOR.rgb * (0.85 + 1.3 * pulse * active) + vec3(1.0) * inner * 0.2 * active;
	COLOR = vec4(c, clamp(a + pulse * core * 0.55 * active, 0.0, 1.0));
}
