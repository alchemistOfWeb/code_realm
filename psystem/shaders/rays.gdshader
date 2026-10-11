shader_type canvas_item;
// Вращающиеся лучи света (баннер нового уровня, награды).

uniform vec4 ray_color : source_color = vec4(1.0, 0.84, 0.0, 1.0);
uniform float ray_count = 14.0;
uniform float speed = 0.25;
uniform float intensity = 0.6;

void fragment() {
	vec2 p = UV - 0.5;
	float r = length(p);
	float a = atan(p.y, p.x) + TIME * speed;
	float rays = pow(0.5 + 0.5 * cos(a * ray_count), 6.0);
	float rays2 = pow(0.5 + 0.5 * cos(-a * ray_count * 0.5 + TIME * speed * 1.7), 10.0) * 0.5;
	float fade = smoothstep(0.5, 0.05, r);
	float core = smoothstep(0.25, 0.0, r) * 0.6;
	float v = (rays + rays2) * fade + core;
	COLOR = vec4(ray_color.rgb, clamp(v * intensity * COLOR.a, 0.0, 1.0));
}
