class_name MapMarker
extends Button
## Маркер локации на глобальной карте: круг цвета биома с иконкой, кольцо прогресса исследования,
## значок уровня и подпись. Локации «в разработке» — приглушённые, со значком молотка.

const RADIUS := 26.0

var info: Dictionary = {}
var _selected := false
var _hover := false
var _camp := false
var _progress := 0.0
var _playable := false
var _icon_tex: Texture2D
var _wip_tex: Texture2D
var _label: Label


func _init() -> void:
	size = Vector2(RADIUS * 2 + 12, RADIUS * 2 + 12)
	custom_minimum_size = size
	flat = true
	focus_mode = Control.FOCUS_NONE
	mouse_entered.connect(func():
		_hover = true
		queue_redraw())
	mouse_exited.connect(func():
		_hover = false
		queue_redraw())


func setup(loc: Dictionary) -> void:
	info = loc
	_playable = WorldData.is_playable(loc.id)
	_icon_tex = Palette.game_icon(WorldData.biome(loc.biome).icon)
	_wip_tex = Palette.game_icon("hammer-drop")   # текстуры грузим заранее: load() внутри _draw даёт пустой квадрат
	tooltip_text = "%s · %s %d" % [loc.name, Loc.t("ур."), int(loc.level)]
	_add_label(loc.name)
	refresh()


func setup_camp() -> void:
	_camp = true
	_playable = true
	_icon_tex = Palette.game_icon("campfire")
	info = {"name": WorldData.camp().name, "biome": "meadow"}
	_add_label(WorldData.camp().name)
	queue_redraw()


func refresh() -> void:
	if _playable and not _camp:
		_progress = WorldData.location_progress(info.id)
	queue_redraw()


func set_selected(on: bool) -> void:
	_selected = on
	queue_redraw()


func _add_label(text: String) -> void:
	_label = Label.new()
	_label.text = text
	_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_label.add_theme_font_size_override("font_size", 13 if (_playable or _camp) else 11)
	_label.add_theme_color_override("font_color", Color("#FFF6E0") if (_playable or _camp) else Color("#E8DCC4", 0.85))
	_label.add_theme_color_override("font_outline_color", Color(0.12, 0.08, 0.04, 0.95))
	_label.add_theme_constant_override("outline_size", 6)
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.size = Vector2(170, 20)
	_label.position = Vector2(size.x * 0.5 - 85, size.y - 4)
	add_child(_label)


func _draw() -> void:
	var c := size * 0.5
	var r := RADIUS * (1.12 if _hover or _selected else 1.0)
	var base := Color(WorldData.biome(info.get("biome", "forest")).color)
	if _camp:
		base = Color("#E39B3A")
	var dim := not (_playable or _camp)
	if dim:
		base = base.lerp(Color("#8A8478"), 0.55)
	# Тень и подложка
	draw_circle(c + Vector2(2, 3), r + 3, Color(0, 0, 0, 0.35))
	draw_circle(c, r + 3, Color("#2B1E12"))
	draw_circle(c, r, base.darkened(0.15))
	draw_circle(c, r * 0.82, base)
	if _icon_tex:
		var s := r * 1.1
		draw_texture_rect(_icon_tex, Rect2(c - Vector2(s, s) * 0.5, Vector2(s, s)), false, Color(1, 1, 1, 0.95) if not dim else Color(1, 1, 1, 0.6))
	# Кольцо исследования
	if _playable and not _camp:
		draw_arc(c, r + 5, 0, TAU, 40, Color(0, 0, 0, 0.45), 4.0, true)
		if _progress > 0.0:
			draw_arc(c, r + 5, -PI / 2, -PI / 2 + TAU * _progress, 40, Palette.MINT, 4.0, true)
	if _selected:
		draw_arc(c, r + 9, 0, TAU, 48, Color("#FFE08A"), 2.5, true)
	# Значок уровня
	if not _camp:
		var bp := c + Vector2(r * 0.78, -r * 0.78)
		var lvl := int(info.get("level", 1))
		var plvl := int(GameManager.player_data.level)
		var lc := Palette.MINT if lvl <= plvl + 1 else (Palette.ENERGY if lvl <= plvl + 4 else Palette.HP)
		draw_circle(bp, 11, Color("#1A1410"))
		draw_circle(bp, 9.5, lc.darkened(0.35) if not dim else Color("#6E6A62"))
		var font := Palette.FONT_UI_BOLD
		var txt := str(lvl)
		var ts := font.get_string_size(txt, HORIZONTAL_ALIGNMENT_CENTER, -1, 11)
		draw_string(font, bp + Vector2(-ts.x * 0.5, 4), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color.WHITE)
		if dim:
			var wp := c + Vector2(-r * 0.8, r * 0.75)
			draw_circle(wp, 9, Color("#1A1410"))
			if _wip_tex:
				draw_texture_rect(_wip_tex, Rect2(wp - Vector2(7, 7), Vector2(14, 14)), false, Palette.ENERGY)
