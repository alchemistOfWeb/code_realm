shader_type canvas_item;
// Бегущий блик по заполненной части прогресс-бара. fill — доля заполнения (0..1).

uniform float fill = 0.5;
uniform float speed = 0.5;
uniform vec4 shine_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);

void fragment() {
	float pos = fract(TIME * speed * 0.6);
	float x = UV.x / max(fill, 0.001);
	float band = 1.0 - smoothstep(0.0, 0.12, abs(x - pos * 1.4 + 0.2));
	float inside = step(UV.x, fill);
	float top = 1.0 - UV.y * 0.6;
	COLOR = vec4(shine_color.rgb, band * inside * top * 0.45);
}
