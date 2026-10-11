extends PanelContainer
## Существо на поле боя: иконка, имя, атака/защита, статусы (Taunt, заморожен, может атаковать).

signal clicked(token)

var data: Dictionary = {}
var side: String = "player"
var highlighted := false

var _icon: TextureRect
var _name: Label
var _atk: Label
var _def: Label
var _status: Label


func _init() -> void:
	custom_minimum_size = Vector2(104, 116)
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	pivot_offset = Vector2(52, 58)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(box)
	_status = Label.new()
	_status.add_theme_font_size_override("font_size", 10)
	_status.add_theme_font_override("font", Palette.FONT_UI_BOLD)
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_status)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(0, 40)
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_icon)
	_name = Label.new()
	_name.add_theme_font_size_override("font_size", 11)
	_name.add_theme_font_override("font", Palette.FONT_TEXT_SEMI)
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name.clip_text = true
	_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_name)
	var stats := HBoxContainer.new()
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(stats)
	_atk = _stat(stats, "broadsword", Color("#E8A33D"))
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats.add_child(sp)
	_def = _stat(stats, "roman-shield", Color("#6FB3FF"))


func _stat(parent: Control, icon_name: String, color: Color) -> Label:
	var ic := TextureRect.new()
	ic.texture = Palette.game_icon(icon_name)
	ic.custom_minimum_size = Vector2(16, 16)
	ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	ic.modulate = color
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(ic)
	var l := Label.new()
	l.add_theme_font_override("font", Palette.FONT_UI_BOLD)
	l.add_theme_font_size_override("font_size", 16)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func setup(creature: Dictionary, owner_side: String) -> void:
	data = creature
	side = owner_side
	var color := Color.from_string(creature.get("art_color", "#7B68EE"), Palette.ACCENT)
	_icon.texture = Palette.game_icon(creature.get("icon", "cog"))
	_icon.modulate = color.lightened(0.35)
	_name.text = creature.get("name", "?")
	_atk.text = str(creature.get("attack", 0))
	_def.text = str(creature.get("defense", 0))
	_def.add_theme_color_override("font_color", Palette.HP if creature.defense < creature.get("max_defense", creature.defense) else Palette.TEXT)
	var tags: PackedStringArray = []
	if creature.get("taunt", false):
		tags.append("TAUNT")
	if creature.get("frozen", 0) > 0:
		tags.append("❄ %d" % creature.frozen)
	if creature.get("divine_shield", false):
		tags.append("ЩИТ")
	if creature.get("controlled", 0) > 0:
		tags.append("ПОД КОНТРОЛЕМ")
	_status.text = " · ".join(tags) if not tags.is_empty() else " "
	_status.add_theme_color_override("font_color", Palette.ENERGY)
	tooltip_text = _tooltip()
	refresh_style()


func refresh_style() -> void:
	var color := Color.from_string(data.get("art_color", "#7B68EE"), Palette.ACCENT)
	var border := Color(color, 0.6)
	var glow := Color(0, 0, 0, 0)
	var bw := 1
	if data.get("taunt", false):
		border = Color("#C8D0DC")
		bw = 3
	if data.get("divine_shield", false):
		border = Palette.GOLD
		bw = 3
	if side == "player" and data.get("can_attack", false) and data.get("frozen", 0) <= 0 and data.get("attack", 0) > 0:
		glow = Color(Palette.MINT, 0.45)
		border = Palette.MINT
	if highlighted:
		glow = Color(Palette.HP if side == "enemy" else Palette.ENERGY, 0.6)
		border = Palette.HP if side == "enemy" else Palette.ENERGY
		bw = 3
	var sb := Palette.box(Color("#15142B").lerp(color, 0.15), border, bw, 10, 6, 6)
	sb.shadow_color = glow
	sb.shadow_size = 10 if glow.a > 0 else 0
	add_theme_stylebox_override("panel", sb)
	modulate = Color(0.75, 0.85, 1.2) if data.get("frozen", 0) > 0 else Color.WHITE


func set_highlight(on: bool) -> void:
	highlighted = on
	refresh_style()


func _tooltip() -> String:
	var card: Dictionary = data.get("card", {})
	var text := "%s — %d/%d" % [data.get("name", ""), data.get("attack", 0), data.get("defense", 0)]
	if card.get("description", "") != "":
		text += "\n" + card.description
	return text


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		clicked.emit(self)
		accept_event()
