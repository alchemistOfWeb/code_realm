extends Control
## Свиток наград (оверлей поверх текущего экрана).
## Анимация: печать → свиток разворачивается под фанфару → строки наград → карты
## появляются рубашкой вверх и по очереди переворачиваются → «Забрать награду».
## Награды к моменту показа уже начислены (GameManager.complete_tree_test).
##
## params.result — результат complete_tree_test {spec_id, xp, energy, cards, nodes_marked, first, ...}

const CARD_SCENE := preload("res://scenes/combat/CardVisual.tscn")
const PARCHMENT := preload("res://shaders/parchment.gdshader")
const RAYS := preload("res://shaders/rays.gdshader")
const INK := Color("#3B2A18")
const INK_SOFT := Color("#6B5236")
const PAPER_W := 780.0
const ROLL_H := 26.0
const CLOSED_H := 46.0

var result: Dictionary = {}
var spec_color: Color = Palette.ACCENT

var _dim: ColorRect
var _rays: ColorRect
var _root: Control
var _paper: ColorRect
var _top_roll: Panel
var _bottom_roll: Panel
var _seal: Control
var _content: VBoxContainer
var _cards_row: HBoxContainer
var _claim: Button
var _hint: Label
var _opened := false
var _paper_h := 470.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(params: Dictionary) -> void:
	result = params.get("result", {})
	spec_color = ContentParser.get_spec_color(result.get("spec_id", ""))
	_build()
	_appear()


# ---------------------------------------------------------------- Построение

func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.01, 0.04, 0.78)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_rays = ColorRect.new()
	_rays.size = Vector2(1100, 1100)
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rm := ShaderMaterial.new()
	rm.shader = RAYS
	rm.set_shader_parameter("ray_color", Palette.GOLD)
	rm.set_shader_parameter("intensity", 0.35)
	_rays.material = rm
	_rays.modulate.a = 0.0
	add_child(_rays)

	_root = Control.new()
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.size = Vector2(PAPER_W + 40, _paper_h + ROLL_H * 2)
	add_child(_root)

	_paper = ColorRect.new()
	_paper.position = Vector2(20, ROLL_H * 0.5)
	_paper.size = Vector2(PAPER_W, CLOSED_H)
	_paper.clip_contents = true
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pm := ShaderMaterial.new()
	pm.shader = PARCHMENT
	pm.set_shader_parameter("size_px", Vector2(PAPER_W, _paper_h))
	_paper.material = pm
	_root.add_child(_paper)

	_content = VBoxContainer.new()
	_content.position = Vector2(40, 34)
	_content.size = Vector2(PAPER_W - 80, _paper_h - 60)
	_content.add_theme_constant_override("separation", 10)
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.modulate.a = 0.0
	_paper.add_child(_content)
	_fill_content()

	_top_roll = _make_roll()
	_top_roll.position = Vector2(0, 0)
	_root.add_child(_top_roll)
	_bottom_roll = _make_roll()
	_root.add_child(_bottom_roll)

	_seal = _make_seal()
	_root.add_child(_seal)

	_hint = Label.new()
	_hint.text = Loc.t("Нажми на печать, чтобы развернуть свиток")
	_hint.theme_type_variation = &"DimLabel"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.size = Vector2(PAPER_W, 24)
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(_hint)

	_claim = Button.new()
	_claim.text = Loc.t("Забрать награду")
	_claim.icon = Palette.icon("check")
	_claim.theme_type_variation = &"AccentButton"
	_claim.custom_minimum_size = Vector2(280, 48)
	_claim.visible = false
	_claim.set_meta("sfx", "coins")
	_claim.pressed.connect(_on_claim)
	add_child(_claim)

	resized.connect(_layout)
	_layout()
	_update_rolls()


func _make_roll() -> Panel:
	var roll := Panel.new()
	roll.size = Vector2(PAPER_W + 40, ROLL_H)
	roll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#6E4A26")
	sb.border_color = Color("#3A2410")
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(int(ROLL_H / 2))
	sb.shadow_color = Color(0, 0, 0, 0.45)
	sb.shadow_size = 6
	roll.add_theme_stylebox_override("panel", sb)
	var shine := ColorRect.new()
	shine.color = Color(1, 0.85, 0.6, 0.25)
	shine.position = Vector2(14, 5)
	shine.size = Vector2(PAPER_W + 12, 4)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	roll.add_child(shine)
	for x in [-14.0, PAPER_W + 34.0]:
		var knob := Panel.new()
		knob.position = Vector2(x, -4)
		knob.size = Vector2(20, ROLL_H + 8)
		knob.mouse_filter = Control.MOUSE_FILTER_IGNORE
		knob.add_theme_stylebox_override("panel", Palette.box(Color("#C9A24A"), Color("#5C4313"), 2, 8))
		roll.add_child(knob)
	return roll


func _make_seal() -> Control:
	var seal := Control.new()
	seal.size = Vector2(110, 110)
	seal.pivot_offset = seal.size / 2.0
	seal.mouse_filter = Control.MOUSE_FILTER_STOP
	seal.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var wax := TextureRect.new()
	wax.texture = Palette.game_icon("wax-seal")
	wax.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wax.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wax.size = seal.size
	wax.modulate = Color("#B0242B")
	wax.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.add_child(wax)
	var icon := TextureRect.new()
	var meta := ContentParser.get_spec_meta(result.get("spec_id", ""))
	icon.texture = load(meta.get("icon", "res://assets/icons/star.svg")) if ResourceLoader.exists(meta.get("icon", "")) else Palette.icon("star")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.position = Vector2(35, 35)
	icon.size = Vector2(40, 40)
	icon.modulate = Color("#FFD9A0")
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	seal.add_child(icon)
	seal.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_open())
	return seal


func _fill_content() -> void:
	var spec_name := ContentParser.get_spec_name(result.get("spec_id", ""))
	var title := Label.new()
	title.text = Loc.t("Свиток мастерства") if result.get("first", false) else Loc.t("Свиток повторения")
	title.add_theme_font_override("font", Palette.FONT_DISPLAY)
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(title)
	var sub := Label.new()
	sub.text = Loc.t("Древо «%s» покорено: %d из %d") % [spec_name, result.get("correct", 0), result.get("total", 0)]
	sub.add_theme_color_override("font_color", INK_SOFT)
	sub.add_theme_font_override("font", Palette.FONT_TEXT_SEMI)
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_content.add_child(sub)

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 28)
	row.name = "RewardRow"
	for item in [["sparkles", "+%d XP" % result.get("xp", 0), Color("#2E6B3A"), result.get("xp", 0) > 0],
			["zap", Loc.t("+%d энергии") % result.get("energy", 0), Color("#8A5A00"), result.get("energy", 0) > 0],
			["book-open", Loc.t("изучено тем: %d") % result.get("nodes_marked", 0), INK_SOFT, result.get("nodes_marked", 0) > 0]]:
		if not item[3]:
			continue
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		var ic := TextureRect.new()
		ic.texture = Palette.icon(item[0])
		ic.custom_minimum_size = Vector2(20, 20)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.modulate = item[2]
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(ic)
		var l := Label.new()
		l.text = item[1]
		l.add_theme_font_override("font", Palette.FONT_UI_BOLD)
		l.add_theme_color_override("font_color", item[2])
		box.add_child(l)
		box.modulate.a = 0.0
		row.add_child(box)
	_content.add_child(row)

	var sep := ColorRect.new()
	sep.color = Color(INK, 0.25)
	sep.custom_minimum_size = Vector2(0, 1)
	_content.add_child(sep)

	_cards_row = HBoxContainer.new()
	_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_cards_row.add_theme_constant_override("separation", 22)
	_cards_row.custom_minimum_size.y = 240
	_content.add_child(_cards_row)
	for card_id in result.get("cards", []):
		var cv := CARD_SCENE.instantiate()
		cv.card_scale = 0.8
		cv.hover_lift = false
		_cards_row.add_child(cv)
		cv.setup(CardDatabase.get_card(card_id), 0)
		cv.show_back()
		cv.modulate.a = 0.0


func _layout() -> void:
	var center := size / 2.0
	_root.position = Vector2(center.x - _root.size.x / 2.0, maxf(10.0, center.y - _root.size.y / 2.0 - 30.0))
	_rays.position = center - _rays.size / 2.0
	_claim.position = Vector2(center.x - 140, minf(size.y - 60, _root.position.y + _root.size.y + 10))
	_hint.position = Vector2(20, _paper.position.y + CLOSED_H + ROLL_H + 70)


func _update_rolls() -> void:
	_bottom_roll.position = Vector2(0, _paper.position.y + _paper.size.y - ROLL_H * 0.5)
	if is_instance_valid(_seal):
		_seal.position = Vector2(_root.size.x / 2.0 - 55, _paper.position.y + _paper.size.y / 2.0 - 55)


# ---------------------------------------------------------------- Анимация

func _appear() -> void:
	_dim.modulate.a = 0.0
	_root.modulate.a = 0.0
	_root.pivot_offset = Vector2(_root.size.x / 2.0, 40)
	_root.scale = Vector2(0.8, 0.8)
	var tw := create_tween().set_parallel()
	tw.tween_property(_dim, "modulate:a", 1.0, 0.3)
	tw.tween_property(_root, "modulate:a", 1.0, 0.35)
	tw.tween_property(_root, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	Audio.play("cloth")
	var pulse := _seal.create_tween().set_loops()
	pulse.tween_property(_seal, "scale", Vector2(1.08, 1.08), 0.6).set_trans(Tween.TRANS_SINE)
	pulse.tween_property(_seal, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_SINE)
	get_tree().create_timer(2.2).timeout.connect(_open)


func _open() -> void:
	if _opened or not is_inside_tree():
		return
	_opened = true
	_hint.visible = false
	Audio.play("chest_latch", 0.0)
	# Печать ломается
	var st := _seal.create_tween()
	st.tween_property(_seal, "scale", Vector2(1.35, 1.35), 0.15)
	st.parallel().tween_property(_seal, "rotation", 0.25, 0.15)
	st.tween_property(_seal, "modulate:a", 0.0, 0.2)
	st.tween_callback(_seal.queue_free)
	# Свиток разворачивается
	var tw := create_tween()
	tw.tween_interval(0.25)
	tw.tween_callback(func():
		Audio.play("scroll_open", 0.0)
		Audio.play_jingle("fanfare"))
	tw.tween_method(_set_paper_height, CLOSED_H, _paper_h, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.parallel().tween_property(_rays, "modulate:a", 1.0, 1.0)
	tw.tween_property(_content, "modulate:a", 1.0, 0.3)
	tw.tween_callback(_reveal_rewards)


func _set_paper_height(h: float) -> void:
	_paper.size.y = h
	_update_rolls()


func _reveal_rewards() -> void:
	var tw := create_tween()
	for box in _content.get_node("RewardRow").get_children():
		tw.tween_callback(Audio.play.bind("coins", 0.05))
		tw.tween_property(box, "modulate:a", 1.0, 0.25)
	for cv in _cards_row.get_children():
		tw.tween_callback(Audio.play.bind("book_place", 0.05))
		tw.tween_property(cv, "modulate:a", 1.0, 0.2)
	tw.tween_interval(0.3)
	for cv in _cards_row.get_children():
		tw.tween_callback(_flip_card.bind(cv))
		tw.tween_interval(0.55)
	tw.tween_callback(_show_claim)


func _flip_card(cv: Control) -> void:
	cv.flip_to_front()
	var rarity: String = cv.card.get("rarity", "common")
	if rarity in ["rare", "legendary"]:
		get_tree().create_timer(0.25).timeout.connect(func():
			Audio.play("reward" if rarity == "rare" else "levelup", 0.0)
			_flash(cv, Palette.RARITY_COLORS[rarity]))


func _flash(cv: Control, color: Color) -> void:
	var p := CPUParticles2D.new()
	p.position = cv.global_position + cv.size / 2.0
	p.top_level = true
	p.z_index = 30
	p.one_shot = true
	p.amount = 40
	p.lifetime = 1.0
	p.explosiveness = 0.9
	p.spread = 180.0
	p.direction = Vector2(0, -1)
	p.initial_velocity_min = 120.0
	p.initial_velocity_max = 280.0
	p.gravity = Vector2(0, 200)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 4.0
	var ramp := Gradient.new()
	ramp.set_color(0, color.lightened(0.5))
	ramp.set_color(1, Color(color, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.6).timeout.connect(p.queue_free)


func _show_claim() -> void:
	_claim.visible = true
	_claim.modulate.a = 0.0
	_claim.create_tween().tween_property(_claim, "modulate:a", 1.0, 0.3)
	_claim.grab_focus()


func _on_claim() -> void:
	var n: int = result.get("cards", []).size()
	if n > 0:
		EventBus.notify(Loc.t("Карты добавлены в коллекцию: %d") % n, "success")
	EventBus.back()


func _unhandled_input(event: InputEvent) -> void:
	if not _opened and event is InputEventMouseButton and event.pressed:
		_open()
		get_viewport().set_input_as_handled()
