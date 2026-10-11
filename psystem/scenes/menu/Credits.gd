extends Control
## Титры: авторы игры, движка и всех ассетов (модели, анимации, иконки, шрифты, звук, музыка).
## Медленно прокручиваются; колесо мыши/перетаскивание — прокрутка вручную, Esc — назад.

const SECTIONS := [
	{"title": "CodeRealm", "lines": [
		["Идея, контент и тестирование", "alchemistOfWeb"],
		["Код, дизайн игры и сборка ассетов", "Claude (Anthropic)"],
	]},
	{"title": "Движок", "lines": [
		["Godot Engine 4.6 — MIT", "Juan Linietsky, Ariel Manzur и сообщество Godot"],
		["Сборка персонажей", "Blender"],
	]},
	{"title": "3D-модели и анимации", "lines": [
		["Universal Base Characters — CC0", "Quaternius"],
		["Modular Character Outfits: Fantasy — CC0", "Quaternius"],
		["Universal Animation Library — CC0", "Quaternius"],
		["Stylized Nature MegaKit — CC0", "Quaternius"],
		["Medieval Village MegaKit — CC0", "Quaternius"],
		["Fantasy Props MegaKit — CC0", "Quaternius"],
		["Bestiary: Dungeon Monsters — CC0", "Quaternius"],
		["Monster Pack Animated — CC0", "Quaternius"],
		["Easy Animated Enemy Pack — CC0", "Quaternius"],
		["Medieval Weapons Pack — CC0", "Quaternius"],
		["Mini Dungeon — CC0", "Kenney"],
		["Эльфийские уши, клыки орков, рога тифлингов", "Claude (Blender)"],
	]},
	{"title": "Иконки", "lines": [
		["game-icons.net — CC BY 3.0", "Delapouite, Lorc, Skoll, Sbed, Caro Asercion, Darkzaitzev, Faithtoken, Viscious Speed, Zeromancer, Cathelineau, Lord Berandas, Lucas, Carl Olsen, Various Artists"],
		["Lucide — ISC", "Lucide Contributors"],
	]},
	{"title": "Шрифты", "lines": [
		["Inter — SIL OFL", "Rasmus Andersson"],
		["JetBrains Mono — SIL OFL", "JetBrains"],
		["Unbounded — SIL OFL", "NaN"],
	]},
	{"title": "Звук", "lines": [
		["Interface Sounds, Music Jingles, RPG Audio, Impact Sounds — CC0", "Kenney"],
		["Fanfares: «VICTORY» — CC BY 4.0, «Just a random fanfare» — CC0", "Spring Spring"],
	]},
	{"title": "Музыка", "lines": [
		["Slow Stride, Heavenly Loop — CC0", "isaiah658"],
		["Underwater Theme II — CC0", "Cleyton Kauffman"],
		["Heartfelt Battle (loopable) — CC0", "OpenGameArt"],
	]},
	{"title": "Спасибо", "lines": [
		["Всем авторам открытых ассетов, без которых этот мир был бы пустым.", ""],
		["И тебе — за то, что учишься и играешь.", ""],
	]},
]

var _scroll: ScrollContainer
var _auto := true
var _pos := 0.0


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.color = Color(0.03, 0.03, 0.06, 0.92)
	add_child(bg)
	_scroll = ScrollContainer.new()
	_scroll.set_anchors_preset(Control.PRESET_FULL_RECT)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	add_child(_scroll)
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(center)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 760
	box.add_theme_constant_override("separation", 6)
	center.add_child(box)
	var top := Control.new()
	top.custom_minimum_size.y = 520
	box.add_child(top)
	var title := Label.new()
	title.text = Loc.t("Титры")
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color("#FFE9B0"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	for sec in SECTIONS:
		var gap := Control.new()
		gap.custom_minimum_size.y = 34
		box.add_child(gap)
		var h := Label.new()
		h.text = sec.title
		h.theme_type_variation = &"HeaderLabel"
		h.add_theme_font_size_override("font_size", 22)
		h.add_theme_color_override("font_color", Palette.ACCENT.lightened(0.3))
		h.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(h)
		for line in sec.lines:
			var what := Label.new()
			what.text = line[0]
			what.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			what.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			what.add_theme_color_override("font_color", Color("#D8D2C4"))
			box.add_child(what)
			if line[1] != "":
				var who := Label.new()
				who.text = line[1]
				who.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED if not "(" in line[1] else Node.AUTO_TRANSLATE_MODE_INHERIT
				who.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
				who.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				who.add_theme_font_override("font", Palette.FONT_UI_BOLD)
				who.add_theme_color_override("font_color", Color("#FFFFFF"))
				box.add_child(who)
				var gap2 := Control.new()
				gap2.custom_minimum_size.y = 6
				box.add_child(gap2)
	var bottom := Control.new()
	bottom.custom_minimum_size.y = 560
	box.add_child(bottom)

	var back := Button.new()
	back.text = Loc.t("Назад")
	back.icon = Palette.icon("arrow-left")
	back.position = Vector2(24, 20)
	back.pressed.connect(EventBus.back)
	add_child(back)
	_scroll.gui_input.connect(func(ev):
		if ev is InputEventMouseButton and ev.pressed:
			_auto = false)


func _process(delta: float) -> void:
	if not _auto or _scroll == null:
		return
	_pos += delta * 38.0
	_scroll.scroll_vertical = int(_pos)
	var bar := _scroll.get_v_scroll_bar()
	if _pos >= bar.max_value - bar.page:
		_pos = 0.0
