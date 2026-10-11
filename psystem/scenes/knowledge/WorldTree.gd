extends Control
## Главный экран: «Ядро знаний» в центре и сферы специализаций по эллипсу.
## Число специализаций любое — раскладка считается автоматически.

const ORB_SCENE := preload("res://scenes/knowledge/SpecOrb.tscn")
const LINE_SHADER := preload("res://shaders/tree_connection.gdshader")
const ORB_CENTER := Vector2(115, 100)   # центр сферы внутри SpecOrb (= pivot_offset)
const ORB_SIZE := Vector2(230, 260)

@onready var connections_layer: Control = $ConnectionsLayer
@onready var nodes_container: Control = $NodesContainer
@onready var progress_label: Label = %ProgressLabel
@onready var total_bar: ProgressBar = %TotalBar
@onready var quest_panel: PanelContainer = %QuestPanel
@onready var quest_list: VBoxContainer = %QuestList

var _orbs: Dictionary = {}   # spec_id -> SpecOrb
var _core   # SpecOrb
var _line_material: ShaderMaterial


func _ready() -> void:
	_line_material = ShaderMaterial.new()
	_line_material.shader = LINE_SHADER
	_build_world_tree()
	_build_expedition_button()
	EventBus.progress_changed.connect(func(_s): refresh())
	resized.connect(_layout)
	refresh()
	_layout.call_deferred()


func on_resume() -> void:
	refresh()


func _build_world_tree() -> void:
	_core = ORB_SCENE.instantiate()
	nodes_container.add_child(_core)
	_core.setup_custom("Ядро знаний", Palette.ACCENT, "brain", "Общий прогресс по всем специализациям.\nНажми, чтобы открыть экран персонажа.")
	_core.pressed.connect(func(): EventBus.go("character"))
	for spec_id in ContentParser.get_all_spec_ids():
		var orb := ORB_SCENE.instantiate()
		nodes_container.add_child(orb)
		orb.setup(spec_id)
		orb.pressed.connect(_on_spec_pressed.bind(spec_id))
		_orbs[spec_id] = orb


func _layout() -> void:
	if size.x < 100 or size.y < 100:
		return
	for child in connections_layer.get_children():
		child.queue_free()

	var ids := ContentParser.get_all_spec_ids()
	var n := ids.size()
	var angles: Array[float] = []
	var max_sin := -1.0
	for i in n:
		var a := -PI / 2.0 + TAU * i / maxf(n, 1)
		angles.append(a)
		max_sin = maxf(max_sin, sin(a))

	# Масштаб сфер под размер экрана; эллипс вписывается между заголовком и нижним краем
	var s := clampf(minf(size.x / 1450.0, size.y / 800.0), 0.6, 1.15)
	var header: Control = $Header
	var top := header.position.y + header.size.y + 8.0
	var up := ORB_CENTER.y * s              # от центра сферы до верха свечения
	var down := (ORB_SIZE.y - ORB_CENTER.y) * s   # от центра до низа подписи
	var ry := maxf((size.y - 10.0 - down - top - up) / maxf(1.0 + max_sin, 1.0), 60.0)
	var center := Vector2(size.x * 0.5, top + up + ry)
	var rx := minf(ry * 1.6, size.x * 0.5 - ORB_SIZE.x * 0.5 * s - 10.0)

	_core.base_scale = s
	_core.position = center - ORB_CENTER
	for i in n:
		var spec_id: String = ids[i]
		var pos := center + Vector2(cos(angles[i]) * rx, sin(angles[i]) * ry)
		var orb = _orbs[spec_id]
		orb.base_scale = s
		orb.position = pos - ORB_CENTER
		var dir := (pos - center).normalized()
		var color := ContentParser.get_spec_color(spec_id)
		var active := 1.0 if GameManager.count_learned(spec_id) > 0 else 0.18
		_add_line(PackedVector2Array([center + dir * 78 * s, pos - dir * 78 * s]), Color(color, active), 7.0 * s)

	# Орбита между соседними сферами
	if n > 1:
		for i in n:
			var a0 := angles[i]
			var a1 := angles[i] + TAU / n
			var pts := PackedVector2Array()
			for k in 25:
				var a := lerpf(a0, a1, lerpf(0.2, 0.8, k / 24.0))
				pts.append(center + Vector2(cos(a) * rx, sin(a) * ry))
			var c0 := ContentParser.get_spec_color(ids[i])
			var c1 := ContentParser.get_spec_color(ids[(i + 1) % n])
			var line := _add_line(pts, Color.WHITE, 4.0 * s)
			var grad := Gradient.new()
			grad.set_color(0, Color(c0, 0.3))
			grad.set_color(1, Color(c1, 0.3))
			line.gradient = grad


func _add_line(points: PackedVector2Array, color: Color, width: float) -> Line2D:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.default_color = color
	line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.begin_cap_mode = Line2D.LINE_CAP_ROUND
	line.end_cap_mode = Line2D.LINE_CAP_ROUND
	line.antialiased = true
	line.material = _line_material
	connections_layer.add_child(line)
	return line


func refresh() -> void:
	var learned := GameManager.total_learned()
	var total := ContentParser.total_node_count()
	progress_label.text = "Знания: %d / %d" % [learned, total]
	total_bar.max_value = maxi(total, 1)
	total_bar.value = learned
	for spec_id in _orbs:
		_orbs[spec_id].refresh()
	_core.set_progress(learned, total, "Уровень %d · %d%%" % [GameManager.player_data.level, roundi(100.0 * learned / maxf(total, 1))])
	_refresh_quests()
	_layout()


func _on_spec_pressed(spec_id: String) -> void:
	EventBus.go("mini_tree", {"spec_id": spec_id})


# ---------------------------------------------------------------- Экспедиция

func _build_expedition_button() -> void:
	var btn := Button.new()
	btn.text = "Экспедиция в руины"
	btn.icon = Palette.game_icon("portal")
	btn.theme_type_variation = &"AccentButton"
	btn.add_theme_constant_override("icon_max_width", 26)
	btn.add_theme_font_size_override("font_size", 16)
	btn.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	btn.offset_left = -270
	btn.offset_top = -66
	btn.offset_right = -18
	btn.offset_bottom = -18
	btn.tooltip_text = "Исследуй сломанный механический город: диалоги, загадки, сейфы с Python-кодом и карточные бои"
	btn.pressed.connect(_open_expedition_prep)
	add_child(btn)


func _open_expedition_prep() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	var brass := Color("#C9A24A")
	panel.add_theme_stylebox_override("panel", Palette.glow_box(Color("#120F0A", 0.97), brass, Color(brass, 0.3), 16, 14))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 600
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var title := Label.new()
	title.text = "Руины Феррограда"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_color_override("font_color", brass.lightened(0.3))
	box.add_child(title)
	var lore := Label.new()
	lore.text = "Великий Механизм остановился, и порча свела автоматонов с ума. В руинах тебя ждут жители, которым пригодятся твои знания, двери-загадки, сейфы с испорченным Python-кодом и порченые машины. Три этажа вниз — к Сердцу Механизма."
	lore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	lore.add_theme_color_override("font_color", Color("#E8DCC0"))
	box.add_child(lore)
	var p := GameManager.player_data
	var energy_ok: bool = p.energy >= XPCalculator.DUNGEON_ENERGY_COST
	var deck_ok := GameManager.deck_ready()
	var req := RichTextLabel.new()
	req.bbcode_enabled = true
	req.fit_content = true
	req.text = "%s Энергия: %d / %d (нужно %d — учи темы: +5 за каждую)\n%s Колода: %d карт (нужно минимум %d — собери в «Персонаж → Колода»)\n[color=#8C8CB0]HP в экспедиции: %d. Поражение в бою — возврат в лагерь и потеря 20%% золота.[/color]" % [
		"[color=#00D4AA]✓[/color]" if energy_ok else "[color=#FF6B6B]✗[/color]", p.energy, p.max_energy, XPCalculator.DUNGEON_ENERGY_COST,
		"[color=#00D4AA]✓[/color]" if deck_ok else "[color=#FF6B6B]✗[/color]", GameManager.combat_deck.size(), XPCalculator.MIN_DECK_SIZE, p.max_hp]
	box.add_child(req)
	var stats: Dictionary = GameManager.world.get("stats", {})
	if stats.get("expeditions", 0) > 0:
		var st := Label.new()
		st.text = "Экспедиций: %d · глубина: %d · побед: %d · загадок: %d · сейфов: %d" % [stats.get("expeditions", 0), stats.get("deepest_floor", 0), stats.get("fights_won", 0), stats.get("riddles", 0), stats.get("safes", 0)]
		st.theme_type_variation = &"DimLabel"
		box.add_child(st)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	var go := Button.new()
	go.text = "Отправиться (−%d энергии)" % XPCalculator.DUNGEON_ENERGY_COST
	go.theme_type_variation = &"AccentButton"
	go.disabled = not (energy_ok and deck_ok)
	go.pressed.connect(func():
		overlay.queue_free()
		EventBus.go("dungeon"))
	row.add_child(go)
	if not deck_ok:
		var deck_btn := Button.new()
		deck_btn.text = "Собрать колоду"
		deck_btn.pressed.connect(func():
			overlay.queue_free()
			EventBus.go("character", {"tab": 2}))
		row.add_child(deck_btn)
	var cancel := Button.new()
	cancel.text = "Не сейчас"
	cancel.theme_type_variation = &"GhostButton"
	cancel.pressed.connect(overlay.queue_free)
	row.add_child(cancel)


# ---------------------------------------------------------------- Туториал «Путь новичка»

func _refresh_quests() -> void:
	for child in quest_list.get_children():
		child.queue_free()
	var first_spec := "python_developer" if "python_developer" in ContentParser.get_all_spec_ids() else ""
	var first_learned := GameManager.count_learned(first_spec) > 0 if first_spec != "" else GameManager.total_learned() > 0
	var steps := [
		["Изучи первый узел Python Developer → получи XP", first_learned],
		["Получи первую карту — пройди общий тест дерева", GameManager.collection_size() > 0],
		["Собери колоду из %d+ карт" % XPCalculator.MIN_DECK_SIZE, GameManager.combat_deck.size() >= XPCalculator.MIN_DECK_SIZE],
		["Войди в подземелье (стоит %d энергии)" % XPCalculator.DUNGEON_ENERGY_COST, GameManager.player_data.get("dungeon_runs", 0) > 0],
	]
	var current_found := false
	var all_done := true
	for step in steps:
		var done: bool = step[1]
		all_done = all_done and done
		var is_current := not done and not current_found
		if is_current:
			current_found = true
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		var icon := TextureRect.new()
		icon.texture = Palette.icon("check" if done else "circle-dot")
		icon.custom_minimum_size = Vector2(18, 18)
		icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		icon.modulate = Palette.MINT if done else (Palette.ENERGY if is_current else Palette.TEXT_FAINT)
		row.add_child(icon)
		var label := Label.new()
		label.text = step[0]
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color", Palette.MINT if done else (Palette.TEXT if is_current else Palette.TEXT_FAINT))
		row.add_child(label)
		quest_list.add_child(row)
	quest_panel.visible = not all_done
