extends HBoxContainer
## Вкладка «Снаряжение»: кукла героя (3D-превью) со слотами экипировки и инвентарь.
## Клик по предмету в инвентаре — надеть (ПКМ по кинжалу — во вторую руку), клик по слоту — снять.
## Ограничений по весу и объёму у инвентаря нет.

const LEFT_SLOTS := ["head", "shoulders", "chest", "hands", "legs"]
const RIGHT_SLOTS := ["feet", "weapon", "offhand", "ring", "amulet"]

var _left: VBoxContainer
var _right: VBoxContainer
var _preview: HeroPreview
var _summary: RichTextLabel
var _grid: GridContainer
var _inv_title: Label


func _ready() -> void:
	add_theme_constant_override("separation", 14)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	var doll := PanelContainer.new()
	doll.theme_type_variation = &"CardPanel"
	doll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doll.size_flags_stretch_ratio = 1.15
	add_child(doll)
	var doll_row := HBoxContainer.new()
	doll_row.add_theme_constant_override("separation", 8)
	doll.add_child(doll_row)
	_left = VBoxContainer.new()
	_left.add_theme_constant_override("separation", 8)
	_left.alignment = BoxContainer.ALIGNMENT_CENTER
	doll_row.add_child(_left)
	var mid := VBoxContainer.new()
	mid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	doll_row.add_child(mid)
	_preview = HeroPreview.new()
	_preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_preview.custom_minimum_size = Vector2(200, 300)
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

	var inv := PanelContainer.new()
	inv.theme_type_variation = &"CardPanel"
	inv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(inv)
	var inv_box := VBoxContainer.new()
	inv_box.add_theme_constant_override("separation", 10)
	inv.add_child(inv_box)
	var head := HBoxContainer.new()
	inv_box.add_child(head)
	_inv_title = Label.new()
	_inv_title.theme_type_variation = &"HeaderLabel"
	_inv_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(_inv_title)
	var shop := Button.new()
	shop.text = "В лавку"
	shop.icon = Palette.game_icon("shop")
	shop.add_theme_constant_override("icon_max_width", 20)
	shop.pressed.connect(func(): EventBus.go("shop"))
	head.add_child(shop)
	var hint := Label.new()
	hint.text = "Клик — надеть, клик по слоту — снять. ПКМ по кинжалу — во вторую руку."
	hint.theme_type_variation = &"DimLabel"
	hint.add_theme_font_size_override("font_size", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inv_box.add_child(hint)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	inv_box.add_child(scroll)
	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 6)
	scroll.add_child(margin)
	_grid = GridContainer.new()
	_grid.columns = 3
	_grid.add_theme_constant_override("h_separation", 10)
	_grid.add_theme_constant_override("v_separation", 10)
	margin.add_child(_grid)
	scroll.resized.connect(func(): _grid.columns = maxi(1, int((scroll.size.x - 12) / 142.0)))
	GameManager.equipment_changed.connect(refresh)
	refresh()


func refresh() -> void:
	if not is_inside_tree():
		return
	for box in [_left, _right]:
		for c in box.get_children():
			c.queue_free()
	for slot in LEFT_SLOTS:
		_left.add_child(_slot_tile(slot))
	for slot in RIGHT_SLOTS:
		_right.add_child(_slot_tile(slot))
	_preview.show_player()
	_refresh_summary()
	for c in _grid.get_children():
		c.queue_free()
	var inv: Array = GameManager.player_data.inventory.duplicate()
	inv.sort_custom(func(a, b):
		var ia := ItemDatabase.get_item(a)
		var ib := ItemDatabase.get_item(b)
		return [ia.get("slot", ""), -int(ia.get("level", 1))] < [ib.get("slot", ""), -int(ib.get("level", 1))])
	_inv_title.text = Loc.t("Инвентарь (%d)") % inv.size()
	if inv.is_empty():
		var empty := Label.new()
		empty.text = "Инвентарь пуст. Снаряжение продаётся в лавке и попадается в сундуках вылазок."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.custom_minimum_size.x = 300
		empty.theme_type_variation = &"DimLabel"
		_grid.add_child(empty)
	for id in inv:
		var it := ItemDatabase.get_item(id)
		var tile := ItemTile.make(it, Loc.t(ItemDatabase.SLOTS.get(it.get("slot", ""), {}).get("name", "")), Vector2(132, 132))
		tile.gui_input.connect(_on_inventory_input.bind(id))
		tile.mouse_entered.connect(func(): _preview.try_item(it))
		tile.mouse_exited.connect(func(): _preview.show_player())
		_grid.add_child(tile)


func _slot_tile(slot: String) -> ItemTile:
	var it := ItemDatabase.get_item(GameManager.equipped(slot))
	var tile := ItemTile.make_row(it, slot, Vector2(176, 62))
	if not it.is_empty():
		tile.pressed.connect(func():
			GameManager.unequip(slot)
			Audio.play("cloth"))
	return tile


func _on_inventory_input(event: InputEvent, id: String) -> void:
	if not (event is InputEventMouseButton and event.pressed):
		return
	var it := ItemDatabase.get_item(id)
	var slot := ""
	if event.button_index == MOUSE_BUTTON_RIGHT and it.get("offhand_ok", false):
		slot = "offhand"
	elif event.button_index != MOUSE_BUTTON_LEFT:
		return
	if GameManager.equip(id, slot):
		Audio.play("cloth")


func _refresh_summary() -> void:
	var eq := GameManager.equipment_stats()
	var attrs := GameManager.effective_attributes()
	var weapons: PackedStringArray = []
	for w in GameManager.combat_weapons():
		weapons.append(Loc.t(XPCalculator.WEAPONS[w].name))
	_summary.text = "[center]%s: [b]%s[/b]\n%s [color=#F5C542]%d[/color] · %s [color=#FF8A8A]%d[/color] · %s [color=#7FDBFF]%d[/color] · %s [color=#00D4AA]%d%%[/color][/center]" % [
		Loc.t("Атаки в бою"), ", ".join(weapons),
		Loc.t("Броня"), int(eq.get("armor", 0)), Loc.t("Урон"), int(eq.get("damage", 0)),
		Loc.t("HP"), GameManager.player_data.max_hp,
		Loc.t("Уклонение"), XPCalculator.dodge_chance(attrs.get("agility", 0), int(eq.get("dodge", 0)))]
