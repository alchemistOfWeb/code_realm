extends PanelContainer
## Верхняя панель: уровень, XP, HP, энергия, золото, кнопки «Заметки» и «Персонаж».

@onready var level_label: Label = %LevelLabel
@onready var xp_label: Label = %XPLabel
@onready var xp_bar: ProgressBar = %XPBar
@onready var hp_label: Label = %HPLabel
@onready var energy_label: Label = %EnergyLabel
@onready var energy_bar: ProgressBar = %EnergyBar
@onready var gold_label: Label = %GoldLabel
@onready var points_badge: Label = %PointsBadge

var _notes_dialog: AcceptDialog
var _shown_level := -1
var _xp_tween: Tween
var _shine_mat: ShaderMaterial
var _chest_tween: Tween
var _notes_edit: TextEdit


func _ready() -> void:
	GameManager.player_changed.connect(refresh)
	GameManager.xp_gained.connect(_on_xp_gained)
	GameManager.energy_changed.connect(func(_c, _m): _pulse(energy_bar))
	SaveSystem.loaded.connect(refresh)
	%LogoButton.pressed.connect(func(): EventBus.navigate_home.emit())
	%CharacterButton.pressed.connect(func(): EventBus.go("character"))
	%NotesButton.pressed.connect(_open_notes_dialog)
	%SettingsButton.pressed.connect(func(): EventBus.go("settings"))
	%ChestButton.icon = Palette.game_icon("chest")
	%ChestButton.set_meta("sfx", "chest_creak")
	%ChestButton.pressed.connect(func(): EventBus.go("lootbox", {"overlay": true}))
	_add_xp_shine()
	_add_nav_buttons()
	%MusicButton.pressed.connect(func(): Settings.set_value("music_enabled", not Settings.get_value("music_enabled")))
	%MusicButton.set_meta("sfx", "toggle")
	Settings.changed.connect(_on_settings_changed)
	_update_music_button()
	refresh(false)


## Кнопки «Карта мира», «Лавка» и «Меню» (главное меню, титры, выход из игры).
func _add_nav_buttons() -> void:
	var row: HBoxContainer = %CharacterButton.get_parent()
	var at: int = %CharacterButton.get_index()
	var defs := [
		[Loc.t("Карта мира"), "treasure-map", Loc.t("Карта мира: локации и вылазки"), func(): EventBus.go("world_map")],
		[Loc.t("Лавка"), "shop", Loc.t("Лавка снаряжения: оружие и броня"), func(): EventBus.go("shop")],
	]
	for d in defs:
		var b := Button.new()
		b.icon = Palette.game_icon(d[1])
		b.tooltip_text = d[2]
		b.add_theme_constant_override("h_separation", 0)
		b.expand_icon = false
		b.add_theme_constant_override("icon_max_width", 20)
		b.pressed.connect(d[3])
		row.add_child(b)
		row.move_child(b, at)
		at += 1
	# Музыка переключается в настройках — освобождаем место под кнопку меню; логотип — только иконка
	%MusicButton.visible = false
	%LogoButton.text = ""
	%LogoButton.tooltip_text = Loc.t("Древо знаний (главный экран)")
	row.add_theme_constant_override("separation", 10)
	var menu := Button.new()
	menu.icon = Palette.game_icon("power-button")
	menu.tooltip_text = Loc.t("Меню: главное меню, титры, выход из игры (Esc)")
	menu.add_theme_constant_override("icon_max_width", 20)
	menu.pressed.connect(func(): EventBus.game_menu_requested.emit())
	row.add_child(menu)


func _on_settings_changed(key: String) -> void:
	if key == "music_enabled":
		_update_music_button()


func _update_music_button() -> void:
	var on: bool = Settings.get_value("music_enabled")
	%MusicButton.icon = Palette.icon("music" if on else "volume-x")
	%MusicButton.modulate = Color.WHITE if on else Color(1, 1, 1, 0.55)


func refresh(animate: bool = true) -> void:
	var p := GameManager.player_data
	level_label.text = Loc.t("УР %d") % p.level
	xp_label.text = "%d / %d XP" % [p.xp, p.xp_to_next]
	hp_label.text = "%d / %d" % [p.hp, p.max_hp]
	energy_label.text = "%d / %d" % [p.energy, p.max_energy]
	gold_label.text = str(p.gold)
	points_badge.visible = p.attribute_points > 0
	points_badge.text = Loc.t("+%d очк.") % p.attribute_points
	points_badge.tooltip_text = Loc.t("Нераспределённые очки атрибутов — открой экран персонажа")
	energy_bar.max_value = p.max_energy
	_update_chest(p.get("lootboxes", 0))
	if animate and _shown_level >= 0:
		_animate_xp(p.level, p.xp, p.xp_to_next)
		var tw := create_tween()
		tw.tween_property(energy_bar, "value", float(p.energy), 0.5).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	else:
		xp_bar.max_value = p.xp_to_next
		xp_bar.value = p.xp
		energy_bar.value = p.energy
		_update_shine()
	_shown_level = p.level


## XP-бар: при повышении уровня сначала доливается до конца, затем заполняется заново.
func _animate_xp(level: int, xp: int, xp_to_next: int) -> void:
	if _xp_tween:
		_xp_tween.kill()
	_xp_tween = create_tween()
	if level > _shown_level:
		_xp_tween.tween_property(xp_bar, "value", xp_bar.max_value, 0.35).set_trans(Tween.TRANS_CUBIC)
		_xp_tween.tween_callback(func():
			xp_bar.max_value = xp_to_next
			xp_bar.value = 0
			_pulse(xp_bar))
	else:
		xp_bar.max_value = xp_to_next
	_xp_tween.tween_property(xp_bar, "value", float(xp), 0.55).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_xp_tween.tween_callback(_update_shine)


func _add_xp_shine() -> void:
	var shine := ColorRect.new()
	shine.set_anchors_preset(Control.PRESET_FULL_RECT)
	shine.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_shine_mat = ShaderMaterial.new()
	_shine_mat.shader = preload("res://shaders/bar_shine.gdshader")
	shine.material = _shine_mat
	xp_bar.add_child(shine)
	xp_bar.value_changed.connect(func(_v): _update_shine())


func _update_shine() -> void:
	if _shine_mat:
		_shine_mat.set_shader_parameter("fill", xp_bar.value / maxf(xp_bar.max_value, 1.0))


func _update_chest(n: int) -> void:
	var btn: Button = %ChestButton
	btn.visible = n > 0
	btn.text = "×%d" % n
	if n > 0 and _chest_tween == null:
		_chest_tween = btn.create_tween().set_loops()
		_chest_tween.tween_property(btn, "modulate", Color(1.35, 1.25, 1.0), 0.7).set_trans(Tween.TRANS_SINE)
		_chest_tween.tween_property(btn, "modulate", Color.WHITE, 0.7).set_trans(Tween.TRANS_SINE)
	elif n == 0 and _chest_tween:
		_chest_tween.kill()
		_chest_tween = null
		btn.modulate = Color.WHITE


func _on_xp_gained(amount: int) -> void:
	_pulse(xp_bar)
	if not is_visible_in_tree() or xp_bar.size.x <= 0.0:
		return
	var label := Label.new()
	label.text = "+%d XP" % amount
	label.theme_type_variation = &"StatLabel"
	label.add_theme_color_override("font_color", Palette.MINT)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	label.top_level = true
	label.z_index = 50
	add_child(label)
	label.global_position = xp_bar.global_position + Vector2(xp_bar.size.x * 0.5 - 30, 18)
	var tw := label.create_tween().set_parallel()
	tw.tween_property(label, "global_position:y", label.global_position.y + 34, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 1.1).set_delay(0.4)
	tw.chain().tween_callback(label.queue_free)


func _pulse(ctrl: Control) -> void:
	ctrl.modulate = Color(1.8, 1.8, 1.8)
	var tw := ctrl.create_tween()
	tw.tween_property(ctrl, "modulate", Color.WHITE, 0.6)


# ---------------------------------------------------------------- Общие заметки для Claude

func _open_notes_dialog() -> void:
	if _notes_dialog == null:
		_notes_dialog = AcceptDialog.new()
		_notes_dialog.title = Loc.t("Заметки для Claude")
		_notes_dialog.ok_button_text = Loc.t("Сохранить и экспортировать")
		_notes_dialog.min_size = Vector2i(720, 460)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 10)
		_notes_dialog.add_child(box)
		var hint := Label.new()
		hint.theme_type_variation = &"DimLabel"
		hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		hint.text = Loc.t("Общие пожелания по приложению (баги, идеи, правки UI). Заметки к конкретным темам пиши на странице урока. Всё попадёт в NOTES_FOR_CLAUDE.md в корне проекта.")
		box.add_child(hint)
		_notes_edit = TextEdit.new()
		_notes_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
		_notes_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
		_notes_edit.placeholder_text = Loc.t("Например: добавить в дерево Python тему про dataclasses...")
		box.add_child(_notes_edit)
		var stats := Label.new()
		stats.name = "Stats"
		stats.theme_type_variation = &"DimLabel"
		box.add_child(stats)
		_notes_dialog.confirmed.connect(_save_general_notes)
		get_tree().root.add_child(_notes_dialog)
	_notes_edit.text = GameManager.get_note(ClaudeNotesExporter.GENERAL_KEY)
	var count := GameManager.claude_notes.size()
	_notes_dialog.find_child("Stats", true, false).text = Loc.t("Всего заметок: %d  ·  файл: %s") % [count, ClaudeNotesExporter.target_path()]
	_notes_dialog.popup_centered()
	_notes_edit.grab_focus()


func _save_general_notes() -> void:
	GameManager.set_note(ClaudeNotesExporter.GENERAL_KEY, _notes_edit.text)
	SaveSystem.save_all()
	var path := ClaudeNotesExporter.export_all()
	if path != "":
		EventBus.notify(Loc.t("Заметки экспортированы в NOTES_FOR_CLAUDE.md"), "success")
