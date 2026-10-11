class_name ItemTile
extends Button
## Плитка предмета: иконка, название, подпись (цена / слот), рамка цвета уровня, подсказка с характеристиками.

var item: Dictionary = {}
var _sub_label: Label


static func make(it: Dictionary, sub_text: String = "", tile_size: Vector2 = Vector2(150, 150)) -> ItemTile:
	var t := ItemTile.new()
	t.item = it
	t.custom_minimum_size = tile_size
	t._build(sub_text)
	return t


## Горизонтальная плитка надетого предмета (иконка слева, название и главный бонус справа).
static func make_row(it: Dictionary, slot: String, tile_size: Vector2 = Vector2(190, 64)) -> ItemTile:
	if it.is_empty():
		return empty_slot(slot, tile_size)
	var t := ItemTile.new()
	t.item = it
	t.custom_minimum_size = tile_size
	t.set_meta("slot", slot)
	t.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var tier := ItemDatabase.tier_color(it)
	t._style(tier)
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 8
	row.offset_right = -6
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	t.add_child(row)
	var icon_rect := TextureRect.new()
	icon_rect.texture = ItemDatabase.icon(it)
	icon_rect.custom_minimum_size = Vector2(44, 44)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not ResourceLoader.exists(ItemDatabase.RENDER_DIR + String(it.get("id", "")) + ".png"):
		icon_rect.modulate = tier.lightened(0.35)
	row.add_child(icon_rect)
	var col := VBoxContainer.new()
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	var name_label := Label.new()
	name_label.text = it.get("name", "")
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", tier.lightened(0.45))
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_label)
	var lines := ItemDatabase.stat_lines(it)
	var sub := Label.new()
	sub.text = lines[0] if not lines.is_empty() else Loc.t(ItemDatabase.SLOTS.get(slot, {}).get("name", ""))
	sub.theme_type_variation = &"DimLabel"
	sub.add_theme_font_size_override("font_size", 11)
	sub.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	sub.clip_text = true
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(sub)
	t.tooltip_text = " "
	return t


## Пустой слот экипировки.
static func empty_slot(slot: String, tile_size: Vector2 = Vector2(150, 64)) -> ItemTile:
	var t := ItemTile.new()
	t.custom_minimum_size = tile_size
	t.set_meta("slot", slot)
	t._build_empty(slot)
	return t


func _build(sub_text: String) -> void:
	auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var tier := ItemDatabase.tier_color(item)
	_style(tier)
	var box := VBoxContainer.new()
	box.set_anchors_preset(Control.PRESET_FULL_RECT)
	box.offset_left = 8
	box.offset_right = -8
	box.offset_top = 8
	box.offset_bottom = -6
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 2)
	add_child(box)
	var icon_rect := TextureRect.new()
	icon_rect.texture = ItemDatabase.icon(item)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if not ResourceLoader.exists(ItemDatabase.RENDER_DIR + String(item.get("id", "")) + ".png"):
		icon_rect.modulate = tier.lightened(0.35)
	box.add_child(icon_rect)
	var name_label := Label.new()
	name_label.text = item.get("name", "")
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", tier.lightened(0.45))
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(name_label)
	if sub_text != "":
		_sub_label = Label.new()
		_sub_label.text = sub_text
		_sub_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_sub_label.theme_type_variation = &"MonoLabel"
		_sub_label.add_theme_font_size_override("font_size", 12)
		_sub_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		box.add_child(_sub_label)
	tooltip_text = " "   # непустая — чтобы вызвался _make_custom_tooltip


func set_sub(text: String, color: Color = Palette.TEXT) -> void:
	if _sub_label:
		_sub_label.text = text
		_sub_label.add_theme_color_override("font_color", color)


func _build_empty(slot: String) -> void:
	_style(Color(1, 1, 1, 0.15))
	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -8
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	var icon_rect := TextureRect.new()
	icon_rect.texture = Palette.game_icon(ItemDatabase.SLOTS[slot].icon)
	icon_rect.custom_minimum_size = Vector2(30, 30)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon_rect.modulate = Color(1, 1, 1, 0.3)
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon_rect)
	var l := Label.new()
	l.text = ItemDatabase.SLOTS[slot].name
	l.theme_type_variation = &"DimLabel"
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(l)
	tooltip_text = Loc.t("Пустой слот: %s") % Loc.t(ItemDatabase.SLOTS[slot].name)


func _style(border: Color) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#14132A", 0.92)
	sb.border_color = Color(border, 0.75)
	sb.set_border_width_all(2)
	sb.set_corner_radius_all(10)
	var hover := sb.duplicate()
	hover.bg_color = Color("#1E1C3C", 0.95)
	hover.border_color = border.lightened(0.3)
	hover.shadow_color = Color(border, 0.35)
	hover.shadow_size = 8
	var pressed := hover.duplicate()
	pressed.bg_color = Color("#262350")
	add_theme_stylebox_override("normal", sb)
	add_theme_stylebox_override("hover", hover)
	add_theme_stylebox_override("pressed", pressed)
	add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	add_theme_stylebox_override("disabled", sb)


func _make_custom_tooltip(_for_text: String) -> Object:
	if item.is_empty():
		return null
	return ItemTile.tooltip_for(item)


static func tooltip_for(it: Dictionary) -> Control:
	var panel := PanelContainer.new()
	var tier := ItemDatabase.tier_color(it)
	panel.add_theme_stylebox_override("panel", Palette.glow_box(Color("#0E0D1C", 0.97), tier, Color(tier, 0.25), 10, 10))
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 260
	box.add_theme_constant_override("separation", 4)
	panel.add_child(box)
	var title := Label.new()
	title.text = it.get("name", "")
	title.add_theme_font_override("font", Palette.FONT_UI_BOLD)
	title.add_theme_color_override("font_color", tier.lightened(0.4))
	box.add_child(title)
	var slot_label := Label.new()
	slot_label.text = "%s · %s %d" % [Loc.t(ItemDatabase.SLOTS.get(it.get("slot", ""), {}).get("name", "")), Loc.t("ур."), int(it.get("level", 1))]
	slot_label.theme_type_variation = &"DimLabel"
	slot_label.add_theme_font_size_override("font_size", 12)
	box.add_child(slot_label)
	for line in ItemDatabase.stat_lines(it):
		var l := Label.new()
		l.text = line
		l.add_theme_color_override("font_color", Palette.MINT if line.begins_with("+") else (Palette.HP if line.begins_with("-") else Palette.TEXT))
		box.add_child(l)
	var desc := Label.new()
	desc.text = it.get("desc", "")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 260
	desc.theme_type_variation = &"DimLabel"
	desc.add_theme_font_size_override("font_size", 12)
	box.add_child(desc)
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	return panel
