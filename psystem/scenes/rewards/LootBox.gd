extends Control
## Сундук с картами (оверлей). Сундуки даются за повышение уровня (GameManager.lootboxes).
## Клик по сундуку: тряска → щелчок замка → крышка открывается → карта вылетает рубашкой и переворачивается.

const CARD_SCENE := preload("res://scenes/combat/CardVisual.tscn")
const RAYS := preload("res://shaders/rays.gdshader")

var _dim: ColorRect
var _rays: ColorRect
var _chest: TextureRect
var _count_label: Label
var _hint: Label
var _card_slot: Control
var _open_btn: Button
var _close_btn: Button
var _busy := false
var _bob: Tween
var _chest_y := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(_params: Dictionary) -> void:
	_build()
	resized.connect(_layout)
	_layout()
	_refresh()
	_dim.modulate.a = 0.0
	create_tween().tween_property(_dim, "modulate:a", 1.0, 0.25)
	Audio.play("chest_creak", 0.05)


func _build() -> void:
	_dim = ColorRect.new()
	_dim.color = Color(0.01, 0.01, 0.04, 0.82)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_dim)

	_rays = ColorRect.new()
	_rays.size = Vector2(900, 900)
	_rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rm := ShaderMaterial.new()
	rm.shader = RAYS
	rm.set_shader_parameter("ray_color", Palette.GOLD)
	rm.set_shader_parameter("intensity", 0.25)
	rm.set_shader_parameter("speed", 0.12)
	_rays.material = rm
	add_child(_rays)

	var title := Label.new()
	title.name = "Title"
	title.text = "Сундук искателя знаний"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_color_override("font_color", Palette.GOLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(700, 44)
	add_child(title)

	_count_label = Label.new()
	_count_label.theme_type_variation = &"MonoLabel"
	_count_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_count_label.size = Vector2(700, 24)
	add_child(_count_label)

	_chest = TextureRect.new()
	_chest.texture = Palette.game_icon("chest")
	_chest.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chest.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_chest.size = Vector2(220, 220)
	_chest.pivot_offset = _chest.size / 2.0
	_chest.modulate = Color("#E2B45A")
	_chest.mouse_filter = Control.MOUSE_FILTER_STOP
	_chest.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_chest.gui_input.connect(_on_chest_input)
	add_child(_chest)

	_card_slot = Control.new()
	_card_slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_card_slot.size = Vector2(200, 280)
	add_child(_card_slot)

	_hint = Label.new()
	_hint.theme_type_variation = &"DimLabel"
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.size = Vector2(700, 24)
	add_child(_hint)

	_open_btn = Button.new()
	_open_btn.text = "Открыть сундук"
	_open_btn.theme_type_variation = &"AccentButton"
	_open_btn.custom_minimum_size = Vector2(240, 46)
	_open_btn.set_meta("sfx", "")
	_open_btn.pressed.connect(_open)
	add_child(_open_btn)

	_close_btn = Button.new()
	_close_btn.text = "Закрыть"
	_close_btn.custom_minimum_size = Vector2(160, 46)
	_close_btn.pressed.connect(EventBus.back)
	add_child(_close_btn)


func _layout() -> void:
	var c := size / 2.0
	_rays.position = Vector2(c.x, c.y - 30) - _rays.size / 2.0
	get_node("Title").position = Vector2(c.x - 350, c.y - 300)
	_count_label.position = Vector2(c.x - 350, c.y - 252)
	_chest.position = Vector2(c.x - 110, c.y - 150)
	_chest_y = _chest.position.y
	_card_slot.position = Vector2(c.x - 100, c.y - 180)
	_hint.position = Vector2(c.x - 350, c.y + 112)
	_open_btn.position = Vector2(c.x - 250, c.y + 160)
	_close_btn.position = Vector2(c.x + 30, c.y + 160)


func _refresh() -> void:
	var n := GameManager.lootbox_count()
	_count_label.text = "Сундуков: %d" % n
	_open_btn.disabled = n <= 0 or _busy
	_open_btn.text = "Открыть ещё" if _card_slot.get_child_count() > 0 else "Открыть сундук"
	_hint.text = "Сундук даётся за каждый новый уровень (на каждом 5-м — два)" if n <= 0 else "Нажми на сундук"
	if n > 0 and not _busy:
		_start_bob()


func _start_bob() -> void:
	if _bob:
		_bob.kill()
	_chest.texture = Palette.game_icon("chest")
	_chest.rotation = 0.0
	_chest.position.y = _chest_y
	_bob = _chest.create_tween().set_loops()
	_bob.tween_property(_chest, "position:y", _chest_y - 8, 0.8).set_trans(Tween.TRANS_SINE)
	_bob.tween_property(_chest, "position:y", _chest_y, 0.8).set_trans(Tween.TRANS_SINE)


func _on_chest_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		_open()


func _open() -> void:
	if _busy or GameManager.lootbox_count() <= 0:
		return
	_busy = true
	if _bob:
		_bob.kill()
	for child in _card_slot.get_children():
		child.queue_free()
	_chest.visible = true
	_chest.modulate.a = 1.0
	_open_btn.disabled = true
	_chest.position.y = _chest_y
	_hint.text = ""
	_hint.remove_theme_color_override("font_color")
	var cards := GameManager.open_lootbox()
	SaveSystem.save_all()

	var tw := create_tween()
	tw.tween_callback(Audio.play.bind("chest_latch", 0.0))
	for i in 6:
		tw.tween_property(_chest, "rotation", 0.08 if i % 2 == 0 else -0.08, 0.06)
	tw.tween_property(_chest, "rotation", 0.0, 0.05)
	tw.tween_callback(func():
		Audio.play("chest_creak", 0.0)
		_chest.texture = Palette.game_icon("open-chest")
		_burst())
	tw.tween_property(_chest, "scale", Vector2(1.15, 1.15), 0.12)
	tw.tween_property(_chest, "scale", Vector2.ONE, 0.2)
	if not cards.is_empty():
		tw.tween_callback(_spawn_card.bind(cards[0]))
	tw.tween_interval(1.6)
	tw.tween_callback(func():
		_busy = false
		_refresh())


func _spawn_card(card_id: String) -> void:
	var cv := CARD_SCENE.instantiate()
	cv.hover_lift = false
	_card_slot.add_child(cv)
	cv.setup(CardDatabase.get_card(card_id), 0)
	cv.show_back()
	cv.position = Vector2(0, 120)
	cv.scale = Vector2(0.3, 0.3)
	Audio.play("whoosh")
	var tw := create_tween().set_parallel()
	tw.tween_property(cv, "position", Vector2.ZERO, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(cv, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(_chest, "modulate:a", 0.25, 0.4)
	tw.chain().tween_callback(func():
		cv.flip_to_front()
		var rarity: String = cv.card.get("rarity", "common")
		if rarity in ["rare", "legendary"]:
			Audio.play_jingle("levelup" if rarity == "legendary" else "reward")
		var name_text := "%s — %s" % [cv.card.get("name", "?"), CardDatabase.RARITY_NAMES.get(rarity, rarity)]
		_hint.text = name_text
		_hint.add_theme_color_override("font_color", Palette.RARITY_COLORS.get(rarity, Palette.TEXT)))


func _burst() -> void:
	var p := CPUParticles2D.new()
	p.position = _chest.position + _chest.size / 2.0
	p.one_shot = true
	p.amount = 60
	p.lifetime = 1.1
	p.explosiveness = 0.95
	p.direction = Vector2(0, -1)
	p.spread = 70.0
	p.initial_velocity_min = 200.0
	p.initial_velocity_max = 420.0
	p.gravity = Vector2(0, 500)
	p.scale_amount_min = 2.0
	p.scale_amount_max = 5.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color("#FFF2B0"))
	ramp.set_color(1, Color(Palette.GOLD, 0.0))
	p.color_ramp = ramp
	add_child(p)
	p.emitting = true
	get_tree().create_timer(1.8).timeout.connect(p.queue_free)
