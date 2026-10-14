extends Control
## Визуал карты (Magic/Hearthstone-стиль): кристалл стоимости, имя, генеративная иллюстрация
## с иконкой, тип и редкость, описание, атака/защита существ, рамка по редкости
## (легендарные — анимированный золотой блик). Есть рубашка и анимация переворота.
##
## Размер: BASE_SIZE × card_scale (корневой Control занимает место в контейнерах,
## внутренний _card масштабируется).

signal clicked(card_id: String)

const BASE_SIZE := Vector2(200, 280)
const ART_SHADER := preload("res://shaders/card_art.gdshader")
const GLOW_SHADER := preload("res://shaders/card_glow.gdshader")
const TYPE_ICONS := {"spell": "magic-swirl", "creature": "wolf-head", "artifact": "gem-pendant", "rune": "rune-stone"}
const RARITY_GLOW := {"common": 0.15, "uncommon": 0.3, "rare": 0.5, "legendary": 0.8}

@export var card_scale: float = 1.0:
	set(v):
		card_scale = v
		if is_node_ready():
			_apply_scale()
@export var hover_lift: bool = true

var card: Dictionary = {}
var count: int = 0
var locked: bool = false
var face_up: bool = true

var _card: Control
var _front: Control
var _back: Control
var _frame_mat: ShaderMaterial
var _art_mat: ShaderMaterial
var _hover_tween: Tween


static func game_icon(icon_name: String) -> Texture2D:
	return Palette.game_icon(icon_name)


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	_card = Control.new()
	_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card.size = BASE_SIZE
	_card.pivot_offset = BASE_SIZE / 2.0
	add_child(_card)
	_build_back()
	mouse_entered.connect(_on_hover.bind(true))
	mouse_exited.connect(_on_hover.bind(false))
	_apply_scale()
	if not card.is_empty():
		_build_front()


func setup(card_data: Dictionary, card_count: int = 0, is_locked: bool = false) -> void:
	card = card_data
	count = card_count
	locked = is_locked
	if is_node_ready():
		_build_front()


func _apply_scale() -> void:
	custom_minimum_size = BASE_SIZE * card_scale
	size = custom_minimum_size
	pivot_offset = size / 2.0
	_card.scale = Vector2.ONE * card_scale
	# Масштаб идёт вокруг центра (нужно для переворота) — компенсируем смещение
	_card.position = _card.pivot_offset * (card_scale - 1.0)


# ---------------------------------------------------------------- Лицевая сторона

func _build_front() -> void:
	if _front:
		_front.queue_free()
	_front = Control.new()
	_front.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.size = BASE_SIZE
	_card.add_child(_front)
	_card.move_child(_front, 0)

	var rarity: String = card.get("rarity", "common")
	var rcolor: Color = Palette.RARITY_COLORS.get(rarity, Palette.TEXT_DIM)
	var art_color := Color.from_string(card.get("art_color", "#7B68EE"), Palette.ACCENT)

	# Тело карты
	var body := Panel.new()
	body.size = BASE_SIZE
	body.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := Palette.box(Color("#15142B"), Color.TRANSPARENT, 0, 12)
	sb.bg_color = Color("#15142B").lerp(art_color, 0.08)
	body.add_theme_stylebox_override("panel", sb)
	_front.add_child(body)

	# Иллюстрация
	var art := ColorRect.new()
	art.position = Vector2(12, 42)
	art.size = Vector2(176, 104)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_art_mat = ShaderMaterial.new()
	_art_mat.shader = ART_SHADER
	_art_mat.set_shader_parameter("art_color", art_color)
	_art_mat.set_shader_parameter("seed", float(String(card.get("id", "")).hash() % 997) / 97.0)
	art.material = _art_mat
	_front.add_child(art)
	var icon := TextureRect.new()
	icon.texture = game_icon(card.get("icon", "card-random"))
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(62, 46)
	icon.size = Vector2(76, 76)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.modulate = Color(1, 1, 1, 0.92)
	_front.add_child(icon)
	var art_border := Panel.new()
	art_border.position = art.position
	art_border.size = art.size
	art_border.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ab := Palette.box(Color.TRANSPARENT, Color(rcolor, 0.6), 1, 6)
	ab.draw_center = false
	art_border.add_theme_stylebox_override("panel", ab)
	_front.add_child(art_border)

	# Имя
	var name_label := _label(card.get("name", "?"), Vector2(50, 10), Vector2(140, 26), 14, Color.WHITE, Palette.FONT_TEXT_BOLD)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	name_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_front.add_child(name_label)

	# Стоимость (кристалл)
	var cost_bg := Panel.new()
	cost_bg.position = Vector2(8, 6)
	cost_bg.size = Vector2(36, 36)
	cost_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var cb := Palette.glow_box(Color("#123A6B"), Color("#7FDBFF"), Color(0.5, 0.86, 1.0, 0.35), 4, 18)
	cost_bg.add_theme_stylebox_override("panel", cb)
	_front.add_child(cost_bg)
	var cost := _label(str(card.get("crystal_cost", 0)), Vector2(8, 6), Vector2(36, 36), 18, Color.WHITE, Palette.FONT_UI_BOLD)
	cost.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	cost.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_front.add_child(cost)

	# Тип · редкость
	var type_icon := TextureRect.new()
	type_icon.texture = game_icon(TYPE_ICONS.get(card.get("type", ""), "card-random"))
	type_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	type_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	type_icon.position = Vector2(12, 151)
	type_icon.size = Vector2(16, 16)
	type_icon.modulate = rcolor
	type_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_front.add_child(type_icon)
	var type_text := "%s · %s" % [Loc.t(CardDatabase.TYPE_NAMES.get(card.get("type", ""), "")), Loc.t(CardDatabase.RARITY_NAMES.get(rarity, rarity))]
	_front.add_child(_label(type_text, Vector2(32, 150), Vector2(156, 18), 11, rcolor, Palette.FONT_UI_BOLD))

	# Описание
	var desc := _label(card.get("description", ""), Vector2(12, 172), Vector2(176, 62), 12, Palette.TEXT, Palette.FONT_TEXT, true)
	desc.max_lines_visible = 4
	_front.add_child(desc)

	# Атака / защита или флейвор
	if card.get("type", "") == "creature":
		_front.add_child(_stat_badge("broadsword", str(card.get("attack", 0)), Vector2(8, 240), Color("#E8A33D")))
		_front.add_child(_stat_badge("roman-shield", str(card.get("defense", 0)), Vector2(132, 240), Color("#6FB3FF")))
	else:
		var flavor := _label(card.get("flavor_text", ""), Vector2(12, 238), Vector2(176, 34), 10, Palette.TEXT_DIM, null, true)
		flavor.max_lines_visible = 2
		flavor.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		flavor.add_theme_font_override("font", Palette.italic_font())
		_front.add_child(flavor)

	# Уровень (улучшение слиянием копий)
	var level := int(card.get("level", 1))
	if level > 1:
		var lv := Panel.new()
		lv.position = Vector2(140, 48)
		lv.size = Vector2(44, 22)
		lv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		lv.add_theme_stylebox_override("panel", Palette.box(Color("#3A2A05", 0.92), Color("#FFD24A"), 1, 8))
		_front.add_child(lv)
		var lvl := _label(Loc.t("Ур. %d") % level, lv.position, lv.size, 12, Color("#FFE08A"), Palette.FONT_UI_BOLD)
		lvl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		lvl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		lvl.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		_front.add_child(lvl)

	# Количество
	if count > 1:
		var badge := Panel.new()
		badge.position = Vector2(154, 112)
		badge.size = Vector2(38, 26)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.add_theme_stylebox_override("panel", Palette.box(Color(0, 0, 0, 0.75), Color(rcolor, 0.8), 1, 8))
		_front.add_child(badge)
		var cnt := _label("×%d" % count, badge.position, badge.size, 13, Color.WHITE, Palette.FONT_UI_BOLD)
		cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cnt.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_front.add_child(cnt)

	# Рамка
	var frame := ColorRect.new()
	frame.size = BASE_SIZE + Vector2(16, 16)
	frame.position = Vector2(-8, -8)
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_frame_mat = ShaderMaterial.new()
	_frame_mat.shader = GLOW_SHADER
	_frame_mat.set_shader_parameter("frame_color", rcolor)
	_frame_mat.set_shader_parameter("size_px", frame.size)
	_frame_mat.set_shader_parameter("shimmer", 1.0 if rarity == "legendary" else 0.0)
	_frame_mat.set_shader_parameter("glow", RARITY_GLOW.get(rarity, 0.2))
	_frame_mat.set_shader_parameter("border", 0.03)
	frame.material = _frame_mat
	_front.add_child(frame)

	if locked:
		var shade := Panel.new()
		shade.size = BASE_SIZE
		shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
		shade.add_theme_stylebox_override("panel", Palette.box(Color(0.03, 0.03, 0.08, 0.82), Color.TRANSPARENT, 0, 12))
		_front.add_child(shade)
		var q := _label("?", Vector2(0, 60), Vector2(200, 100), 64, Color(1, 1, 1, 0.55), Palette.FONT_DISPLAY)
		q.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_front.add_child(q)
		tooltip_text = Loc.t("Карта ещё не получена")
	else:
		tooltip_text = ""
	_front.visible = face_up
	_back.visible = not face_up


func _stat_badge(icon_name: String, value: String, pos: Vector2, color: Color) -> Control:
	var box := Control.new()
	box.position = pos
	box.size = Vector2(60, 34)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Panel.new()
	bg.size = box.size
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_theme_stylebox_override("panel", Palette.box(Color(0, 0, 0, 0.55), Color(color, 0.8), 1, 10))
	box.add_child(bg)
	var icon := TextureRect.new()
	icon.texture = game_icon(icon_name)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(6, 7)
	icon.size = Vector2(20, 20)
	icon.modulate = color
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(icon)
	var label := _label(value, Vector2(28, 0), Vector2(28, 34), 18, Color.WHITE, Palette.FONT_UI_BOLD)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	box.add_child(label)
	return box


# ---------------------------------------------------------------- Рубашка и переворот

func _build_back() -> void:
	_back = Control.new()
	_back.size = BASE_SIZE
	_back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.visible = false
	_card.add_child(_back)
	var panel := Panel.new()
	panel.size = BASE_SIZE
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", Palette.box(Color("#1B1240"), Palette.ACCENT, 3, 12))
	_back.add_child(panel)
	var art := ColorRect.new()
	art.position = Vector2(10, 10)
	art.size = BASE_SIZE - Vector2(20, 20)
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = ART_SHADER
	mat.set_shader_parameter("art_color", Palette.ACCENT)
	mat.set_shader_parameter("seed", 3.3)
	art.material = mat
	_back.add_child(art)
	var icon := TextureRect.new()
	icon.texture = game_icon("card-random")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(50, 80)
	icon.size = Vector2(100, 100)
	icon.modulate = Color(1, 0.9, 0.6, 0.9)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_back.add_child(icon)
	var title := _label("CodeRealm", Vector2(0, 220), Vector2(200, 30), 15, Color(1, 0.9, 0.6), Palette.FONT_DISPLAY)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_back.add_child(title)


func show_back() -> void:
	face_up = false
	if _front:
		_front.visible = false
	_back.visible = true


## Переворот рубашкой → лицом. Возвращает Tween (можно дождаться finished).
func flip_to_front(duration: float = 0.45) -> Tween:
	var tw := create_tween()
	tw.tween_property(_card, "scale:x", 0.0, duration / 2.0).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	tw.tween_callback(func():
		face_up = true
		_back.visible = false
		if _front:
			_front.visible = true
		Audio.play("card_flip"))
	tw.tween_property(_card, "scale:x", card_scale, duration / 2.0).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return tw


# ---------------------------------------------------------------- Drag & drop

## Если задан — карту можно перетаскивать (данные уходят в _drop_data цели).
var drag_payload: Dictionary = {}


func _get_drag_data(_at_position: Vector2) -> Variant:
	if drag_payload.is_empty() or card.is_empty():
		return null
	var preview := Control.new()
	var cv: Control = load("res://scenes/combat/CardVisual.tscn").instantiate()
	cv.card_scale = 0.5
	cv.hover_lift = false
	preview.add_child(cv)
	cv.setup(card, 0)
	cv.position = -cv.custom_minimum_size / 2.0
	set_drag_preview(preview)
	Audio.play("card_flip")
	return drag_payload


# ---------------------------------------------------------------- Ввод и hover

func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if Rect2(Vector2.ZERO, size).has_point(event.position) and not card.is_empty():
			clicked.emit(card.get("id", ""))
			accept_event()


func _on_hover(on: bool) -> void:
	if not hover_lift or not face_up:
		return
	if on:
		Audio.play_hover()
	if _hover_tween:
		_hover_tween.kill()
	z_index = 5 if on else 0
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", Vector2.ONE * (1.06 if on else 1.0), 0.15).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _label(text: String, pos: Vector2, sz: Vector2, font_size: int, color: Color, font: Font, wrap: bool = false) -> Label:
	var l := Label.new()
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	l.custom_minimum_size = Vector2(sz.x, 0)
	l.text = text
	l.position = pos
	l.size = sz
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	if font:
		l.add_theme_font_override("font", font)
	return l


