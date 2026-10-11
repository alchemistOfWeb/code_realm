class_name NodeMarker
extends Button
## Кружок подлокации на карте локации. Состояния: hidden («?»), known (замок), open (пульсирует),
## visited (кольцо прогресса), cleared (золотое кольцо и галочка).

const R := 34.0

var loc_id := ""
var data: Dictionary = {}
var status := "hidden"
var _selected := false
var _hover := false
var _t := 0.0
var _tex := {}
var _label: Label


func _init() -> void:
	size = Vector2(R * 2 + 16, R * 2 + 16)
	custom_minimum_size = size
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())


func setup(location_id: String, node_data: Dictionary) -> void:
	loc_id = location_id
	data = node_data
	var kind: Dictionary = WorldData.NODE_KINDS.get(data.kind, {})
	_tex.kind = Palette.game_icon(kind.get("icon", "grass"))
	_tex.lock = Palette.game_icon("padlock")
	_tex.check = Palette.icon("check")
	_tex.boss = Palette.game_icon("skull-crossed-bones")
	_label = Label.new()
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_override("font", Palette.FONT_UI_BOLD)
	_label.add_theme_font_size_override("font_size", 14)
	_label.add_theme_color_override("font_outline_color", Color(0.1, 0.06, 0.02, 0.95))
	_label.add_theme_constant_override("outline_size", 7)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.size = Vector2(200, 22)
	_label.position = Vector2(size.x * 0.5 - 100, size.y - 2)
	add_child(_label)
	refresh()


func refresh() -> void:
	status = WorldData.node_status(loc_id, data.id)
	_label.text = data.name if status != "hidden" else "???"
	_label.add_theme_color_override("font_color", Color("#FFF6E0") if status in ["open", "visited", "cleared"] else Color("#D8CDB8", 0.8))
	tooltip_text = "" if status == "hidden" else data.name
	queue_redraw()


func set_selected(on: bool) -> void:
	_selected = on
	queue_redraw()


func _process(delta: float) -> void:
	if status == "open" or _selected:
		_t += delta
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := R * (1.08 if _hover or _selected else 1.0)
	if status == "hidden":
		draw_circle(c, r * 0.7, Color(0.1, 0.08, 0.06, 0.45))
		var font := Palette.FONT_UI_BOLD
		draw_string(font, c + Vector2(-8, 10), "?", HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color(1, 1, 1, 0.5))
		return
	var underground := WorldData.is_underground(data)
	var base := Color("#7A6A8E") if underground else Color("#5E9A3E")
	if data.kind == "ruins":
		base = Color("#A8946A")
	elif data.kind == "riverside":
		base = Color("#3F8FA8")
	var lit := status in ["open", "visited", "cleared"]
	if not lit:
		base = base.lerp(Color("#6E6A62"), 0.6)
	draw_circle(c + Vector2(3, 4), r + 4, Color(0, 0, 0, 0.4))
	draw_circle(c, r + 4, Color("#2B1E12"))
	draw_circle(c, r, base.darkened(0.2))
	draw_circle(c, r * 0.84, base)
	var icon_size := r * 1.15
	draw_texture_rect(_tex.kind, Rect2(c - Vector2(icon_size, icon_size) * 0.5, Vector2(icon_size, icon_size)), false, Color(1, 1, 1, 0.95 if lit else 0.5))
	if data.get("features", {}).has("boss"):
		var bp := c + Vector2(-r * 0.8, -r * 0.8)
		draw_circle(bp, 12, Color("#2B0E0E"))
		draw_texture_rect(_tex.boss, Rect2(bp - Vector2(9, 9), Vector2(18, 18)), false, Palette.HP)
	match status:
		"known":
			draw_circle(c + Vector2(r * 0.7, r * 0.7), 13, Color("#1A1410"))
			draw_texture_rect(_tex.lock, Rect2(c + Vector2(r * 0.7, r * 0.7) - Vector2(9, 9), Vector2(18, 18)), false, Palette.ENERGY)
		"open":
			var pulse := 0.5 + 0.5 * sin(_t * 3.0)
			draw_arc(c, r + 8 + pulse * 4, 0, TAU, 48, Color(Palette.MINT, 0.6 - pulse * 0.3), 3.0, true)
		"visited", "cleared":
			var p := WorldData.node_progress(loc_id, data.id)
			draw_arc(c, r + 7, 0, TAU, 48, Color(0, 0, 0, 0.45), 5.0, true)
			draw_arc(c, r + 7, -PI / 2, -PI / 2 + TAU * p, 48, Color("#FFD24A") if status == "cleared" else Palette.MINT, 5.0, true)
			if status == "cleared":
				draw_circle(c + Vector2(r * 0.72, r * 0.72), 12, Color("#1A1410"))
				draw_texture_rect(_tex.check, Rect2(c + Vector2(r * 0.72, r * 0.72) - Vector2(8, 8), Vector2(16, 16)), false, Color("#FFD24A"))
	if _selected:
		draw_arc(c, r + 13, 0, TAU, 56, Color("#FFE08A"), 3.0, true)
