extends Control
## Экран персонажа. Вкладки: Статистика (HP/XP/энергия, атрибуты, прогресс знаний),
## Снаряжение (кукла + инвентарь), Коллекция карт, Колода.

@onready var tabs: TabContainer = %Tabs
@onready var level_label: Label = %LevelLabel
@onready var total_xp_label: Label = %TotalXPLabel
@onready var avatar_orb: ColorRect = %AvatarOrb
@onready var bars: GridContainer = %Bars
@onready var attr_points_label: Label = %AttributePointsLabel
@onready var attr_container: VBoxContainer = %AttributesContainer
@onready var spec_list: VBoxContainer = %SpecList
@onready var cards_info: Label = %CardsInfo
@onready var cards_grid: GridContainer = %CardsGrid
@onready var deck_info: Label = %DeckInfo


func _ready() -> void:
	%BackButton.pressed.connect(EventBus.back)
	%SaveDirButton.pressed.connect(func(): OS.shell_open(SaveSystem.get_save_dir_absolute()))
	%WipeButton.pressed.connect(_confirm_wipe)
	var equipment := preload("res://scenes/character/EquipmentPanel.gd").new()
	equipment.name = "Equipment"
	tabs.add_child(equipment)
	tabs.move_child(equipment, 1)
	tabs.set_tab_title(0, "Статистика")
	tabs.set_tab_title(1, "Снаряжение")
	tabs.set_tab_title(2, "Коллекция карт")
	tabs.set_tab_title(3, "Колода")
	GameManager.player_changed.connect(_refresh_stats)
	_refresh_all()


func setup(params: Dictionary) -> void:
	tabs.current_tab = clampi(params.get("tab", 0), 0, tabs.get_tab_count() - 1)


func on_resume() -> void:
	_refresh_all()


func _refresh_all() -> void:
	_refresh_stats()
	_refresh_knowledge()
	_refresh_card_collection()
	_refresh_deck()


# ---------------------------------------------------------------- Статистика

func _refresh_stats() -> void:
	var p := GameManager.player_data
	level_label.text = "%s · %s" % [p.get("name", ""), Loc.t("Уровень %d") % p.level]
	total_xp_label.text = "Всего опыта: %d" % p.get("total_xp", 0)
	(avatar_orb.material as ShaderMaterial).set_shader_parameter("progress", float(p.xp) / maxf(p.xp_to_next, 1))

	for child in bars.get_children():
		child.queue_free()
	_add_bar_row("Здоровье", "HPBar", p.hp, p.max_hp, "%d / %d" % [p.hp, p.max_hp])
	_add_bar_row("Опыт", "XPBar", p.xp, p.xp_to_next, "%d / %d" % [p.xp, p.xp_to_next])
	_add_bar_row("Энергия", "EnergyBar", p.energy, p.max_energy, "%d / %d" % [p.energy, p.max_energy])
	_add_text_row("Золото", str(p.gold), Palette.GOLD)
	var eq := GameManager.equipment_stats()
	_add_text_row("Уклонение", "%d%%" % XPCalculator.dodge_chance(GameManager.effective_attributes().get("agility", 0), int(eq.get("dodge", 0))), Palette.TEXT)
	_add_text_row("Броня", str(int(eq.get("armor", 0))), Palette.TEXT)

	attr_points_label.text = "Очки атрибутов: %d" % p.attribute_points
	attr_points_label.add_theme_color_override("font_color", Palette.MINT if p.attribute_points > 0 else Palette.TEXT_DIM)
	for child in attr_container.get_children():
		child.queue_free()
	for attr_name in XPCalculator.ATTRIBUTES:
		attr_container.add_child(_attribute_row(attr_name, p))


func _add_bar_row(title: String, variation: String, value: float, max_value: float, text: String) -> void:
	var name_label := Label.new()
	name_label.text = title
	name_label.theme_type_variation = &"DimLabel"
	bars.add_child(name_label)
	var bar := ProgressBar.new()
	bar.theme_type_variation = StringName(variation)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(110, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.max_value = maxf(max_value, 1)
	bar.value = value
	bars.add_child(bar)
	var value_label := Label.new()
	value_label.text = text
	value_label.theme_type_variation = &"MonoLabel"
	bars.add_child(value_label)


func _add_text_row(title: String, text: String, color: Color) -> void:
	var name_label := Label.new()
	name_label.text = title
	name_label.theme_type_variation = &"DimLabel"
	bars.add_child(name_label)
	bars.add_child(Control.new())
	var value_label := Label.new()
	value_label.text = text
	value_label.theme_type_variation = &"StatLabel"
	value_label.add_theme_color_override("font_color", color)
	bars.add_child(value_label)


func _attribute_row(attr_name: String, p: Dictionary) -> Control:
	var info: Dictionary = XPCalculator.ATTRIBUTES[attr_name]
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Palette.box(Color(Palette.PANEL, 0.8), Palette.BORDER, 1, 10, 14, 10))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	panel.add_child(row)

	var icon := TextureRect.new()
	icon.texture = Palette.icon(info.icon)
	icon.custom_minimum_size = Vector2(26, 26)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.modulate = Palette.ACCENT.lightened(0.2)
	row.add_child(icon)

	var text_box := VBoxContainer.new()
	text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text_box.add_theme_constant_override("separation", 0)
	var name_label := Label.new()
	name_label.text = info.name
	name_label.theme_type_variation = &"StatLabel"
	name_label.add_theme_font_size_override("font_size", 15)
	text_box.add_child(name_label)
	var desc := Label.new()
	desc.text = info.desc
	desc.theme_type_variation = &"DimLabel"
	desc.add_theme_font_size_override("font_size", 13)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_box.add_child(desc)
	row.add_child(text_box)

	var value := Label.new()
	value.text = str(p.attributes.get(attr_name, 0))
	value.theme_type_variation = &"TitleLabel"
	value.add_theme_font_size_override("font_size", 22)
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(value)

	var plus := Button.new()
	plus.icon = Palette.icon("plus")
	plus.theme_type_variation = &"AccentButton"
	plus.tooltip_text = "Вложить очко атрибутов"
	plus.disabled = p.attribute_points <= 0
	plus.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plus.set_meta("sfx", "")
	plus.pressed.connect(_on_increase_attribute.bind(attr_name))
	row.add_child(plus)
	return panel


func _on_increase_attribute(attr_name: String) -> void:
	if GameManager.increase_attribute(attr_name):
		SaveSystem.save_all()
		Audio.play("confirm")


func _refresh_knowledge() -> void:
	for child in spec_list.get_children():
		child.queue_free()
	for spec_id in ContentParser.get_all_spec_ids():
		var color := ContentParser.get_spec_color(spec_id)
		var learned := GameManager.count_learned(spec_id)
		var total := ContentParser.count_nodes(spec_id)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 4)
		var head := HBoxContainer.new()
		var btn := Button.new()
		btn.theme_type_variation = &"GhostButton"
		btn.text = ContentParser.get_spec_name(spec_id)
		btn.add_theme_color_override("font_color", color.lightened(0.2))
		btn.add_theme_color_override("font_hover_color", color.lightened(0.4))
		btn.tooltip_text = "Открыть дерево"
		btn.pressed.connect(func(): EventBus.go("mini_tree", {"spec_id": spec_id}))
		head.add_child(btn)
		var spacer := Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		head.add_child(spacer)
		var count := Label.new()
		count.text = "%d / %d" % [learned, total]
		count.theme_type_variation = &"MonoLabel"
		count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(count)
		box.add_child(head)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 8
		bar.max_value = maxi(total, 1)
		bar.value = learned
		bar.add_theme_stylebox_override("fill", Palette.box(color, Color.TRANSPARENT, 0, 6, 0, 0))
		box.add_child(bar)
		spec_list.add_child(box)


# ---------------------------------------------------------------- Карты

const CARD_SCENE := preload("res://scenes/combat/CardVisual.tscn")
const GRID_CARD_SCALE := 0.72

var _rarity_filter: OptionButton
var _spec_filter: OptionButton
var _show_locked: CheckBox
var _chest_btn: Button


func _build_cards_bar() -> void:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	var cards_tab := cards_info.get_parent()
	cards_tab.add_child(bar)
	cards_tab.move_child(bar, 0)

	_rarity_filter = OptionButton.new()
	_rarity_filter.add_item("Все редкости")
	_rarity_filter.set_item_metadata(0, "")
	for r in ["legendary", "rare", "uncommon", "common"]:
		_rarity_filter.add_item(CardDatabase.RARITY_NAMES[r])
		_rarity_filter.set_item_metadata(_rarity_filter.item_count - 1, r)
	_rarity_filter.item_selected.connect(func(_i): _refresh_card_collection())
	bar.add_child(_rarity_filter)

	_spec_filter = OptionButton.new()
	_spec_filter.add_item("Все специализации")
	_spec_filter.set_item_metadata(0, "")
	for spec_id in ContentParser.get_all_spec_ids():
		_spec_filter.add_item(ContentParser.get_spec_name(spec_id))
		_spec_filter.set_item_metadata(_spec_filter.item_count - 1, spec_id)
	_spec_filter.item_selected.connect(func(_i): _refresh_card_collection())
	bar.add_child(_spec_filter)

	_show_locked = CheckBox.new()
	_show_locked.text = "Показать неполученные"
	_show_locked.button_pressed = true
	_show_locked.toggled.connect(func(_on): _refresh_card_collection())
	bar.add_child(_show_locked)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.add_child(spacer)

	_chest_btn = Button.new()
	_chest_btn.icon = Palette.game_icon("chest")
	_chest_btn.theme_type_variation = &"AccentButton"
	_chest_btn.add_theme_constant_override("icon_max_width", 22)
	_chest_btn.set_meta("sfx", "chest_creak")
	_chest_btn.pressed.connect(func(): EventBus.go("lootbox", {"overlay": true}))
	bar.add_child(_chest_btn)

	cards_grid.resized.connect(_update_grid_columns)
	cards_grid.get_parent().resized.connect(_update_grid_columns)


func _update_grid_columns() -> void:
	var w: float = cards_grid.get_parent().size.x
	var cell := CardVisualSize.x * GRID_CARD_SCALE + cards_grid.get_theme_constant("h_separation")
	cards_grid.columns = maxi(1, int((w + cards_grid.get_theme_constant("h_separation")) / cell))


const CardVisualSize := Vector2(200, 280)


func _refresh_card_collection() -> void:
	if _rarity_filter == null:
		_build_cards_bar()
	for child in cards_grid.get_children():
		child.queue_free()
	var catalog := CardDatabase.all_cards()
	var owned: Dictionary = GameManager.card_collection
	cards_info.text = "Уникальных карт: %d из %d  ·  всего в коллекции: %d  ·  колода: %d / %d" % [
		owned.size(), catalog.size(), GameManager.collection_size(), GameManager.combat_deck.size(), XPCalculator.MAX_DECK_SIZE]
	var boxes := GameManager.lootbox_count()
	_chest_btn.text = "Открыть сундук (%d)" % boxes
	_chest_btn.disabled = boxes <= 0
	_chest_btn.tooltip_text = "Сундуки даются за каждый новый уровень" if boxes <= 0 else "В сундуке — случайная карта"

	var rarity: String = _rarity_filter.get_item_metadata(_rarity_filter.selected)
	var spec: String = _spec_filter.get_item_metadata(_spec_filter.selected)
	var ids: Array = []
	for card in catalog:
		if rarity != "" and card.get("rarity", "") != rarity:
			continue
		if spec != "" and card.get("from_specialization", "") != spec:
			continue
		if not owned.has(card.id) and not _show_locked.button_pressed:
			continue
		ids.append(card.id)
	# Сначала полученные (по редкости), затем неполученные
	var have := CardDatabase.sort_by_rarity(ids.filter(func(i): return owned.has(i)))
	var missing := CardDatabase.sort_by_rarity(ids.filter(func(i): return not owned.has(i)))
	for card_id in have + missing:
		var cv := CARD_SCENE.instantiate()
		cv.card_scale = GRID_CARD_SCALE
		cards_grid.add_child(cv)
		var is_owned := owned.has(card_id)
		cv.setup(CardDatabase.get_card(card_id), int(owned.get(card_id, 0)), not is_owned)
		if is_owned:
			cv.clicked.connect(_show_card_detail)
	if ids.is_empty():
		var empty := Label.new()
		empty.text = "Нет карт по выбранным фильтрам."
		empty.theme_type_variation = &"DimLabel"
		cards_grid.add_child(empty)
	_update_grid_columns.call_deferred()


## Крупный просмотр карты поверх экрана.
func _show_card_detail(card_id: String) -> void:
	var card := CardDatabase.get_card(card_id)
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(center)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 36)
	center.add_child(row)
	var cv := CARD_SCENE.instantiate()
	cv.card_scale = 1.6
	cv.hover_lift = false
	row.add_child(cv)
	cv.setup(card, int(GameManager.card_collection.get(card_id, 0)))
	var info := VBoxContainer.new()
	info.custom_minimum_size.x = 360
	info.add_theme_constant_override("separation", 10)
	info.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(info)
	var rarity: String = card.get("rarity", "common")
	var name_label := Label.new()
	name_label.text = card.get("name", "")
	name_label.theme_type_variation = &"TitleLabel"
	name_label.add_theme_color_override("font_color", Palette.RARITY_COLORS.get(rarity, Palette.TEXT))
	info.add_child(name_label)
	var lines := [
		"%s · %s" % [CardDatabase.TYPE_NAMES.get(card.get("type", ""), ""), CardDatabase.RARITY_NAMES.get(rarity, rarity)],
		"Специализация: %s" % ContentParser.get_spec_name(card.get("from_specialization", "")),
		"Стоимость: %d кристалл(а)" % card.get("crystal_cost", 0),
		"В коллекции: ×%d" % int(GameManager.card_collection.get(card_id, 0)),
	]
	if card.get("type", "") == "creature":
		lines.insert(3, "Атака / защита: %d / %d" % [card.get("attack", 0), card.get("defense", 0)])
	for t in lines:
		var l := Label.new()
		l.text = t
		l.theme_type_variation = &"MonoLabel"
		info.add_child(l)
	var desc := Label.new()
	desc.text = card.get("description", "")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info.add_child(desc)
	var flavor := Label.new()
	flavor.text = "«%s»" % card.get("flavor_text", "")
	flavor.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	flavor.theme_type_variation = &"DimLabel"
	info.add_child(flavor)
	var hint := Label.new()
	hint.text = "Клик — закрыть"
	hint.theme_type_variation = &"DimLabel"
	info.add_child(hint)
	overlay.modulate.a = 0.0
	overlay.create_tween().tween_property(overlay, "modulate:a", 1.0, 0.2)
	Audio.play("card_flip")
	overlay.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed:
			overlay.queue_free())


var _deck_builder: Control


func _refresh_deck() -> void:
	if _deck_builder == null:
		deck_info.visible = false
		_deck_builder = preload("res://scenes/character/DeckBuilder.gd").new()
		_deck_builder.size_flags_vertical = Control.SIZE_EXPAND_FILL
		deck_info.get_parent().add_child(_deck_builder)
	else:
		_deck_builder.refresh()


# ---------------------------------------------------------------- Сброс игры

func _confirm_wipe() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = "Начать заново?"
	dialog.dialog_text = "Будут удалены уровень, опыт, прогресс знаний, карты и заметки для Claude.\nЭто действие нельзя отменить."
	dialog.ok_button_text = "Удалить всё"
	dialog.cancel_button_text = "Отмена"
	dialog.confirmed.connect(func():
		if not GameManager.claude_notes.is_empty():
			ClaudeNotesExporter.export_all()  # заметки не теряются: остаются в NOTES_FOR_CLAUDE.md
		SaveSystem.wipe()
		EventBus.notify("Прогресс сброшен. Новое начало!", "warning")
		EventBus.navigate_home.emit())
	add_child(dialog)
	dialog.popup_centered()
