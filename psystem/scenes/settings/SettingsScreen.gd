extends Control
## Экран настроек: режим окна, разрешение, масштаб интерфейса, VSync, громкость, музыка.
## Все значения живут в автолоаде Settings; экран только отображает и меняет их.

const UI_SCALE_MIN := 70
const UI_SCALE_MAX := 150

@onready var screen_box: VBoxContainer = %ScreenBox
@onready var sound_box: VBoxContainer = %SoundBox

var _mode_option: OptionButton
var _res_option: OptionButton
var _res_values: Array[String] = []
var _scale_slider: HSlider
var _scale_label: Label
var _vsync_check: CheckBox
var _window_info: Label
var _volume_sliders: Dictionary = {}   # key -> [HSlider, Label]
var _music_check: CheckBox
var _ui_sounds_check: CheckBox
var _track_label: Label
var _lang_option: OptionButton
var _controls_box: VBoxContainer
var _bind_buttons: Dictionary = {}     # action → Button
var _waiting_action := ""
var _sens_slider: HSlider


func _ready() -> void:
	%BackButton.pressed.connect(EventBus.back)
	%ResetButton.pressed.connect(_on_reset)
	_build_screen_section()
	_build_sound_section()
	_build_controls_section()
	Settings.changed.connect(_on_settings_changed)
	Audio.track_changed.connect(_on_track_changed)
	get_window().size_changed.connect(_refresh_window_info)
	_refresh()


func on_resume() -> void:
	_refresh()


func _on_settings_changed(_key: String) -> void:
	_refresh()


func _on_track_changed(_title: String) -> void:
	_refresh_track()


# ---------------------------------------------------------------- Построение

func _build_screen_section() -> void:
	screen_box.add_child(_section_header(Loc.t("Экран"), "monitor"))

	_lang_option = OptionButton.new()
	for code in Loc.LANGS:
		_lang_option.add_item(Loc.LANGS[code])
		_lang_option.set_item_metadata(_lang_option.item_count - 1, code)
	_lang_option.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_lang_option.item_selected.connect(_on_language)
	screen_box.add_child(_row(Loc.t("Язык / Language"), _lang_option))

	_mode_option = OptionButton.new()
	for key in Settings.WINDOW_MODES:
		_mode_option.add_item(Settings.WINDOW_MODES[key])
		_mode_option.set_item_metadata(_mode_option.item_count - 1, key)
	_mode_option.item_selected.connect(func(i): Settings.set_value("window_mode", _mode_option.get_item_metadata(i)))
	screen_box.add_child(_row(Loc.t("Режим окна"), _mode_option))

	_res_option = OptionButton.new()
	_res_option.item_selected.connect(func(i): Settings.set_value("resolution", _res_values[i]))
	screen_box.add_child(_row(Loc.t("Разрешение окна"), _res_option))

	var scale_box := HBoxContainer.new()
	scale_box.add_theme_constant_override("separation", 12)
	_scale_slider = HSlider.new()
	_scale_slider.min_value = UI_SCALE_MIN
	_scale_slider.max_value = UI_SCALE_MAX
	_scale_slider.step = 5
	_scale_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scale_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_scale_slider.custom_minimum_size.x = 160
	_scale_label = _value_label()
	_scale_slider.value_changed.connect(func(v):
		_scale_label.text = "%d%%" % v
		if not _scale_slider.has_meta("dragging"):
			Settings.set_value("ui_scale", v / 100.0))
	_scale_slider.drag_started.connect(func(): _scale_slider.set_meta("dragging", true))
	_scale_slider.drag_ended.connect(func(_c):
		_scale_slider.remove_meta("dragging")
		Settings.set_value("ui_scale", _scale_slider.value / 100.0))
	scale_box.add_child(_scale_slider)
	scale_box.add_child(_scale_label)
	screen_box.add_child(_row(Loc.t("Масштаб интерфейса"), scale_box))

	_vsync_check = CheckBox.new()
	_vsync_check.text = Loc.t("Вертикальная синхронизация (VSync)")
	_vsync_check.toggled.connect(func(on): Settings.set_value("vsync", on))
	screen_box.add_child(_vsync_check)

	_window_info = Label.new()
	_window_info.theme_type_variation = &"DimLabel"
	_window_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_window_info.custom_minimum_size.x = 200
	screen_box.add_child(_window_info)


func _build_sound_section() -> void:
	sound_box.add_child(_section_header(Loc.t("Звук"), "volume-2"))
	for item in [["master_volume", Loc.t("Общая громкость")], ["music_volume", Loc.t("Музыка")], ["sfx_volume", Loc.t("Звуки интерфейса")]]:
		var key: String = item[0]
		var box := HBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 100
		slider.step = 1
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		slider.custom_minimum_size.x = 160
		var label := _value_label()
		slider.value_changed.connect(func(v):
			label.text = "%d%%" % v
			Settings.set_value(key, v / 100.0))
		if key != "music_volume":
			slider.drag_ended.connect(func(_c): Audio.play("click", 0.0))
		box.add_child(slider)
		box.add_child(label)
		_volume_sliders[key] = [slider, label]
		sound_box.add_child(_row(item[1], box))

	_music_check = CheckBox.new()
	_music_check.text = Loc.t("Фоновая музыка")
	_music_check.toggled.connect(func(on): Settings.set_value("music_enabled", on))
	sound_box.add_child(_music_check)

	_ui_sounds_check = CheckBox.new()
	_ui_sounds_check.text = Loc.t("Звуки интерфейса (клики, уведомления, награды)")
	_ui_sounds_check.toggled.connect(func(on): Settings.set_value("ui_sounds", on))
	sound_box.add_child(_ui_sounds_check)

	var track_row := HBoxContainer.new()
	track_row.add_theme_constant_override("separation", 12)
	_track_label = Label.new()
	_track_label.theme_type_variation = &"MonoLabel"
	_track_label.add_theme_font_size_override("font_size", 13)
	_track_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_track_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_track_label.clip_text = true
	track_row.add_child(_track_label)
	var next_btn := Button.new()
	next_btn.text = Loc.t("Следующий трек")
	next_btn.icon = Palette.icon("skip-forward")
	next_btn.pressed.connect(func():
		if not Settings.get_value("music_enabled"):
			Settings.set_value("music_enabled", true)
		else:
			Audio.next_track())
	track_row.add_child(next_btn)
	sound_box.add_child(track_row)


func _build_controls_section() -> void:
	# Правая колонка: «Звук» и под ним «Управление»
	var sound_panel: Control = sound_box.get_parent()
	var columns: Control = sound_panel.get_parent()
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 18)
	columns.add_child(col)
	columns.move_child(col, sound_panel.get_index())
	sound_panel.reparent(col)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"CardPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_child(panel)
	_controls_box = VBoxContainer.new()
	_controls_box.add_theme_constant_override("separation", 8)
	panel.add_child(_controls_box)
	_controls_box.add_child(_section_header(Loc.t("Управление в вылазках"), "gamepad-2"))
	for action in Settings.REBINDABLE:
		var b := Button.new()
		b.custom_minimum_size.x = 110
		b.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		b.pressed.connect(_start_rebind.bind(action))
		_bind_buttons[action] = b
		var row := _row(Settings.REBINDABLE[action], b)
		b.size_flags_horizontal = Control.SIZE_SHRINK_END
		_controls_box.add_child(row)
	var sens_box := HBoxContainer.new()
	_sens_slider = HSlider.new()
	_sens_slider.min_value = 0.3
	_sens_slider.max_value = 2.5
	_sens_slider.step = 0.1
	_sens_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sens_slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_sens_slider.value_changed.connect(func(v): Settings.set_value("mouse_sensitivity", v))
	sens_box.add_child(_sens_slider)
	_controls_box.add_child(_row(Loc.t("Чувствительность камеры"), sens_box))
	var hint := Label.new()
	hint.text = Loc.t("Нажми на клавишу действия, затем новую клавишу. Камера — правая кнопка мыши, колесо — приближение.")
	hint.theme_type_variation = &"DimLabel"
	hint.add_theme_font_size_override("font_size", 12)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 260
	_controls_box.add_child(hint)


func _start_rebind(action: String) -> void:
	_waiting_action = action
	_bind_buttons[action].text = Loc.t("Нажми клавишу…")


func _input(event: InputEvent) -> void:
	if _waiting_action == "" or not event is InputEventKey or not event.pressed:
		return
	get_viewport().set_input_as_handled()
	if event.physical_keycode != KEY_ESCAPE:
		Settings.rebind(_waiting_action, event.physical_keycode)
	_waiting_action = ""
	_refresh_controls()


func _refresh_controls() -> void:
	for action in _bind_buttons:
		_bind_buttons[action].text = Settings.action_key_name(action)
	if _sens_slider:
		_sens_slider.set_value_no_signal(float(Settings.get_value("mouse_sensitivity")))


func _on_language(i: int) -> void:
	var code: String = _lang_option.get_item_metadata(i)
	if code == Loc.lang():
		return
	Settings.set_value("language", code)
	# Пересобрать экраны на новом языке
	if SaveSystem.has_active_profile():
		EventBus.go("world", {"root": true})
	else:
		EventBus.go("main_menu", {"root": true})


func _section_header(text: String, icon_name: String) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var icon := TextureRect.new()
	icon.texture = Palette.icon(icon_name)
	icon.custom_minimum_size = Vector2(22, 22)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.modulate = Palette.ACCENT.lightened(0.2)
	row.add_child(icon)
	var label := Label.new()
	label.text = text
	label.theme_type_variation = &"HeaderLabel"
	row.add_child(label)
	return row


func _row(title: String, control: Control) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var label := Label.new()
	label.text = title
	label.custom_minimum_size.x = 190
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(control)
	return row


func _value_label() -> Label:
	var label := Label.new()
	label.theme_type_variation = &"MonoLabel"
	label.custom_minimum_size.x = 52
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


# ---------------------------------------------------------------- Обновление

func _refresh() -> void:
	var embedded := Settings.is_embedded()
	var mode: String = Settings.get_value("window_mode")
	for i in _mode_option.item_count:
		if _mode_option.get_item_metadata(i) == mode:
			_mode_option.select(i)
	_mode_option.disabled = embedded

	_res_option.clear()
	_res_values.clear()
	_res_option.add_item(Loc.t("Авто (%s)") % Settings.resolution_to_string(Settings.auto_resolution()))
	_res_values.append("auto")
	for r in Settings.available_resolutions():
		_res_option.add_item(Settings.resolution_to_string(r).replace("x", " × "))
		_res_values.append(Settings.resolution_to_string(r))
	var current: String = Settings.get_value("resolution")
	_res_option.select(maxi(_res_values.find(current), 0))
	_res_option.disabled = embedded or mode != "windowed"

	var scale_pct := roundi(float(Settings.get_value("ui_scale")) * 100.0)
	_scale_slider.set_value_no_signal(scale_pct)
	_scale_label.text = "%d%%" % scale_pct
	_vsync_check.set_pressed_no_signal(Settings.get_value("vsync"))

	for key in _volume_sliders:
		var v := roundi(float(Settings.get_value(key)) * 100.0)
		_volume_sliders[key][0].set_value_no_signal(v)
		_volume_sliders[key][1].text = "%d%%" % v
	_music_check.set_pressed_no_signal(Settings.get_value("music_enabled"))
	_ui_sounds_check.set_pressed_no_signal(Settings.get_value("ui_sounds"))
	for i in _lang_option.item_count:
		if _lang_option.get_item_metadata(i) == Loc.lang():
			_lang_option.select(i)
	_refresh_controls()
	_refresh_track()
	_refresh_window_info()


func _refresh_track() -> void:
	var title := Audio.current_track_title()
	_track_label.text = "♪ " + title if title != "" else Loc.t("Музыка выключена")


func _refresh_window_info() -> void:
	if _window_info == null:
		return
	var screen := Settings.usable_screen_rect().size
	var win := get_window().size
	var text := Loc.t("Окно: %d × %d · экран: %d × %d · базовое разрешение интерфейса 1280 × 720") % [win.x, win.y, screen.x, screen.y]
	if Settings.is_embedded():
		text += Loc.t("\n\nИгра запущена внутри редактора (вкладка Game) — размером окна управляет редактор. ") \
			+ Loc.t("На панели Game выбери режим «Keep Aspect» или «Stretch», либо отключи «Embed Game on Next Play», чтобы игра открывалась отдельным окном.")
		_window_info.add_theme_color_override("font_color", Palette.ENERGY)
	_window_info.text = text


func _on_reset() -> void:
	Settings.reset_to_defaults()
	EventBus.notify(Loc.t("Настройки сброшены"), "info")
