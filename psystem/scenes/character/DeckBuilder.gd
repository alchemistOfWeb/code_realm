extends HBoxContainer
## Сборка колоды: коллекция слева (клик или перетаскивание → в колоду), колода справа
## (клик или перетаскивание обратно → убрать). Кривая стоимости, автосборка, стартовый набор,
## тренировочный бой.

const CARD_SCENE := preload("res://scenes/combat/CardVisual.tscn")
const CARD_SCALE := 0.56

var _grid: GridContainer
var _grid_scroll: ScrollContainer
var _deck_list: VBoxContainer
var _deck_title: Label
var _deck_status: Label
var _curve: HBoxContainer
var _starter_btn: Button
var _rarity_filter: OptionButton
var _enemy_select: OptionButton
var _train_btn: Button


func _ready() -> void:
	add_theme_constant_override("separation", 16)
	_build()
	GameManager.deck_changed.connect(refresh)
	refresh()


func _build() -> void:
	# --- Коллекция
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	add_child(left)
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 10)
	left.add_child(bar)
	var hint := Label.new()
	hint.text = "Клик или перетаскивание — в колоду"
	hint.theme_type_variation = &"DimLabel"
	hint.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(hint)
	_rarity_filter = OptionButton.new()
	_rarity_filter.add_item("Все редкости")
	_rarity_filter.set_item_metadata(0, "")
	for r in ["legendary", "rare", "uncommon", "common"]:
		_rarity_filter.add_item(CardDatabase.RARITY_NAMES[r])
		_rarity_filter.set_item_metadata(_rarity_filter.item_count - 1, r)
	_rarity_filter.item_selected.connect(func(_i): refresh())
	bar.add_child(_rarity_filter)
	var auto := Button.new()
	auto.text = "Автосборка"
	auto.tooltip_text = "Собрать колоду автоматически из лучших карт коллекции"
	auto.pressed.connect(func(): GameManager.auto_build_deck())
	bar.add_child(auto)
	var clear := Button.new()
	clear.text = "Очистить"
	clear.theme_type_variation = &"GhostButton"
	clear.pressed.connect(func(): GameManager.clear_deck())
	bar.add_child(clear)

	_starter_btn = Button.new()
	_starter_btn.text = "Получить стартовый набор Странника (%d карт)" % GameManager.STARTER_PACK.size()
	_starter_btn.theme_type_variation = &"MintButton"
	_starter_btn.icon = Palette.game_icon("card-random")
	_starter_btn.add_theme_constant_override("icon_max_width", 22)
	_starter_btn.set_meta("sfx", "reward")
	_starter_btn.pressed.connect(_on_starter)
	left.add_child(_starter_btn)

	_grid_scroll = ScrollContainer.new()
	_grid_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(_grid_scroll)
	_grid = GridContainer.new()
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grid.add_theme_constant_override("h_separation", 12)
	_grid.add_theme_constant_override("v_separation", 12)
	_grid_scroll.add_child(_grid)
	_grid_scroll.resized.connect(_update_columns)
	# Бросок карты из колоды на коллекцию — убрать
	_grid_scroll.set_drag_forwarding(Callable(), _can_drop_collection, _drop_collection)

	# --- Колода
	var right := PanelContainer.new()
	right.theme_type_variation = &"CardPanel"
	right.custom_minimum_size.x = 330
	add_child(right)
	right.set_drag_forwarding(Callable(), _can_drop_deck, _drop_deck)
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 8)
	right.add_child(rbox)
	_deck_title = Label.new()
	_deck_title.theme_type_variation = &"HeaderLabel"
	rbox.add_child(_deck_title)
	_deck_status = Label.new()
	_deck_status.theme_type_variation = &"MonoLabel"
	_deck_status.add_theme_font_size_override("font_size", 12)
	_deck_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	rbox.add_child(_deck_status)
	_curve = HBoxContainer.new()
	_curve.custom_minimum_size.y = 56
	_curve.add_theme_constant_override("separation", 4)
	rbox.add_child(_curve)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rbox.add_child(scroll)
	_deck_list = VBoxContainer.new()
	_deck_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck_list.add_theme_constant_override("separation", 3)
	scroll.add_child(_deck_list)
	scroll.set_drag_forwarding(Callable(), _can_drop_deck, _drop_deck)

	var train_row := HBoxContainer.new()
	train_row.add_theme_constant_override("separation", 6)
	rbox.add_child(train_row)
	_enemy_select = OptionButton.new()
	_enemy_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_select.clip_text = true
	for e in CardDatabase.all_enemies():
		_enemy_select.add_item("%s (%d HP)" % [e.name, e.hp])
		_enemy_select.set_item_metadata(_enemy_select.item_count - 1, e.id)
	train_row.add_child(_enemy_select)
	_train_btn = Button.new()
	_train_btn.text = "Тренировка"
	_train_btn.icon = Palette.game_icon("crossed-swords")
	_train_btn.add_theme_constant_override("icon_max_width", 20)
	_train_btn.theme_type_variation = &"AccentButton"
	_train_btn.tooltip_text = "Тренировочный бой текущей колодой: без наград и потерь"
	_train_btn.pressed.connect(_on_train)
	train_row.add_child(_train_btn)


func refresh() -> void:
	_starter_btn.visible = not GameManager.has_flag("starter_pack")
	# Коллекция
	for child in _grid.get_children():
		child.queue_free()
	var rarity: String = _rarity_filter.get_item_metadata(_rarity_filter.selected)
	var ids := CardDatabase.sort_by_rarity(GameManager.card_collection.keys())
	for id in ids:
		var card := CardDatabase.get_card(id)
		if rarity != "" and card.get("rarity") != rarity:
			continue
		var owned := int(GameManager.card_collection[id])
		var free := owned - GameManager.deck_count(id)
		var cv := CARD_SCENE.instantiate()
		cv.card_scale = CARD_SCALE
		_grid.add_child(cv)
		cv.setup(card, free)
		cv.drag_payload = {"from": "collection", "id": id}
		var reason := GameManager.deck_add_block_reason(id)
		cv.modulate = Color.WHITE if reason == "" else Color(0.5, 0.5, 0.58)
		cv.tooltip_text = reason if reason != "" else "В колоде: %d из %d" % [GameManager.deck_count(id), owned]
		cv.clicked.connect(_add.bind(id))
	if ids.is_empty():
		var empty := Label.new()
		empty.text = "Коллекция пуста. Возьми стартовый набор, проходи тесты деревьев и открывай сундуки."
		empty.theme_type_variation = &"DimLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.x = 400
		_grid.add_child(empty)
	_update_columns.call_deferred()

	# Колода
	var deck: Array = GameManager.combat_deck
	_deck_title.text = "Колода: %d / %d" % [deck.size(), XPCalculator.MAX_DECK_SIZE]
	var ready := GameManager.deck_ready()
	_deck_status.text = "Готова к экспедиции ✓" if ready else "Нужно минимум %d карт для экспедиции" % XPCalculator.MIN_DECK_SIZE
	_deck_status.add_theme_color_override("font_color", Palette.MINT if ready else Palette.ENERGY)
	_train_btn.disabled = deck.size() < 5
	_train_btn.tooltip_text = "Тренировочный бой текущей колодой: без наград и потерь" if deck.size() >= 5 else "Для тренировки нужно хотя бы 5 карт"
	for child in _deck_list.get_children():
		child.queue_free()
	var counts := {}
	for id in deck:
		counts[id] = counts.get(id, 0) + 1
	var unique := counts.keys()
	unique.sort_custom(func(a, b):
		var ca := CardDatabase.get_card(a)
		var cb := CardDatabase.get_card(b)
		if ca.get("crystal_cost", 0) != cb.get("crystal_cost", 0):
			return ca.get("crystal_cost", 0) < cb.get("crystal_cost", 0)
		return String(ca.get("name", "")) < String(cb.get("name", "")))
	for id in unique:
		_deck_list.add_child(_deck_row(id, counts[id]))
	if unique.is_empty():
		var empty := Label.new()
		empty.text = "Перетащи карты сюда"
		empty.theme_type_variation = &"DimLabel"
		_deck_list.add_child(empty)
	_draw_curve(deck)


func _deck_row(id: String, n: int) -> Button:
	var card := CardDatabase.get_card(id)
	var rcolor: Color = Palette.RARITY_COLORS.get(card.get("rarity", "common"), Palette.TEXT)
	var b := Button.new()
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.text = "◆%d   %s%s" % [card.get("crystal_cost", 0), card.get("name", id), "   ×%d" % n if n > 1 else ""]
	b.add_theme_color_override("font_color", rcolor)
	b.add_theme_color_override("font_hover_color", rcolor.lightened(0.3))
	b.add_theme_font_override("font", Palette.FONT_UI_BOLD)
	b.add_theme_font_size_override("font_size", 13)
	b.tooltip_text = "%s\n%s\n\nКлик — убрать из колоды" % [card.get("name", ""), card.get("description", "")]
	b.set_meta("sfx", "drop")
	b.pressed.connect(func(): GameManager.remove_from_deck(id))
	b.set_drag_forwarding(func(_pos): return {"from": "deck", "id": id}, Callable(), Callable())
	return b


func _draw_curve(deck: Array) -> void:
	for child in _curve.get_children():
		child.queue_free()
	var buckets := [0, 0, 0, 0, 0, 0, 0, 0]
	for id in deck:
		buckets[mini(int(CardDatabase.get_card(id).get("crystal_cost", 0)), 7)] += 1
	var top := 1
	for b in buckets:
		top = maxi(top, b)
	for i in buckets.size():
		var col := VBoxContainer.new()
		col.alignment = BoxContainer.ALIGNMENT_END
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		col.add_theme_constant_override("separation", 2)
		var bar := ColorRect.new()
		bar.color = Color("#7FDBFF") if buckets[i] > 0 else Palette.PANEL_3
		bar.custom_minimum_size = Vector2(0, maxf(3.0, 34.0 * buckets[i] / top))
		bar.tooltip_text = "Стоимость %s: %d карт" % [str(i) + ("+" if i == 7 else ""), buckets[i]]
		col.add_child(bar)
		var l := Label.new()
		l.text = str(i) + ("+" if i == 7 else "")
		l.add_theme_font_size_override("font_size", 10)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", Palette.TEXT_DIM)
		col.add_child(l)
		_curve.add_child(col)


func _update_columns() -> void:
	var w := _grid_scroll.size.x - 12
	var cell := 200.0 * CARD_SCALE + 12
	_grid.columns = maxi(1, int((w + 12) / cell))


func _add(id: String) -> void:
	var reason := GameManager.deck_add_block_reason(id)
	if reason != "":
		EventBus.notify(reason, "warning")
		return
	GameManager.add_to_deck(id)
	Audio.play("book_place")


func _can_drop_deck(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("from") == "collection"


func _drop_deck(_pos: Vector2, data: Variant) -> void:
	_add(data.id)


func _can_drop_collection(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("from") == "deck"


func _drop_collection(_pos: Vector2, data: Variant) -> void:
	GameManager.remove_from_deck(data.id)
	Audio.play("drop")


func _on_starter() -> void:
	if GameManager.grant_starter_pack():
		SaveSystem.save_all()
		EventBus.notify("Стартовый набор Странника получен: %d карт уже в колоде" % GameManager.STARTER_PACK.size(), "success")
	refresh()


func _on_train() -> void:
	EventBus.go("combat", {"enemy_id": _enemy_select.get_item_metadata(_enemy_select.selected), "context": "training"})
