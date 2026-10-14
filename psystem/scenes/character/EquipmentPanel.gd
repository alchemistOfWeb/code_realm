extends HBoxContainer
## Снаряжение героя: кукла (3D-превью) со слотами, инвентарь и — на базе — склад.
## Всё перекладывается перетаскиванием (drag and drop): предмет из инвентаря или со склада — в слот
## (надеть, старый предмет уходит туда, откуда взят новый), из слота — в инвентарь или на склад (снять),
## между инвентарём и складом — переложить. В вылазке вместо склада — зона «Выбросить».
## Число слотов инвентаря не ограничено, но переносимый вес (надетое + инвентарь) зависит от выносливости.

const LEFT_SLOTS := ["head", "shoulders", "chest", "hands", "legs"]
const RIGHT_SLOTS := ["feet", "weapon", "offhand", "ring", "amulet"]
const TILE := Vector2(112, 112)

## "base" — экран персонажа на базе (склад, кнопка лавки), "sortie" — инвентарь в вылазке (зона «Выбросить»).
var mode := "base"

var _left: VBoxContainer
var _right: VBoxContainer
var _slot_tiles: Dictionary = {}     # slot → ItemTile
var _preview: HeroPreview
var _summary: RichTextLabel
var _weight_bar: ProgressBar
var _weight_label: Label
var _inv_grid: GridContainer
var _inv_title: Label
var _stash_grid: GridContainer
var _stash_title: Label
var _drop_zone: PanelContainer


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	_build_doll()
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 12)
	add_child(col)
	var inv := _grid_panel(col, "inventory")
	_inv_title = inv[0]
	_inv_grid = inv[1]
	if mode == "base":
		var shop := Button.new()
		shop.text = Loc.t("В лавку")
		shop.icon = Palette.game_icon("shop")
		shop.add_theme_constant_override("icon_max_width", 20)
		shop.pressed.connect(func(): EventBus.go("shop"))
		_inv_title.get_parent().add_child(shop)
		var stash := _grid_panel(col, "stash")
		_stash_title = stash[0]
		_stash_grid = stash[1]
		_build_drop_zone(col, "sell")
	else:
		_build_drop_zone(col, "drop")
	GameManager.equipment_changed.connect(refresh)
	refresh()


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_DRAG_BEGIN:
			var data = get_viewport().gui_get_drag_data()
			if data is Dictionary and data.get("type") == "item":
				_highlight_slots(ItemDatabase.get_item(data.id))
		NOTIFICATION_DRAG_END:
			_highlight_slots({})


# ---------------------------------------------------------------- Построение

func _build_doll() -> void:
	var doll := PanelContainer.new()
	doll.theme_type_variation = &"CardPanel"
	doll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doll.size_flags_stretch_ratio = 1.1
	add_child(doll)
	var doll_col := VBoxContainer.new()
	doll_col.add_theme_constant_override("separation", 8)
	doll.add_child(doll_col)
	var doll_row := HBoxContainer.new()
	doll_row.add_theme_constant_override("separation", 8)
	doll_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	doll_col.add_child(doll_row)
	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 8)
	_left.alignment = BoxContainer.ALIGNMENT_CENTER
	doll_row.add_child(_left)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doll_row.add_child(mid)
	_preview = HeroPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(180, 260)
	mid.add_child(_preview)
	_summary = RichTextLabel.new()
	_summary.bbcode_enabled = true
	_summary.fit_content = true
	_summary.add_theme_font_size_override("normal_font_size", 13)
	mid.add_child(_summary)
	_right = VBoxContainer.new()
	_right.add_theme_constant_override("separation", 8)
	_right.alignment = BoxContainer.ALIGNMENT_CENTER
	doll_row.add_child(_right)
	for slot in LEFT_SLOTS + RIGHT_SLOTS:
		var holder := Control.new()
		holder.custom_minimum_size = Vector2(176, 62)
		(_left if slot in LEFT_SLOTS else _right).add_child(holder)
		holder.set_meta("slot", slot)
		_slot_tiles[slot] = holder
	# Переносимый вес
	var wrow := HBoxContainer.new()
	wrow.add_theme_constant_override("separation", 8)
	doll_col.add_child(wrow)
	var wicon := TextureRect.new()
	wicon.texture = Palette.game_icon("weight")
	wicon.custom_minimum_size = Vector2(20, 20)
	wicon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	wicon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	wicon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrow.add_child(wicon)
	_weight_bar = ProgressBar.new()
	_weight_bar.show_percentage = false
	_weight_bar.custom_minimum_size = Vector2(120, 10)
	_weight_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_weight_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	wrow.add_child(_weight_bar)
	_weight_label = Label.new()
	_weight_label.theme_type_variation = &"MonoLabel"
	_weight_label.add_theme_font_size_override("font_size", 12)
	_weight_label.tooltip_text = Loc.t("Переносимый вес: надетое снаряжение и инвентарь (склад не считается). Зависит от выносливости. При перегрузе в вылазке — медленный шаг и нельзя бежать.")
	_weight_label.mouse_filter = Control.MOUSE_FILTER_PASS
	wrow.add_child(_weight_label)


## Панель с сеткой предметов: inventory | stash. Возвращает [заголовок, сетка].
func _grid_panel(parent: Control, kind: String) -> Array:
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	panel.add_child(box)
	var head := HBoxContainer.new()
	box.add_child(head)
	var title := Label.new()
	title.theme_type_variation = &"HeaderLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var hint := Label.new()
	hint.text = Loc.t("Перетащи предмет в слот героя, чтобы надеть; из слота — сюда, чтобы снять.") if kind == "inventory" \
		else Loc.t("Склад базы: вещи здесь не утяжеляют героя. Перетаскивай предметы между инвентарём и складом.")
	hint.theme_type_variation = &"DimLabel"
	hint.add_theme_font_size_override("font_size", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = TILE.y + 16
	box.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.size_flags_vertical = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	scroll.add_child(margin)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	margin.add_child(grid)
	scroll.resized.connect(func(): grid.columns = maxi(1, int((scroll.size.x - 12) / (TILE.x + 8))))
	# Бросить предмет можно на всю панель, а не только на плитки
	for c in [panel, scroll, margin, grid]:
		c.set_drag_forwarding(_no_drag, _can_drop_list.bind(kind), _drop_list.bind(kind))
	return [title, grid]


## Зона сброса: "drop" — выбросить (в вылазке), "sell" — продать за полцены (на базе).
func _build_drop_zone(parent: Control, kind: String) -> void:
	var color: Color = Palette.HP if kind == "drop" else Palette.GOLD
	_drop_zone = PanelContainer.new()
	_drop_zone.add_theme_stylebox_override("panel", Palette.box(Color(color.darkened(0.8), 0.6), Color(color, 0.6), 2, 10, 12, 12))
	_drop_zone.custom_minimum_size.y = 64 if kind == "drop" else 40
	parent.add_child(_drop_zone)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_drop_zone.add_child(row)
	var icon := TextureRect.new()
	icon.texture = Palette.icon("x") if kind == "drop" else Palette.icon("coins")
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.modulate = color
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var l := Label.new()
	l.text = Loc.t("Выбросить: перетащи сюда предмет, чтобы избавиться от перегруза") if kind == "drop" else Loc.t("Продать за ½ цены: перетащи сюда вещь (из инвентаря, со склада или с героя)")
	l.add_theme_color_override("font_color", color.lightened(0.3))
	l.add_theme_font_size_override("font_size", 13 if kind == "sell" else 16)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	_drop_zone.set_drag_forwarding(_no_drag, _can_drop_list.bind(kind), _drop_list.bind(kind))


# ---------------------------------------------------------------- Обновление

func refresh() -> void:
	if not is_inside_tree():
		return
	for slot in _slot_tiles:
		var holder: Control = _slot_tiles[slot]
		for c in holder.get_children():
			c.queue_free()
		holder.add_child(_slot_tile(slot))
	_preview.show_player()
	_refresh_summary()
	_inv_title.text = Loc.t("Инвентарь (%d)") % GameManager.player_data.inventory.size()
	_fill(_inv_grid, "inventory", Loc.t("Инвентарь пуст. Снаряжение продаётся в лавке и попадается в сундуках вылазок."))
	if _stash_grid:
		_stash_title.text = Loc.t("Склад (%d)") % GameManager.player_data.stash.size()
		_fill(_stash_grid, "stash", Loc.t("Склад пуст. Перетащи сюда лишние вещи из инвентаря."))
	var w := GameManager.carried_weight()
	var cap := GameManager.carry_capacity()
	var over := GameManager.is_overloaded()
	_weight_bar.max_value = cap
	_weight_bar.value = minf(w, cap)
	_weight_bar.add_theme_stylebox_override("fill", Palette.box(Palette.HP if over else Palette.MINT, Color.TRANSPARENT, 0, 4, 0, 0))
	_weight_label.text = Loc.t("Вес %s / %s кг") % [ItemDatabase.format_weight(w), ItemDatabase.format_weight(cap)] + ("  · " + Loc.t("перегруз!") if over else "")
	_weight_label.add_theme_color_override("font_color", Palette.HP if over else Palette.TEXT)


func _fill(grid: GridContainer, kind: String, empty_text: String) -> void:
	for c in grid.get_children():
		c.queue_free()
	var list: Array = GameManager.player_data[kind].duplicate()
	list.sort_custom(func(a, b):
		var ia := ItemDatabase.get_item(a)
		var ib := ItemDatabase.get_item(b)
		return [ia.get("slot", ""), -int(ia.get("level", 1)), String(a)] < [ib.get("slot", ""), -int(ib.get("level", 1)), String(b)])
	if list.is_empty():
		var empty := Label.new()
		empty.text = empty_text
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.x = 260
		empty.theme_type_variation = &"DimLabel"
		empty.mouse_filter = Control.MOUSE_FILTER_PASS
		empty.set_drag_forwarding(_no_drag, _can_drop_list.bind(kind), _drop_list.bind(kind))
		grid.add_child(empty)
	for id in list:
		var it := ItemDatabase.get_item(id)
		var sub := "%s · %s %s" % [Loc.t(ItemDatabase.SLOTS.get(it.get("slot", ""), {}).get("name", "")), ItemDatabase.format_weight(ItemDatabase.weight(it)), Loc.t("кг")]
		var tile := ItemTile.make(it, sub, TILE)
		tile.set_drag_forwarding(_drag_item.bind(id, kind, ""), _can_drop_list.bind(kind), _drop_list.bind(kind))
		tile.mouse_entered.connect(func(): _preview.try_item(it))
		tile.mouse_exited.connect(func(): _preview.show_player())
		grid.add_child(tile)


func _slot_tile(slot: String) -> ItemTile:
	var id := GameManager.equipped(slot)
	var it := ItemDatabase.get_item(id)
	var weapon := ItemDatabase.get_item(GameManager.equipped("weapon"))
	if slot == "offhand" and id == "" and ItemDatabase.is_two_handed(weapon):
		# Вторая рука занята двуручным оружием: показываем его бледной тенью
		var ghost := ItemTile.make_row(weapon, "weapon", Vector2(176, 62))
		ghost.modulate = Color(1, 1, 1, 0.45)
		ghost.tooltip_text = Loc.t("Вторая рука занята двуручным оружием")
		ghost.set_drag_forwarding(_drag_item.bind(weapon.id, "slot", "weapon"), _can_drop_slot.bind(slot), _drop_slot.bind(slot))
		return ghost
	var tile := ItemTile.make_row(it, slot, Vector2(176, 62))
	tile.set_drag_forwarding(_drag_item.bind(id, "slot", slot), _can_drop_slot.bind(slot), _drop_slot.bind(slot))
	return tile


func _highlight_slots(item: Dictionary) -> void:
	for slot in _slot_tiles:
		var holder: Control = _slot_tiles[slot]
		holder.modulate = Color(1.25, 1.2, 0.75) if not item.is_empty() and ItemDatabase.fits(item, slot) else Color.WHITE


# ---------------------------------------------------------------- Drag and drop

## Пустой Callable в set_drag_forwarding отключает и приём перетаскивания — поэтому заглушка.
func _no_drag(_at: Vector2) -> Variant:
	return null


func _drag_item(_at: Vector2, id: String, from: String, slot: String) -> Variant:
	if id == "":
		return null
	var it := ItemDatabase.get_item(id)
	# Сначала режим растяжения, потом размер: иначе минимальный размер — вся текстура рендера
	var icon := TextureRect.new()
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture = ItemDatabase.icon(it)
	icon.custom_minimum_size = Vector2(44, 44)
	icon.size = Vector2(44, 44)
	icon.modulate = Color(1, 1, 1, 0.9)
	var holder := Control.new()
	holder.add_child(icon)
	icon.position = -Vector2(22, 22)
	set_drag_preview(holder)
	Audio.play("select")
	return {"type": "item", "id": id, "from": from, "slot": slot}


func _can_drop_slot(_at: Vector2, data: Variant, slot: String) -> bool:
	if not (data is Dictionary and data.get("type") == "item"):
		return false
	if data.from == "slot" and data.slot == slot:
		return false
	return ItemDatabase.fits(ItemDatabase.get_item(data.id), slot)


func _drop_slot(_at: Vector2, data: Variant, slot: String) -> void:
	var ok := false
	if data.from == "slot":
		# Кинжал из основной руки во вторую и обратно
		GameManager.unequip(data.slot)
		ok = GameManager.equip(data.id, slot)
	else:
		ok = GameManager.equip(data.id, slot, data.from)
	if ok:
		Audio.play("cloth")


func _can_drop_list(_at: Vector2, data: Variant, kind: String) -> bool:
	if not (data is Dictionary and data.get("type") == "item"):
		return false
	if kind == "drop":
		return data.from in ["inventory", "slot"]
	if kind == "sell":
		return ItemDatabase.sell_price(ItemDatabase.get_item(data.id)) > 0
	return data.from != kind


func _drop_list(_at: Vector2, data: Variant, kind: String) -> void:
	var it := ItemDatabase.get_item(data.id)
	if kind == "sell":
		_confirm_sell(data, it)
		return
	if kind == "drop":
		if data.from == "slot":
			GameManager.unequip(data.slot)
		GameManager.drop_item(data.id)
		Audio.play("drop")
		EventBus.notify(Loc.t("Выброшено: %s") % it.get("name", ""), "info")
		return
	if data.from == "slot":
		GameManager.unequip(data.slot, kind)
	else:
		GameManager.move_item(data.id, data.from, kind)
	Audio.play("cloth")


func _confirm_sell(data: Dictionary, it: Dictionary) -> void:
	var price := ItemDatabase.sell_price(it)
	var dialog := ConfirmationDialog.new()
	dialog.title = Loc.t("Продать предмет?")
	dialog.dialog_text = Loc.t("Продать «%s» за %d золота?") % [it.get("name", ""), price]
	dialog.ok_button_text = Loc.t("Продать")
	dialog.cancel_button_text = Loc.t("Отмена")
	dialog.confirmed.connect(func():
		var source: String = data.from
		if source == "slot":
			GameManager.unequip(data.slot, "inventory")
			source = "inventory"
		var gold := GameManager.sell_item(data.id, source)
		if gold > 0:
			Audio.play("coins")
			EventBus.notify(Loc.t("Продано: %s (+%d золота)") % [it.get("name", ""), gold], "success"))
	dialog.close_requested.connect(dialog.queue_free)
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered()


func _refresh_summary() -> void:
	var eq := GameManager.equipment_stats()
	var attrs := GameManager.effective_attributes()
	var weapons: PackedStringArray = []
	for w in GameManager.combat_weapons():
		weapons.append(Loc.t(XPCalculator.WEAPONS[w].name))
	_summary.text = "[center]%s: [b]%s[/b]\n%s [color=#F5C542]%d[/color] · %s [color=#FF8A8A]%d[/color] · %s [color=#7FDBFF]%d[/color] · %s [color=#00D4AA]%s[/color][/center]" % [
		Loc.t("Атаки в бою"), ", ".join(weapons),
		Loc.t("Броня"), int(eq.get("armor", 0)), Loc.t("Урон"), int(eq.get("damage", 0)),
		Loc.t("HP"), GameManager.player_data.max_hp,
		Loc.t("Уклонение"), XPCalculator.format_percent(XPCalculator.dodge_chance(attrs.get("agility", 0), int(eq.get("dodge", 0))))]
