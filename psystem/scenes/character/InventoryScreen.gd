extends Control
## Инвентарь в вылазке (клавиша I): кукла героя, инвентарь, перетаскивание снаряжения, вес, зона «Выбросить».
## Открывается оверлеем поверх мира (мир на паузе). I или Esc — закрыть.


func setup(_params: Dictionary) -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.02, 0.06, 0.93)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 40)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var icon := TextureRect.new()
	icon.texture = Palette.game_icon("backpack")
	icon.custom_minimum_size = Vector2(30, 30)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var title := Label.new()
	title.text = Loc.t("Инвентарь")
	title.theme_type_variation = &"TitleLabel"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var close := Button.new()
	close.text = Loc.t("Закрыть (%s)") % Settings.action_key_name("inventory")
	close.icon = Palette.icon("x")
	close.pressed.connect(EventBus.back)
	head.add_child(close)
	var panel := preload("res://scenes/character/EquipmentPanel.gd").new()
	panel.mode = "sortie"
	box.add_child(panel)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		get_viewport().set_input_as_handled()
		EventBus.back()
