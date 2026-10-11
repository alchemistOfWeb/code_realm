extends Control
## Главное меню: выбор / создание / удаление профиля (героя), настройки, язык, титры, выход.
## Фон — 3D-поляна у костра (CampScene) с выбранным героем.

var _scene: CampScene
var _list: VBoxContainer
var _play_btn: Button
var _delete_btn: Button
var _info: Label
var _selected := ""
var _confirm: ConfirmationDialog


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	SaveSystem.profiles_changed.connect(_refresh_list)
	_selected = SaveSystem.last_profile_id()
	_refresh_list()


func on_resume() -> void:
	_selected = SaveSystem.last_profile_id() if SaveSystem.get_profile(_selected).is_empty() else _selected
	_refresh_list()


func _build() -> void:
	var svc := SubViewportContainer.new()
	svc.set_anchors_preset(Control.PRESET_FULL_RECT)
	svc.stretch = true
	svc.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(svc)
	var vp := SubViewport.new()
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_2X
	svc.add_child(vp)
	_scene = CampScene.new()
	vp.add_child(_scene)
	_scene.set_view("menu")

	# Затемнение слева, чтобы меню читалось на фоне
	var shade := TextureRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var g := Gradient.new()
	g.set_color(0, Color(0.02, 0.02, 0.05, 0.86))
	g.set_color(1, Color(0.02, 0.02, 0.05, 0.0))
	g.set_offset(1, 0.62)
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.width = 256
	gt.height = 4
	shade.texture = gt
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	add_child(shade)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 36)
	margin.add_theme_constant_override("margin_left", 52)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var root := HBoxContainer.new()
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(root)

	var col := VBoxContainer.new()
	col.custom_minimum_size.x = 400
	col.add_theme_constant_override("separation", 14)
	root.add_child(col)

	var title := Label.new()
	title.text = "CodeRealm"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 54)
	title.add_theme_color_override("font_color", Color("#FFE9B0"))
	title.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.0, 0.9))
	title.add_theme_constant_override("outline_size", 10)
	col.add_child(title)
	var sub := Label.new()
	sub.text = "Королевство знаний: учись, сражайся, исследуй"
	sub.theme_type_variation = &"DimLabel"
	sub.add_theme_color_override("font_color", Color("#E8D9B8"))
	col.add_child(sub)

	var spacer := Control.new()
	spacer.custom_minimum_size.y = 8
	col.add_child(spacer)

	var heroes_title := Label.new()
	heroes_title.text = "Герои"
	heroes_title.theme_type_variation = &"HeaderLabel"
	col.add_child(heroes_title)

	var list_panel := PanelContainer.new()
	list_panel.theme_type_variation = &"GlassPanel"
	list_panel.custom_minimum_size = Vector2(400, 230)
	col.add_child(list_panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_panel.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 6)
	scroll.add_child(_list)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	col.add_child(row)
	var new_btn := Button.new()
	new_btn.text = "Новый герой"
	new_btn.icon = Palette.icon("plus")
	new_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	new_btn.pressed.connect(func(): EventBus.go("creator"))
	row.add_child(new_btn)
	_delete_btn = Button.new()
	_delete_btn.text = "Удалить"
	_delete_btn.icon = Palette.icon("x")
	_delete_btn.theme_type_variation = &"GhostButton"
	_delete_btn.pressed.connect(_ask_delete)
	row.add_child(_delete_btn)

	_play_btn = Button.new()
	_play_btn.text = "Играть"
	_play_btn.theme_type_variation = &"AccentButton"
	_play_btn.custom_minimum_size.y = 52
	_play_btn.add_theme_font_size_override("font_size", 20)
	_play_btn.pressed.connect(_play)
	col.add_child(_play_btn)

	_info = Label.new()
	_info.theme_type_variation = &"DimLabel"
	_info.add_theme_color_override("font_color", Color("#D8CBB0"))
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_info)

	var bottom := HBoxContainer.new()
	bottom.add_theme_constant_override("separation", 10)
	col.add_child(bottom)
	for b in [["Настройки", "settings", func(): EventBus.go("settings")],
			["Титры", "scroll-text", func(): EventBus.go("credits")],
			["Выйти из игры", "x", EventBus.quit_game]]:
		var btn := Button.new()
		btn.text = b[0]
		btn.icon = Palette.icon(b[1])
		btn.pressed.connect(b[2])
		bottom.add_child(btn)

	# Язык — в правом верхнем углу
	var lang_box := HBoxContainer.new()
	lang_box.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	lang_box.offset_left = -220
	lang_box.offset_top = 22
	lang_box.offset_right = -24
	lang_box.alignment = BoxContainer.ALIGNMENT_END
	lang_box.add_theme_constant_override("separation", 6)
	add_child(lang_box)
	for code in Loc.LANGS:
		var lb := Button.new()
		lb.text = Loc.LANGS[code]
		lb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		lb.toggle_mode = true
		lb.button_pressed = Loc.lang() == code
		lb.theme_type_variation = &"AccentButton" if Loc.lang() == code else &"GhostButton"
		lb.pressed.connect(_set_language.bind(code))
		lang_box.add_child(lb)

	var version := Label.new()
	version.text = "Godot 4.6 · v5"
	version.theme_type_variation = &"DimLabel"
	version.add_theme_font_size_override("font_size", 11)
	version.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	version.offset_left = -160
	version.offset_top = -30
	version.offset_right = -20
	version.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	add_child(version)


func _refresh_list() -> void:
	for c in _list.get_children():
		c.queue_free()
	var profiles := SaveSystem.list_profiles()
	if SaveSystem.get_profile(_selected).is_empty():
		_selected = profiles[0].id if not profiles.is_empty() else ""
	if profiles.is_empty():
		var empty := Label.new()
		empty.text = "Пока нет ни одного героя.\nСоздай первого — выбери расу, пол и внешность."
		empty.theme_type_variation = &"DimLabel"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_list.add_child(empty)
	for p in profiles:
		_list.add_child(_profile_row(p))
	_play_btn.disabled = _selected == ""
	_delete_btn.disabled = _selected == ""
	var sel := SaveSystem.get_profile(_selected)
	if sel.is_empty():
		_info.text = ""
		_scene.show_hero(Appearance.default_look("male"))
	else:
		_info.text = Loc.t("Последняя игра: %s") % String(sel.get("last_played", "")).replace("T", " ").left(16)
		_scene.show_hero(sel.get("look", {}) if not sel.get("look", {}).is_empty() else Appearance.default_look(), sel.get("outfit", {}))


func _profile_row(p: Dictionary) -> Control:
	var btn := Button.new()
	btn.toggle_mode = true
	btn.button_pressed = p.id == _selected
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.custom_minimum_size.y = 52
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	var look: Dictionary = p.get("look", {})
	var race := Appearance.race(look.get("race", "human"))
	btn.text = "%s\n%s · %s %d" % [p.get("name", "?"), Loc.t(race.name), Loc.t("уровень"), int(p.get("level", 1))]
	btn.icon = Palette.game_icon(_race_icon(look.get("race", "human")))
	btn.expand_icon = false
	btn.add_theme_constant_override("icon_max_width", 28)
	btn.pressed.connect(func():
		_selected = p.id
		_refresh_list())
	btn.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.double_click:
			_selected = p.id
			_play())
	return btn


static func _race_icon(race_id: String) -> String:
	return {"human": "person", "elf": "woman-elf-face", "dwarf": "dwarf-face", "orc": "orc-head",
		"halfling": "hobbit-dwelling", "tiefling": "devil-mask"}.get(race_id, "person")


func _play() -> void:
	if _selected == "" or not SaveSystem.select_profile(_selected):
		return
	Audio.play("confirm")
	EventBus.go("world", {"root": true})


func _ask_delete() -> void:
	var p := SaveSystem.get_profile(_selected)
	if p.is_empty():
		return
	if _confirm == null:
		_confirm = ConfirmationDialog.new()
		_confirm.title = "Удалить героя?"
		_confirm.ok_button_text = "Удалить навсегда"
		_confirm.cancel_button_text = "Отмена"
		_confirm.confirmed.connect(func():
			SaveSystem.delete_profile(_selected)
			_selected = SaveSystem.last_profile_id()
			EventBus.notify("Герой удалён", "info")
			_refresh_list())
		add_child(_confirm)
	_confirm.dialog_text = Loc.t("Профиль «%s» и весь его прогресс будут удалены. Это действие нельзя отменить.") % p.name
	_confirm.popup_centered()


func _set_language(code: String) -> void:
	if code == Loc.lang():
		return
	Settings.set_value("language", code)
	EventBus.go("main_menu", {"root": true})
