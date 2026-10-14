extends Control
## Полоска компаса сверху по центру (как в Skyrim): стороны света по направлению взгляда, метки указателей,
## входов в пещеры, неизвестных мест («?») и ближайших врагов. Север — −Z (верх карты локации).

const WIDTH := 500.0
const HEIGHT := 40.0
const SPAN := deg_to_rad(200.0)     # сколько градусов помещается в полоску
const DIRS := [["С", PI], ["СВ", PI * 0.75], ["В", PI * 0.5], ["ЮВ", PI * 0.25], ["Ю", 0.0], ["ЮЗ", -PI * 0.25], ["З", -PI * 0.5], ["СЗ", -PI * 0.75]]
const COLORS := {"sign": Color("#F5C542"), "cave": Color("#B08CFF"), "unknown": Color("#E8E2D0"), "enemy": Color("#FF5050")}

var _yaw := 0.0
var _pos := Vector3.ZERO
var _markers: Array = []
var _font: Font


func _ready() -> void:
	set_anchors_preset(Control.PRESET_CENTER_TOP)
	offset_left = -WIDTH * 0.5
	offset_right = WIDTH * 0.5
	offset_top = 10
	offset_bottom = 10 + HEIGHT
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = Palette.FONT_UI_BOLD


## yaw — направление взгляда (вектор (sin, cos) по осям X, Z).
func update_view(yaw: float, pos: Vector3, markers: Array) -> void:
	_yaw = yaw
	_pos = pos
	_markers = markers
	queue_redraw()


## Смещение по горизонтали для направления bearing; null — вне полоски.
func _x_of(bearing: float) -> float:
	var rel := angle_difference(_yaw, bearing)
	return size.x * 0.5 - rel / (SPAN * 0.5) * size.x * 0.5


func _draw() -> void:
	var w := size.x
	draw_style_box(Palette.box(Color("#0B0A14", 0.62), Color(1, 1, 1, 0.12), 1, 6, 0, 0), Rect2(Vector2.ZERO, size))
	# Деления каждые 15°
	for k in 24:
		var b := TAU * k / 24.0 - PI
		var rel := angle_difference(_yaw, b)
		if absf(rel) > SPAN * 0.5:
			continue
		var x := _x_of(b)
		draw_line(Vector2(x, HEIGHT - 8), Vector2(x, HEIGHT - 3), Color(1, 1, 1, 0.3), 1.0)
	for d in DIRS:
		var rel := angle_difference(_yaw, d[1])
		if absf(rel) > SPAN * 0.5:
			continue
		var x := _x_of(d[1])
		var main: bool = String(d[0]).length() == 1
		var text: String = Loc.t(d[0])
		var fs := 17 if main else 12
		var tw := _font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var col := Color("#FF6B6B") if d[0] == "С" else Color(1, 1, 1, 0.9 if main else 0.55)
		draw_string_outline(_font, Vector2(x - tw * 0.5, 22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 4, Color(0, 0, 0, 0.7))
		draw_string(_font, Vector2(x - tw * 0.5, 22), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
	# Метки
	for m in _markers:
		var v: Vector3 = m.pos - _pos
		if Vector2(v.x, v.z).length() < 0.5:
			continue
		var b := atan2(v.x, v.z)
		var rel := angle_difference(_yaw, b)
		if absf(rel) > SPAN * 0.5:
			continue
		var x := _x_of(b)
		var col: Color = COLORS.get(m.kind, Color.WHITE)
		match m.kind:
			"enemy":
				draw_circle(Vector2(x, HEIGHT - 9), 3.5, col)
			"unknown":
				draw_string_outline(_font, Vector2(x - 4, HEIGHT - 3), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, 4, Color(0, 0, 0, 0.8))
				draw_string(_font, Vector2(x - 4, HEIGHT - 3), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, col)
			_:
				var pts := PackedVector2Array([Vector2(x, HEIGHT - 2), Vector2(x - 6, HEIGHT - 12), Vector2(x + 6, HEIGHT - 12)])
				draw_colored_polygon(pts, col)
				draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[0]]), Color(0, 0, 0, 0.7), 1.0)
				# Название — когда метка почти по курсу
				if absf(rel) < deg_to_rad(12) and String(m.label) != "":
					var dist := Vector2(v.x, v.z).length()
					var t := "%s · %d м" % [m.label, roundi(dist)]
					var tw := _font.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12).x
					draw_string_outline(_font, Vector2(x - tw * 0.5, HEIGHT + 15), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, 4, Color(0, 0, 0, 0.8))
					draw_string(_font, Vector2(x - tw * 0.5, HEIGHT + 15), t, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)
	# Центр — направление взгляда
	draw_line(Vector2(w * 0.5, 0), Vector2(w * 0.5, 6), Color(1, 1, 1, 0.8), 2.0)
