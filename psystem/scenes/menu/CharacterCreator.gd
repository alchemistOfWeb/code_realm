extends Control
## Создание героя: имя, пол, раса (с бонусом), цвет кожи, причёска, цвет волос, борода, расцветка одежды.
## Справа — 3D-превью (CampScene), героя можно вращать мышью.

var look := Appearance.default_look("male")
var _scene: CampScene
var _name_edit: LineEdit
var _gender_row: HBoxContainer
var _race_grid: GridContainer
var _race_info: Label
var _skin_row: HBoxContainer
var _hair_row: HBoxContainer
var _hair_color_row: HBoxContainer
var _beard_check: CheckBox
var _outfit_row: HBoxContainer
var _dragging := false

const NAMES := {
	"male": ["Арен", "Борислав", "Кайл", "Дарен", "Эйвар", "Тарин", "Рольф", "Лиам"],
	"female": ["Айла", "Мирена", "Сая", "Ильва", "Нора", "Тесса", "Верана", "Лира"],
}


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_build()
	_randomize_name()
	_refresh()


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
	_scene.set_view("creator")

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"GlassPanel"
	panel.set_anchors_preset(Control.PRESET_LEFT_WIDE)
	panel.offset_left = 24
	panel.offset_top = 20
	panel.offset_bottom = -20
	panel.offset_right = 24 + 470
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 10)
	scroll.add_child(box)

	var header := HBoxContainer.new()
	box.add_child(header)
	var back := Button.new()
	back.text = Loc.t("Назад")
	back.icon = Palette.icon("arrow-left")
	back.theme_type_variation = &"GhostButton"
	back.pressed.connect(EventBus.back)
	header.add_child(back)
	var title := Label.new()
	title.text = Loc.t("Новый герой")
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 24)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	header.add_child(title)

	box.add_child(_caption(Loc.t("Имя")))
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	box.add_child(name_row)
	_name_edit = LineEdit.new()
	_name_edit.max_length = 20
	_name_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_name_edit.placeholder_text = Loc.t("Имя героя")
	name_row.add_child(_name_edit)
	var dice := Button.new()
	dice.icon = Palette.game_icon("rolling-dices")
	dice.tooltip_text = Loc.t("Случайное имя")
	dice.add_theme_constant_override("icon_max_width", 20)
	dice.pressed.connect(_randomize_name)
	name_row.add_child(dice)

	box.add_child(_caption(Loc.t("Пол")))
	_gender_row = HBoxContainer.new()
	_gender_row.add_theme_constant_override("separation", 8)
	box.add_child(_gender_row)
	for g in Appearance.GENDERS:
		var b := Button.new()
		b.text = Appearance.GENDERS[g]
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("value", g)
		b.pressed.connect(_set_gender.bind(g))
		_gender_row.add_child(b)

	box.add_child(_caption(Loc.t("Раса")))
	_race_grid = GridContainer.new()
	_race_grid.columns = 3
	_race_grid.add_theme_constant_override("h_separation", 6)
	_race_grid.add_theme_constant_override("v_separation", 6)
	box.add_child(_race_grid)
	for r in Appearance.RACES:
		var b := Button.new()
		b.text = Appearance.RACES[r].name
		b.toggle_mode = true
		b.icon = Palette.game_icon(_race_icon(r))
		b.add_theme_constant_override("icon_max_width", 22)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("value", r)
		b.pressed.connect(_set_race.bind(r))
		_race_grid.add_child(b)
	_race_info = Label.new()
	_race_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_race_info.custom_minimum_size.x = 400
	_race_info.theme_type_variation = &"DimLabel"
	box.add_child(_race_info)

	box.add_child(_caption(Loc.t("Цвет кожи")))
	_skin_row = HBoxContainer.new()
	_skin_row.add_theme_constant_override("separation", 6)
	box.add_child(_skin_row)

	box.add_child(_caption(Loc.t("Причёска")))
	_hair_row = HBoxContainer.new()
	_hair_row.add_theme_constant_override("separation", 6)
	box.add_child(_hair_row)

	box.add_child(_caption(Loc.t("Цвет волос")))
	_hair_color_row = HBoxContainer.new()
	_hair_color_row.add_theme_constant_override("separation", 5)
	box.add_child(_hair_color_row)
	for i in Appearance.HAIR_COLORS.size():
		_hair_color_row.add_child(_swatch(Color(Appearance.HAIR_COLORS[i]), _set_value.bind("hair_color", i), "hair_color", i))

	_beard_check = CheckBox.new()
	_beard_check.text = Loc.t("Борода")
	_beard_check.toggled.connect(func(on): _set_value("beard", on))
	box.add_child(_beard_check)

	box.add_child(_caption(Loc.t("Расцветка одежды")))
	_outfit_row = HBoxContainer.new()
	_outfit_row.add_theme_constant_override("separation", 6)
	box.add_child(_outfit_row)
	for i in Appearance.OUTFIT_VARIANTS:
		var b := Button.new()
		b.text = [Loc.t("Льняная"), Loc.t("Крашеная")][i]
		b.toggle_mode = true
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.set_meta("value", i)
		b.pressed.connect(_set_value.bind("outfit_variant", i))
		_outfit_row.add_child(b)

	var random := Button.new()
	random.text = Loc.t("Случайная внешность")
	random.icon = Palette.game_icon("rolling-dices")
	random.add_theme_constant_override("icon_max_width", 20)
	random.pressed.connect(_randomize_look)
	box.add_child(random)

	var create := Button.new()
	create.text = Loc.t("Начать приключение")
	create.theme_type_variation = &"AccentButton"
	create.custom_minimum_size.y = 50
	create.add_theme_font_size_override("font_size", 18)
	create.pressed.connect(_create)
	box.add_child(create)

	var hint := Label.new()
	hint.text = Loc.t("Перетащи героя мышью, чтобы повернуть")
	hint.theme_type_variation = &"DimLabel"
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_top = -40
	hint.offset_left = 120
	hint.offset_right = 520
	hint.add_theme_color_override("font_color", Color("#F0E6CF"))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	hint.add_theme_constant_override("outline_size", 6)
	add_child(hint)


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"HeaderLabel"
	l.add_theme_font_size_override("font_size", 15)
	return l


func _swatch(color: Color, cb: Callable, key: String, value: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(30, 30)
	b.toggle_mode = true
	b.set_meta("key", key)
	b.set_meta("value", value)
	var sb := StyleBoxFlat.new()
	sb.bg_color = color
	sb.set_corner_radius_all(15)
	sb.set_border_width_all(2)
	sb.border_color = Color(1, 1, 1, 0.25)
	var sel := sb.duplicate()
	sel.border_color = Color("#FFE08A")
	sel.set_border_width_all(4)
	for st in ["normal", "hover", "focus"]:
		b.add_theme_stylebox_override(st, sb)
	b.add_theme_stylebox_override("pressed", sel)
	b.add_theme_stylebox_override("hover_pressed", sel)
	b.pressed.connect(cb)
	return b


static func _race_icon(race_id: String) -> String:
	return {"human": "person", "elf": "woman-elf-face", "dwarf": "dwarf-face", "orc": "orc-head",
		"halfling": "hobbit-dwelling", "tiefling": "devil-mask"}.get(race_id, "person")


# ---------------------------------------------------------------- Изменения

func _set_gender(g: String) -> void:
	if look.gender == g:
		_refresh()
		return
	look.gender = g
	var styles: Array = Appearance.HAIRSTYLES[g]
	if not look.hair in styles:
		look.hair = styles[0]
	if g == "female":
		look.beard = false
	_randomize_name()
	_refresh()


func _set_race(r: String) -> void:
	look.race = r
	look.skin = clampi(int(look.skin), 0, Appearance.race(r).skins.size() - 1)
	_refresh()


func _set_value(key: String, value) -> void:
	look[key] = value
	_refresh()


func _randomize_name() -> void:
	var list: Array = NAMES[look.gender]
	_name_edit.text = Loc.t(list[randi() % list.size()])


func _randomize_look() -> void:
	var r := Appearance.random_look(randi(), look.race)
	r.gender = look.gender
	r.hair = Appearance.HAIRSTYLES[look.gender][randi() % Appearance.HAIRSTYLES[look.gender].size()]
	r.beard = look.gender == "male" and randf() < 0.4
	look = r
	_refresh()


func _refresh() -> void:
	for b in _gender_row.get_children():
		b.button_pressed = b.get_meta("value") == look.gender
	for b in _race_grid.get_children():
		b.button_pressed = b.get_meta("value") == look.race
	var race := Appearance.race(look.race)
	_race_info.text = "%s\n%s %s" % [Loc.t(race.desc), Loc.t("Бонус:"), Loc.t(race.bonus_text)]
	for c in _skin_row.get_children():
		c.queue_free()
	for i in race.skins.size():
		var sw := _swatch(Color(race.skins[i]), _set_value.bind("skin", i), "skin", i)
		sw.button_pressed = i == int(look.skin)
		_skin_row.add_child(sw)
	for c in _hair_row.get_children():
		c.queue_free()
	for style in Appearance.HAIRSTYLES[look.gender]:
		var b := Button.new()
		b.text = Appearance.HAIR_NAMES[style]
		b.toggle_mode = true
		b.button_pressed = style == look.hair
		b.pressed.connect(_set_value.bind("hair", style))
		_hair_row.add_child(b)
	for b in _hair_color_row.get_children():
		b.button_pressed = b.get_meta("value") == int(look.hair_color)
	for b in _outfit_row.get_children():
		b.button_pressed = b.get_meta("value") == int(look.outfit_variant)
	var dwarf_beard: bool = look.race == "dwarf" and look.gender == "male"
	_beard_check.visible = look.gender == "male"
	_beard_check.disabled = dwarf_beard
	_beard_check.set_pressed_no_signal(look.beard or dwarf_beard)
	_scene.show_hero(look)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_scene.rotate_hero(event.relative.x * 0.01)


func _create() -> void:
	var hero_name := _name_edit.text.strip_edges()
	if hero_name == "":
		EventBus.notify(Loc.t("Введи имя героя"), "warning")
		return
	GameManager.create_hero(hero_name, look)
	SaveSystem.create_profile(hero_name)
	GameManager.grant_starter_pack()
	SaveSystem.save_all()
	Audio.play_jingle("levelup")
	EventBus.notify(Loc.t("Добро пожаловать в CodeRealm, %s!") % hero_name, "success")
	EventBus.go("world", {"root": true})
