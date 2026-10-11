extends VBoxContainer
## Сборка колоды.
## Слева — коллекция: у карт, взятых в колоду, зелёная лента «В колоде ×N», у исчерпанных — затемнение.
## Клик / перетаскивание — в колоду, ПКМ — убрать одну копию.
## Справа — колода мини-картами (по стоимости) с числом копий: клик или перетаскивание обратно — убрать.
## Сверху — поиск и фильтры; в колоде — кривая стоимости и состав по типам. Минимального размера нет.

const CARD_SCENE := preload("res://scenes/combat/CardVisual.tscn")
const CARD_SCALE := 0.58
const MINI_SCALE := 0.37
const GRID_MARGIN := 14

var _search: LineEdit
var _rarity_filter: OptionButton
var _type_filter: OptionButton
var _cost_filter: OptionButton
var _starter_btn: Button
var _grid: GridContainer
var _grid_scroll: ScrollContainer
var _deck_grid: GridContainer
var _deck_title: Label
var _deck_status: Label
var _deck_types: Label
var _curve: HBoxContainer
var _enemy_select: OptionButton
var _train_btn: Button


func _ready() -> void:
	add_theme_constant_override("separation", 10)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build()
	GameManager.deck_changed.connect(refresh)
	refresh()


func _build() -> void:
	# --- Панель фильтров
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 8)
	add_child(bar)
	_search = LineEdit.new()
	_search.placeholder_text = Loc.t("Поиск карты…")
	_search.custom_minimum_size.x = 190
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _refresh_collection())
	bar.add_child(_search)
	_rarity_filter = _option(bar, [[Loc.t("Все редкости"), ""]] + [["legendary", "legendary"], ["rare", "rare"], ["uncommon", "uncommon"], ["common", "common"]], true)
	_type_filter = _option(bar, [[Loc.t("Все типы"), ""], [Loc.t("Существа"), "creature"], [Loc.t("Заклинания"), "spell"], [Loc.t("Артефакты"), "artifact"]])
	_cost_filter = _option(bar, [[Loc.t("Любая цена"), Vector2i(0, 99)], ["0–2", Vector2i(0, 2)], ["3–4", Vector2i(3, 4)], ["5–6", Vector2i(5, 6)], ["7+", Vector2i(7, 99)]])
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)
	var auto := Button.new()
	auto.text = Loc.t("Автосборка")
	auto.tooltip_text = Loc.t("Собрать колоду автоматически из лучших карт коллекции")
	auto.pressed.connect(func(): GameManager.auto_build_deck())
	bar.add_child(auto)
	var clear := Button.new()
	clear.text = Loc.t("Очистить")
	clear.theme_type_variation = &"GhostButton"
	clear.pressed.connect(func(): GameManager.clear_deck())
	bar.add_child(clear)

	_starter_btn = Button.new()
	_starter_btn.text = Loc.t("Получить стартовый набор Странника (%d карт)") % GameManager.STARTER_PACK.size()
	_starter_btn.theme_type_variation = &"MintButton"
	_starter_btn.icon = Palette.game_icon("card-random")
	_starter_btn.add_theme_constant_override("icon_max_width", 22)
	_starter_btn.set_meta("sfx", "reward")
	_starter_btn.pressed.connect(_on_starter)
	add_child(_starter_btn)

	var body := HBoxContainer.new()
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 14)
	add_child(body)

	# --- Коллекция (с отступами, чтобы рамки и увеличение при наведении не обрезались)
	var left := PanelContainer.new()
	left.theme_type_variation = &"CardPanel"
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_child(left)
	_grid_scroll = ScrollContainer.new()
	_grid_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(_grid_scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, GRID_MARGIN)
	_grid_scroll.add_child(margin)
	_grid = GridContainer.new()
	_grid.add_theme_constant_override("h_separation", 14)
	_grid.add_theme_constant_override("v_separation", 16)
	margin.add_child(_grid)
	_grid_scroll.resized.connect(_update_columns)
	_grid_scroll.set_drag_forwarding(Callable(), _can_drop_collection, _drop_collection)

	# --- Колода
	var right := PanelContainer.new()
	right.theme_type_variation = &"CardPanel"
	right.custom_minimum_size.x = 372
	body.add_child(right)
	right.set_drag_forwarding(Callable(), _can_drop_deck, _drop_deck)
	var rbox := VBoxContainer.new()
	rbox.add_theme_constant_override("separation", 6)
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
	_curve.custom_minimum_size.y = 52
	_curve.add_theme_constant_override("separation", 4)
	rbox.add_child(_curve)
	_deck_types = Label.new()
	_deck_types.theme_type_variation = &"DimLabel"
	_deck_types.add_theme_font_size_override("font_size", 12)
	rbox.add_child(_deck_types)
	var deck_scroll := ScrollContainer.new()
	deck_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	deck_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	rbox.add_child(deck_scroll)
	deck_scroll.set_drag_forwarding(Callable(), _can_drop_deck, _drop_deck)
	var dm := MarginContainer.new()
	dm.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		dm.add_theme_constant_override("margin_" + side, 8)
	deck_scroll.add_child(dm)
	_deck_grid = GridContainer.new()
	_deck_grid.columns = 4
	_deck_grid.add_theme_constant_override("h_separation", 8)
	_deck_grid.add_theme_constant_override("v_separation", 10)
	dm.add_child(_deck_grid)

	var train_row := HBoxContainer.new()
	train_row.add_theme_constant_override("separation", 6)
	rbox.add_child(train_row)
	_enemy_select = OptionButton.new()
	_enemy_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enemy_select.clip_text = true
	for e in CardDatabase.all_enemies():
		_enemy_select.add_item("%s (%d HP)" % [Loc.f(e, "name"), e.hp])
		_enemy_select.set_item_metadata(_enemy_select.item_count - 1, e.id)
	train_row.add_child(_enemy_select)
	_train_btn = Button.new()
	_train_btn.text = Loc.t("Тренировка")
	_train_btn.icon = Palette.game_icon("crossed-swords")
	_train_btn.add_theme_constant_override("icon_max_width", 20)
	_train_btn.theme_type_variation = &"AccentButton"
	_train_btn.pressed.connect(_on_train)
	train_row.add_child(_train_btn)


func _option(parent: Control, items: Array, rarity_names: bool = false) -> OptionButton:
	var o := OptionButton.new()
	for it in items:
		var text: String = it[0]
		if rarity_names and String(it[1]) != "":
			text = CardDatabase.RARITY_NAMES[it[1]]
		o.add_item(text)
		o.set_item_metadata(o.item_count - 1, it[1])
	o.item_selected.connect(func(_i): _refresh_collection())
	parent.add_child(o)
	return o


func refresh() -> void:
	_starter_btn.visible = not GameManager.has_flag("starter_pack")
	_refresh_collection()
	_refresh_deck()


# ---------------------------------------------------------------- Коллекция

func _refresh_collection() -> void:
	for child in _grid.get_children():
		child.queue_free()
	var rarity: String = _rarity_filter.get_item_metadata(_rarity_filter.selected)
	var type: String = _type_filter.get_item_metadata(_type_filter.selected)
	var cost_range: Vector2i = _cost_filter.get_item_metadata(_cost_filter.selected)
	var query := _search.text.strip_edges().to_lower()
	var ids := CardDatabase.sort_by_rarity(GameManager.card_collection.keys())
	var shown := 0
	for id in ids:
		var card := CardDatabase.get_card(id)
		if rarity != "" and card.get("rarity") != rarity:
			continue
		if type != "" and card.get("type") != type:
			continue
		var cost := int(card.get("crystal_cost", 0))
		if cost < cost_range.x or cost > cost_range.y:
			continue
		if query != "" and not query in String(card.get("name", "")).to_lower() and not query in String(card.get("description", "")).to_lower():
			continue
		_grid.add_child(_collection_cell(card))
		shown += 1
	if shown == 0:
		var empty := Label.new()
		empty.text = Loc.t("Коллекция пуста. Возьми стартовый набор, проходи тесты деревьев и открывай сундуки.") if ids.is_empty() else Loc.t("Нет карт по выбранным фильтрам.")
		empty.theme_type_variation = &"DimLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.x = 400
		_grid.add_child(empty)
	_update_columns.call_deferred()


func _collection_cell(card: Dictionary) -> Control:
	var id: String = card.id
	var owned := int(GameManager.card_collection.get(id, 0))
	var in_deck := GameManager.deck_count(id)
	var free := owned - in_deck
	var cell := Control.new()
	cell.custom_minimum_size = _card_size() * CARD_SCALE
	var cv := CARD_SCENE.instantiate()
	cv.card_scale = CARD_SCALE
	cell.add_child(cv)
	cv.setup(card, free)
	cv.drag_payload = {"from": "collection", "id": id}
	var reason := GameManager.deck_add_block_reason(id)
	if free <= 0:
		cv.modulate = Color(0.45, 0.45, 0.52)
	cv.tooltip_text = (reason + "\n" if reason != "" else "") + Loc.t("В колоде: %d из %d · клик — добавить, ПКМ — убрать") % [in_deck, owned]
	cv.clicked.connect(_add.bind(id))
	cv.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			_remove(id))
	if in_deck > 0:
		var ribbon := PanelContainer.new()
		ribbon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color("#0FA37F", 0.95)
		sb.set_corner_radius_all(6)
		sb.content_margin_left = 6
		sb.content_margin_right = 6
		sb.content_margin_top = 1
		sb.content_margin_bottom = 1
		ribbon.add_theme_stylebox_override("panel", sb)
		var l := Label.new()
		l.text = Loc.t("✓ В колоде ×%d") % in_deck
		l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		l.add_theme_font_override("font", Palette.FONT_UI_BOLD)
		l.add_theme_font_size_override("font_size", 11)
		l.add_theme_color_override("font_color", Color.WHITE)
		ribbon.add_child(l)
		ribbon.position = Vector2(6, cell.custom_minimum_size.y - 22)
		cell.add_child(ribbon)
		var outline := Panel.new()
		outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var ob := StyleBoxFlat.new()
		ob.bg_color = Color.TRANSPARENT
		ob.border_color = Color("#3DDC97")
		ob.set_border_width_all(3)
		ob.set_corner_radius_all(12)
		outline.add_theme_stylebox_override("panel", ob)
		outline.position = Vector2(-4, -4)
		outline.size = cell.custom_minimum_size + Vector2(8, 8)
		cell.add_child(outline)
		cell.move_child(outline, 0)
	return cell


static func _card_size() -> Vector2:
	return Vector2(200, 280)


func _update_columns() -> void:
	var w := _grid_scroll.size.x - GRID_MARGIN * 2
	var cell := 200.0 * CARD_SCALE + 14
	_grid.columns = maxi(1, int((w + 14) / cell))


# ---------------------------------------------------------------- Колода

func _refresh_deck() -> void:
	var deck: Array = GameManager.combat_deck
	_deck_title.text = Loc.t("Колода: %d / %d") % [deck.size(), XPCalculator.MAX_DECK_SIZE]
	_deck_status.text = Loc.t("Готова к вылазке ✓ (колода любого размера)") if not deck.is_empty() else Loc.t("Колода пуста — в бою останутся только оружие и руны")
	_deck_status.add_theme_color_override("font_color", Palette.MINT if not deck.is_empty() else Palette.ENERGY)
	_train_btn.disabled = deck.is_empty()
	_train_btn.tooltip_text = Loc.t("Тренировочный бой текущей колодой: без наград и потерь")
	var counts := {}
	var types := {"creature": 0, "spell": 0, "artifact": 0}
	for id in deck:
		counts[id] = counts.get(id, 0) + 1
		var t: String = CardDatabase.get_card(id).get("type", "spell")
		types[t] = types.get(t, 0) + 1
	_deck_types.text = Loc.t("Существа: %d · Заклинания: %d · Артефакты: %d") % [types.creature, types.spell, types.artifact]
	for child in _deck_grid.get_children():
		child.queue_free()
	var unique := counts.keys()
	unique.sort_custom(func(a, b):
		var ca := CardDatabase.get_card(a)
		var cb := CardDatabase.get_card(b)
		if ca.get("crystal_cost", 0) != cb.get("crystal_cost", 0):
			return ca.get("crystal_cost", 0) < cb.get("crystal_cost", 0)
		return String(ca.get("name", "")) < String(cb.get("name", "")))
	for id in unique:
		_deck_grid.add_child(_deck_cell(id, counts[id]))
	if unique.is_empty():
		var empty := Label.new()
		empty.text = Loc.t("Перетащи карты сюда или кликни по карте в коллекции")
		empty.theme_type_variation = &"DimLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.x = 320
		_deck_grid.add_child(empty)
	_draw_curve(deck)


func _deck_cell(id: String, n: int) -> Control:
	var card := CardDatabase.get_card(id)
	var cell := Control.new()
	cell.custom_minimum_size = _card_size() * MINI_SCALE
	var cv := CARD_SCENE.instantiate()
	cv.card_scale = MINI_SCALE
	cv.hover_lift = false
	cell.add_child(cv)
	cv.setup(card, 0)
	cv.tooltip_text = "%s\n%s\n\n%s" % [card.get("name", ""), card.get("description", ""), Loc.t("Клик — убрать одну копию")]
	cv.clicked.connect(_remove.bind(id))
	cv.drag_payload = {"from": "deck", "id": id}
	if n > 1:
		var badge := Label.new()
		badge.text = "×%d" % n
		badge.add_theme_font_override("font", Palette.FONT_UI_BOLD)
		badge.add_theme_font_size_override("font_size", 16)
		badge.add_theme_color_override("font_color", Color.WHITE)
		badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
		badge.add_theme_constant_override("outline_size", 6)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		badge.position = Vector2(cell.custom_minimum_size.x - 30, cell.custom_minimum_size.y - 26)
		cell.add_child(badge)
	return cell


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
		bar.custom_minimum_size = Vector2(0, maxf(3.0, 32.0 * buckets[i] / top))
		bar.tooltip_text = Loc.t("Стоимость %s: %d карт") % [str(i) + ("+" if i == 7 else ""), buckets[i]]
		col.add_child(bar)
		var l := Label.new()
		l.text = str(i) + ("+" if i == 7 else "")
		l.add_theme_font_size_override("font_size", 10)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.add_theme_color_override("font_color", Palette.TEXT_DIM)
		col.add_child(l)
		_curve.add_child(col)


# ---------------------------------------------------------------- Действия

func _add(id: String) -> void:
	var reason := GameManager.deck_add_block_reason(id)
	if reason != "":
		EventBus.notify(reason, "warning")
		return
	GameManager.add_to_deck(id)
	Audio.play("book_place")


func _remove(id: String) -> void:
	if GameManager.remove_from_deck(id):
		Audio.play("drop")


func _can_drop_deck(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("from") == "collection"


func _drop_deck(_pos: Vector2, data: Variant) -> void:
	_add(data.id)


func _can_drop_collection(_pos: Vector2, data: Variant) -> bool:
	return data is Dictionary and data.get("from") == "deck"


func _drop_collection(_pos: Vector2, data: Variant) -> void:
	_remove(data.id)


func _on_starter() -> void:
	if GameManager.grant_starter_pack():
		SaveSystem.save_all()
		EventBus.notify(Loc.t("Стартовый набор Странника получен: %d карт уже в колоде") % GameManager.STARTER_PACK.size(), "success")
	refresh()


func _on_train() -> void:
	EventBus.go("combat", {"enemy_id": _enemy_select.get_item_metadata(_enemy_select.selected), "context": "training"})
