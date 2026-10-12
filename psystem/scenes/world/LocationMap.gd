extends Control
## Карта локации: подлокации-кружки, связанные тропами (связный граф).
## Начать вылазку можно только в открытую подлокацию: стартовую или ту, проход в которую уже найден
## из соседней. Найденные проходы позволяют потом сразу отправляться в дальнюю точку.
## Во время вылазки (params.in_sortie, клавиша M) — карта всей локации: «ты здесь», исследованная часть
## текущей подлокации, быстрое перемещение в открытые подлокации (params.on_travel) и переход к карте мира.
## params.view_only — только просмотр (из карты мира во время вылазки).

const CANVAS := Vector2(1280, 600)
const SHADER := preload("res://shaders/world_map.gdshader")
const KIND_BIOME := {"meadow": 1, "forest": 0, "riverside": 7, "ruins": 2, "cave": 10, "tomb": 9, "dungeon": 4}

var location_id := ""
var _loc: Dictionary = {}
var _canvas: Control
var _paths: Control
var _nodes: Dictionary = {}
var _panel_box: VBoxContainer
var _title: Label
var _progress: Label
var _selected := ""
var _icon_cache := {}
var _in_sortie := false
var _view_only := false
var _current := ""
var _minimap_tex: Texture2D
var _on_travel: Callable
var _here: Label


func setup(params: Dictionary) -> void:
	location_id = params.get("location_id", "whisper_grove")
	_in_sortie = params.get("in_sortie", false)
	_view_only = params.get("view_only", false)
	_current = params.get("current", "")
	_minimap_tex = params.get("minimap", null)
	_on_travel = params.get("on_travel", Callable())
	_loc = WorldData.location(location_id)
	_build()
	_select(params.get("node_id", _current if _current != "" else _first_interesting()))


func _unhandled_input(event: InputEvent) -> void:
	if _in_sortie and event.is_action_pressed("map"):
		get_viewport().set_input_as_handled()
		EventBus.back()


func on_resume() -> void:
	for id in _nodes:
		_nodes[id].refresh()
	_paths.queue_redraw()
	_refresh_header()
	_select(_selected)


func _first_interesting() -> String:
	# Последняя открытая и не исследованная полностью подлокация
	var pick := WorldData.start_node(location_id)
	for id in _loc.order:
		var st := WorldData.node_status(location_id, id)
		if st == "open" or st == "visited":
			pick = id
	return pick


func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg_holder := Control.new()
	bg_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg_holder)
	_canvas = Control.new()
	_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_canvas)

	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	var land := Image.create(4, 4, false, Image.FORMAT_L8)
	land.fill(Color(0.8, 0.8, 0.8))
	mat.set_shader_parameter("land", ImageTexture.create_from_image(land))
	var sites := Image.create(128, 1, false, Image.FORMAT_RGBAF)
	var i := 0
	for id in _loc.order:
		var n: Dictionary = _loc.nodes[id]
		sites.set_pixel(i, 0, Color(n.pos[0], n.pos[1], float(KIND_BIOME.get(n.kind, 0)), 0))
		i += 1
	mat.set_shader_parameter("sites", ImageTexture.create_from_image(sites))
	mat.set_shader_parameter("site_count", i)
	var colors: Array[Color] = []
	for b in ["forest", "meadow", "ruins", "swamp", "mountains", "snow", "desert", "coast", "volcano", "dark", "caves"]:
		colors.append(Color(load("res://scenes/world/WorldMap.gd").MAP_COLORS[b]))
	mat.set_shader_parameter("biome_colors", colors)
	mat.set_shader_parameter("aspect", CANVAS.x / CANVAS.y)
	bg.material = mat
	bg_holder.add_child(bg)

	_paths = Control.new()
	_paths.set_anchors_preset(Control.PRESET_FULL_RECT)
	_paths.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paths.draw.connect(_draw_paths)
	_canvas.add_child(_paths)
	for id in _loc.order:
		var m := NodeMarker.new()
		m.setup(location_id, _loc.nodes[id])
		m.pressed.connect(_on_node.bind(id))
		_canvas.add_child(m)
		_nodes[id] = m
	resized.connect(_layout)
	_layout.call_deferred()

	var top := HBoxContainer.new()
	top.position = Vector2(16, 12)
	top.add_theme_constant_override("separation", 14)
	add_child(top)
	var back := Button.new()
	back.text = Loc.t("Карта мира") if not (_in_sortie or _view_only) else (Loc.t("К вылазке (%s)") % Settings.action_key_name("map") if _in_sortie else Loc.t("Назад"))
	back.icon = Palette.icon("arrow-left")
	back.pressed.connect(EventBus.back)
	top.add_child(back)
	if _in_sortie:
		var world := Button.new()
		world.text = Loc.t("Карта мира")
		world.icon = Palette.game_icon("treasure-map")
		world.add_theme_constant_override("icon_max_width", 20)
		world.pressed.connect(func(): EventBus.go("world_map", {"view_only": true}))
		top.add_child(world)
	var tb := VBoxContainer.new()
	tb.add_theme_constant_override("separation", 0)
	top.add_child(tb)
	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_font_size_override("font_size", 26)
	_title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_title.add_theme_constant_override("outline_size", 8)
	tb.add_child(_title)
	_progress = Label.new()
	_progress.add_theme_color_override("font_color", Color("#FFF2D6"))
	_progress.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_progress.add_theme_constant_override("outline_size", 6)
	tb.add_child(_progress)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"GlassPanel"
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -330
	panel.offset_right = -14
	panel.offset_top = 14
	panel.offset_bottom = -14
	add_child(panel)
	_panel_box = VBoxContainer.new()
	_panel_box.add_theme_constant_override("separation", 10)
	panel.add_child(_panel_box)
	_refresh_header()


func _refresh_header() -> void:
	var info := WorldData.location_info(location_id)
	_title.text = info.get("name", location_id)
	_progress.text = Loc.t("Исследовано: %d%% · рекомендуемый уровень %d · энергия %d / %d") % [
		roundi(WorldData.location_progress(location_id) * 100.0), int(info.get("level", 1)),
		int(GameManager.player_data.energy), int(GameManager.player_data.max_energy)]


## Узлы раскладываются в свободной области слева от панели.
func _area() -> Rect2:
	return Rect2(Vector2(40, 110), Vector2(maxf(size.x - 330 - 90, 300), maxf(size.y - 170, 200)))


func _layout() -> void:
	var area := _area()
	for id in _nodes:
		var n: Dictionary = _loc.nodes[id]
		_nodes[id].position = area.position + Vector2(n.pos[0], n.pos[1]) * area.size - _nodes[id].size * 0.5
	if _current != "" and _nodes.has(_current):
		if _here == null:
			_here = Label.new()
			_here.text = Loc.t("▼ Ты здесь")
			_here.add_theme_font_override("font", Palette.FONT_UI_BOLD)
			_here.add_theme_color_override("font_color", Palette.MINT)
			_here.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
			_here.add_theme_constant_override("outline_size", 6)
			_here.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_canvas.add_child(_here)
		var m: Control = _nodes[_current]
		_here.position = m.position + Vector2(m.size.x * 0.5 - 40, -26)
	_paths.queue_redraw()


func _draw_paths() -> void:
	var area := _area()
	var drawn := {}
	for id in _loc.order:
		var a: Dictionary = _loc.nodes[id]
		for other in a.links:
			var key: String = id + ">" + other if id < other else other + ">" + id
			if drawn.has(key) or not _loc.nodes.has(other):
				continue
			drawn[key] = true
			var sa := WorldData.node_status(location_id, id)
			var sb := WorldData.node_status(location_id, other)
			if sa == "hidden" and sb == "hidden":
				continue
			var found: bool = other in WorldData.node_state(location_id, id).exits or id in WorldData.node_state(location_id, other).exits
			var pa := area.position + Vector2(a.pos[0], a.pos[1]) * area.size
			var b: Dictionary = _loc.nodes[other]
			var pb := area.position + Vector2(b.pos[0], b.pos[1]) * area.size
			var color := Color("#4A2F18", 0.85) if found else Color("#2A1E14", 0.35)
			var width := 6.0 if found else 4.0
			var mid := (pa + pb) * 0.5 + (pb - pa).orthogonal().normalized() * pa.distance_to(pb) * 0.1
			var prev := pa
			var steps := int(pa.distance_to(pb) / 12.0)
			for k in range(1, steps + 1):
				var t := float(k) / steps
				var q := pa.lerp(mid, t).lerp(mid.lerp(pb, t), t)
				if found or k % 2 == 0:
					_paths.draw_line(prev, q, color, width, true)
				prev = q
			if found:
				var foot := _footprint()
				if foot:
					var fp := pa.lerp(mid, 0.5).lerp(mid.lerp(pb, 0.5), 0.5)
					_paths.draw_texture_rect(foot, Rect2(fp - Vector2(10, 10), Vector2(20, 20)), false, Color("#F7E7C6", 0.9))


func _footprint() -> Texture2D:
	if not _icon_cache.has("footprint"):
		_icon_cache["footprint"] = Palette.game_icon("footprint")
	return _icon_cache.footprint


func _on_node(node_id: String) -> void:
	var status := WorldData.node_status(location_id, node_id)
	if status == "hidden":
		EventBus.notify(Loc.t("Эта часть локации ещё не исследована"), "info")
		return
	if _selected == node_id and status in ["open", "visited", "cleared"] and not _view_only:
		if _in_sortie:
			_travel(node_id)
		else:
			_start(node_id)
		return
	Audio.play("select")
	_select(node_id)


func _select(node_id: String) -> void:
	_selected = node_id
	for id in _nodes:
		_nodes[id].set_selected(id == node_id)
	for c in _panel_box.get_children():
		c.queue_free()
	var n := WorldData.node(location_id, node_id)
	if n.is_empty():
		return
	var status := WorldData.node_status(location_id, node_id)
	var kind: Dictionary = WorldData.NODE_KINDS.get(n.kind, {})
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_panel_box.add_child(head)
	var icon := TextureRect.new()
	icon.texture = Palette.game_icon(kind.get("icon", "grass"))
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	head.add_child(icon)
	var nb := VBoxContainer.new()
	nb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(nb)
	var name_label := Label.new()
	name_label.text = n.name if status != "hidden" else "???"
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = 220
	nb.add_child(name_label)
	var kind_label := Label.new()
	kind_label.text = Loc.t(kind.get("name", "")) + (" · " + Loc.t("под землёй") if kind.get("underground", false) else "")
	kind_label.theme_type_variation = &"DimLabel"
	nb.add_child(kind_label)
	var desc := Label.new()
	desc.text = n.get("desc", "")
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.custom_minimum_size.x = 280
	_panel_box.add_child(desc)

	var f: Dictionary = n.get("features", {})
	var lines: PackedStringArray = []
	lines.append(Loc.t("Враги: %d") % int(f.get("enemies", 0)))
	lines.append(Loc.t("Сундуки: %d") % int(f.get("chests", 0)))
	if f.has("npcs"):
		lines.append(Loc.t("Жители: %d") % f.npcs.size())
	if f.get("safe", false):
		lines.append(Loc.t("Сейф с Python-кодом"))
	if f.get("riddle_gate", false):
		lines.append(Loc.t("Дверь-загадка"))
	if f.get("platforms", false):
		lines.append(Loc.t("Прыжки по движущимся платформам (падение — гибель!)"))
	if f.has("boss"):
		lines.append(Loc.t("Босс: %s") % _enemy_name(f.boss))
	var feat := Label.new()
	feat.text = "• " + "\n• ".join(lines)
	feat.add_theme_font_size_override("font_size", 13)
	_panel_box.add_child(feat)

	if status in ["visited", "cleared"]:
		var pct := roundi(WorldData.node_progress(location_id, node_id) * 100.0)
		var pl := Label.new()
		pl.text = Loc.t("Исследовано: %d%%") % pct
		pl.add_theme_color_override("font_color", Palette.MINT)
		_panel_box.add_child(pl)
	if _in_sortie and node_id == _current:
		var here := Label.new()
		here.text = Loc.t("Ты здесь. Исследованная часть подлокации:")
		here.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		here.custom_minimum_size.x = 280
		here.add_theme_color_override("font_color", Palette.MINT)
		_panel_box.add_child(here)
		if _minimap_tex:
			var mm := TextureRect.new()
			mm.texture = _minimap_tex
			mm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			mm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			mm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			mm.custom_minimum_size = Vector2(290, 180)
			_panel_box.add_child(mm)
		status = "current"
	elif _in_sortie and status in ["open", "visited", "cleared"]:
		var tr := Button.new()
		tr.text = Loc.t("Быстрое перемещение")
		tr.icon = Palette.game_icon("footprint")
		tr.add_theme_constant_override("icon_max_width", 22)
		tr.theme_type_variation = &"AccentButton"
		tr.custom_minimum_size.y = 46
		tr.pressed.connect(_travel.bind(node_id))
		_panel_box.add_child(tr)
		var th := Label.new()
		th.text = Loc.t("Проход сюда найден — перейдёшь к его указателю без траты энергии.")
		th.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		th.custom_minimum_size.x = 280
		th.theme_type_variation = &"DimLabel"
		_panel_box.add_child(th)
		status = "travel"
	if _view_only and status in ["open", "visited", "cleared"]:
		status = "view"
	match status:
		"open", "visited", "cleared":
			var go := Button.new()
			go.text = Loc.t("Вылазка (−%d энергии)") % XPCalculator.SORTIE_ENERGY_COST
			go.icon = Palette.game_icon("crossed-swords")
			go.add_theme_constant_override("icon_max_width", 22)
			go.theme_type_variation = &"AccentButton"
			go.custom_minimum_size.y = 46
			go.disabled = GameManager.player_data.energy < XPCalculator.SORTIE_ENERGY_COST
			go.pressed.connect(_start.bind(node_id))
			_panel_box.add_child(go)
			if go.disabled:
				var warn := Label.new()
				warn.text = Loc.t("Не хватает энергии. Изучай темы в Древе знаний: +5 энергии за каждую.")
				warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				warn.custom_minimum_size.x = 280
				warn.add_theme_color_override("font_color", Palette.HP)
				_panel_box.add_child(warn)
		"known":
			var lock := Label.new()
			lock.text = Loc.t("Проход сюда ещё не найден. Исследуй соседнюю подлокацию и найди точку перехода.")
			lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			lock.custom_minimum_size.x = 280
			lock.add_theme_color_override("font_color", Palette.ENERGY)
			_panel_box.add_child(lock)
	if _in_sortie or _view_only:
		return
	var hint := Label.new()
	hint.text = Loc.t("Управление в вылазке: WASD — ходьба, Shift — бег, %s — прыжок, E — действие, %s — инвентарь, %s — карта локации, %s — пауза, Esc — меню. Переходы — тропы за край карты и входы в пещеры.") % [Settings.action_key_name("jump"), Settings.action_key_name("inventory"), Settings.action_key_name("map"), Settings.action_key_name("pause")]
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size.x = 280
	hint.theme_type_variation = &"DimLabel"
	hint.add_theme_font_size_override("font_size", 12)
	_panel_box.add_child(hint)


static func _enemy_name(enemy_id: String) -> String:
	for e in CardDatabase.all_enemies():
		if e.id == enemy_id:
			return Loc.f(e, "name")
	return enemy_id


func _travel(node_id: String) -> void:
	Audio.play("whoosh")
	var cb := _on_travel
	EventBus.back()
	if cb.is_valid():
		cb.call(node_id)


func _start(node_id: String) -> void:
	if GameManager.player_data.energy < XPCalculator.SORTIE_ENERGY_COST:
		EventBus.notify(Loc.t("Не хватает энергии для вылазки"), "error")
		return
	Audio.play("whoosh")
	EventBus.go("sortie", {"location_id": location_id, "node_id": node_id})
