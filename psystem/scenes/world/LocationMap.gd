extends Control
## Карта локации — топографическая: отмывка рельефа, послойная окраска высот и горизонтали (каждые 1.5 м),
## тропы, реки и пропасти, названия районов, указатели (точки быстрого перемещения: найдено n из m) и входы
## в пещеры. Неисследованное — в тумане. Наведение — высота точки.
## На базе: выбрать район с найденным указателем (или посещённую пещеру) → «Вылазка».
## Во время вылазки (params.in_sortie, клавиша M): «ты здесь» со стрелкой взгляда, быстрое перемещение
## (params.on_travel), кнопка «Карта мира». params.view_only — только просмотр (из карты мира в вылазке).

const PX := 3                       # пикселей карты на метр
const CONTOUR := 1.5                # шаг горизонталей, м
const PAD := 4                      # метров рамки вокруг проходимой карты

static var _image_cache: Dictionary = {}

var location_id := ""
var _loc: Dictionary = {}
var _surf: Dictionary = {}
var _in_sortie := false
var _view_only := false
var _current := ""
var _minimap_tex: Texture2D
var _on_travel: Callable
var _player_pos := Vector2.INF
var _player_yaw := 0.0
var _selected := ""

var _map_rect: TextureRect
var _fog_rect: TextureRect
var _overlay: Control
var _panel_box: VBoxContainer
var _title: Label
var _progress: Label
var _hover_label: Label
var _markers: Array = []            # {button, world: Vector2, region|cave}
var _hmin := 0.0
var _hmax := 1.0


func setup(params: Dictionary) -> void:
	location_id = params.get("location_id", "whisper_grove")
	_in_sortie = params.get("in_sortie", false)
	_view_only = params.get("view_only", false)
	_current = params.get("current", "")
	_minimap_tex = params.get("minimap", null)
	_on_travel = params.get("on_travel", Callable())
	_player_pos = params.get("player", Vector2.INF)
	_player_yaw = params.get("player_yaw", 0.0)
	_loc = WorldData.location(location_id)
	_surf = OutdoorGenerator.generate_surface(location_id)
	_build()
	var first := _current
	if first == "":
		first = WorldData.start_node(location_id)
		for id in _loc.order:
			if WorldData.is_open(location_id, id) and not WorldData.is_underground(_loc.nodes[id]):
				first = id
	_select(first)


func _unhandled_input(event: InputEvent) -> void:
	if _in_sortie and event.is_action_pressed("map"):
		get_viewport().set_input_as_handled()
		EventBus.back()


func on_resume() -> void:
	_refresh_markers()
	_refresh_header()
	_select(_selected)


# ---------------------------------------------------------------- Построение

func _build() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#1A1712")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)
	var area := Control.new()
	area.name = "MapArea"
	area.set_anchors_preset(Control.PRESET_FULL_RECT)
	area.offset_left = 16
	area.offset_top = 70
	area.offset_right = -346
	area.offset_bottom = -44
	area.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(area)
	_map_rect = TextureRect.new()
	_map_rect.texture = _topo_texture()
	_map_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_map_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_map_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_map_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_map_rect.gui_input.connect(_on_map_input)
	area.add_child(_map_rect)
	_fog_rect = TextureRect.new()
	_fog_rect.texture = _fog_texture()
	_fog_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_fog_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_fog_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fog_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	area.add_child(_fog_rect)
	_overlay = Control.new()
	_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_overlay.draw.connect(_draw_overlay)
	area.add_child(_overlay)
	area.resized.connect(func():
		_place_markers()
		_overlay.queue_redraw())

	# Верхняя строка
	var top := HBoxContainer.new()
	top.position = Vector2(16, 12)
	top.add_theme_constant_override("separation", 12)
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
	_title.add_theme_font_size_override("font_size", 24)
	tb.add_child(_title)
	_progress = Label.new()
	_progress.add_theme_color_override("font_color", Color("#FFF2D6"))
	_progress.add_theme_font_size_override("font_size", 13)
	tb.add_child(_progress)

	# Нижняя строка: высота под курсором, легенда
	_hover_label = Label.new()
	_hover_label.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	_hover_label.offset_left = 18
	_hover_label.offset_top = -36
	_hover_label.offset_bottom = -12
	_hover_label.offset_right = 600
	_hover_label.theme_type_variation = &"MonoLabel"
	_hover_label.add_theme_font_size_override("font_size", 13)
	add_child(_hover_label)
	var legend := _legend()
	legend.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	legend.offset_left = -346 - 460
	legend.offset_right = -346 - 16
	legend.offset_top = -38
	legend.offset_bottom = -14
	add_child(legend)

	var panel := PanelContainer.new()
	panel.theme_type_variation = &"GlassPanel"
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -330
	panel.offset_right = -14
	panel.offset_top = 14
	panel.offset_bottom = -14
	add_child(panel)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	_panel_box = VBoxContainer.new()
	_panel_box.add_theme_constant_override("separation", 10)
	_panel_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_panel_box)

	_build_markers()
	_refresh_header()
	_place_markers.call_deferred()


func _legend() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.alignment = BoxContainer.ALIGNMENT_END
	var lo := Label.new()
	lo.text = "%d м" % roundi(_hmin)
	lo.theme_type_variation = &"MonoLabel"
	lo.add_theme_font_size_override("font_size", 11)
	row.add_child(lo)
	var grad := Gradient.new()
	grad.offsets = PackedFloat32Array([0.0, 0.25, 0.5, 0.75, 1.0])
	grad.colors = PackedColorArray([_hypso(0.0), _hypso(0.25), _hypso(0.5), _hypso(0.75), _hypso(1.0)])
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.width = 128
	gt.height = 8
	var bar := TextureRect.new()
	bar.texture = gt
	bar.custom_minimum_size = Vector2(130, 10)
	bar.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(bar)
	var hi := Label.new()
	hi.text = Loc.t("%d м · горизонтали через %s м") % [roundi(_hmax), str(CONTOUR)]
	hi.theme_type_variation = &"MonoLabel"
	hi.add_theme_font_size_override("font_size", 11)
	row.add_child(hi)
	return row


func _refresh_header() -> void:
	var info := WorldData.location_info(location_id)
	var signs := WorldData.signs_found(location_id)
	_title.text = info.get("name", location_id)
	_progress.text = Loc.t("Исследовано: %d%% · указатели: %d из %d · рекомендуемый уровень %d · энергия %d / %d") % [
		roundi(WorldData.location_progress(location_id) * 100.0), signs.x, signs.y, int(info.get("level", 1)),
		int(GameManager.player_data.energy), int(GameManager.player_data.max_energy)]


# ---------------------------------------------------------------- Топографическое изображение

## Отмывка рельефа + послойная окраска + горизонтали; тропы, вода, пропасти. Кэшируется по локации.
func _topo_texture() -> Texture2D:
	var w: int = _surf.w + PAD * 2
	var h: int = _surf.h + PAD * 2
	var terrain: Dictionary = _surf.terrain
	# Диапазон высот проходимой карты
	_hmin = INF
	_hmax = -INF
	var hs := PackedFloat32Array()
	hs.resize(w * PX * h * PX)
	for py in h * PX:
		for px in w * PX:
			var wx := float(px) / PX - PAD
			var wz := float(py) / PX - PAD
			var hgt := OutdoorGenerator.height_at(terrain, wx, wz)
			hs[py * w * PX + px] = hgt
			_hmin = minf(_hmin, hgt)
			_hmax = maxf(_hmax, hgt)
	var key: String = location_id
	if _image_cache.has(key):
		return _image_cache[key]
	var img := Image.create(w * PX, h * PX, false, Image.FORMAT_RGB8)
	var iw := w * PX
	var grid: PackedByteArray = _surf.grid
	for py in h * PX:
		for px in iw:
			var i := py * iw + px
			var hgt := hs[i]
			var t := (hgt - _hmin) / maxf(_hmax - _hmin, 0.01)
			var col := _hypso(t)
			# Отмывка: освещение с северо-запада по наклону
			var hx := hs[mini(i + 1, hs.size() - 1)] - hs[maxi(i - 1, 0)]
			var hz := hs[mini(i + iw, hs.size() - 1)] - hs[maxi(i - iw, 0)]
			var shade := clampf(0.82 - (hx + hz) * 0.9, 0.45, 1.25)
			col = col * shade
			# Горизонтали
			var band := floori(hgt / CONTOUR)
			var bx := floori(hs[mini(i + 1, hs.size() - 1)] / CONTOUR)
			var bz := floori(hs[mini(i + iw, hs.size() - 1)] / CONTOUR)
			if band != bx or band != bz:
				col = col.darkened(0.35 if band % 4 == 0 else 0.18)
			var cx := px / PX - PAD
			var cz := py / PX - PAD
			if cx >= 0 and cz >= 0 and cx < _surf.w and cz < _surf.h:
				var v := grid[cz * _surf.w + cx]
				if v == OutdoorGenerator.PATH:
					col = col.lerp(Color("#C9A66B"), 0.55)
				elif v == OutdoorGenerator.CHASM:
					var water := false
					for ch in _surf.chasms:
						if (ch.rect as Rect2i).has_point(Vector2i(cx, cz)):
							water = ch.water
					col = Color("#3F7FB8") if water else Color("#120F14")
			img.set_pixel(px, py, Color(col.r, col.g, col.b))
	var tex := ImageTexture.create_from_image(img)
	_image_cache[key] = tex
	return tex


## Цвет высоты: низины — зелень, склоны — охра и камень, вершины — светлые.
func _hypso(t: float) -> Color:
	var stops := [Color("#5E8C46"), Color("#86A85A"), Color("#B9A56A"), Color("#8E7D64"), Color("#D8D2C4")]
	var f := clampf(t, 0.0, 1.0) * (stops.size() - 1)
	var k := mini(int(f), stops.size() - 2)
	return (stops[k] as Color).lerp(stops[k + 1], f - k)


## Туман над неисследованным (маска исследованного поверхности из состояния локации).
func _fog_texture() -> Texture2D:
	var w: int = _surf.w + PAD * 2
	var h: int = _surf.h + PAD * 2
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.08, 0.07, 0.06, 0.62))
	var st: Dictionary = WorldData.loc_state(location_id).get("surface", {})
	var size: int = _surf.w * _surf.h
	if int(st.get("explored_size", 0)) == size:
		var raw := Marshalls.base64_to_raw(String(st.get("explored", ""))).decompress(size, FileAccess.COMPRESSION_DEFLATE)
		if raw.size() == size:
			for i in size:
				if raw[i] == 1:
					img.set_pixel(i % _surf.w + PAD, i / _surf.w + PAD, Color(0, 0, 0, 0))
	# Найденные указатели раскрывают свой район
	for sp in _surf.signposts:
		if WorldData.is_sign_found(location_id, sp.region) or WorldData.node_state(location_id, sp.region).visited:
			for dy in range(-8, 9):
				for dx in range(-8, 9):
					if dx * dx + dy * dy <= 64:
						var x: int = sp.cell.x + dx + PAD
						var y: int = sp.cell.y + dy + PAD
						if x >= 0 and y >= 0 and x < w and y < h:
							img.set_pixel(x, y, Color(0, 0, 0, 0))
	img.resize(w * PX, h * PX, Image.INTERPOLATE_BILINEAR)
	return ImageTexture.create_from_image(img)


# ---------------------------------------------------------------- Метки

func _build_markers() -> void:
	for sp in _surf.signposts:
		var b := _marker_button("wooden-sign")
		b.pressed.connect(_on_marker.bind(sp.region))
		_markers.append({"button": b, "world": Vector2(sp.cell) + Vector2(0.5, 0.5), "id": sp.region, "kind": "sign"})
	for c in _surf.caves:
		var icon: String = {"cave": "cave-entrance", "crypt": "crypt-entrance", "stairs_down": "dungeon-gate"}.get(c.kind, "cave-entrance")
		var b := _marker_button(icon)
		b.pressed.connect(_on_marker.bind(c.to))
		_markers.append({"button": b, "world": Vector2(c.cell) + Vector2(0.5, 0.5), "id": c.to, "kind": "cave", "region": c.region})
	_refresh_markers()


func _marker_button(icon: String) -> Button:
	var b := Button.new()
	b.icon = Palette.game_icon(icon)
	b.flat = true
	b.expand_icon = true
	b.custom_minimum_size = Vector2(28, 28)
	b.size = Vector2(28, 28)
	b.add_theme_stylebox_override("normal", Palette.box(Color("#0B0A14", 0.7), Color(1, 1, 1, 0.3), 1, 14, 2, 2))
	b.add_theme_stylebox_override("hover", Palette.box(Color("#2A2440", 0.9), Palette.ENERGY, 2, 14, 2, 2))
	b.add_theme_stylebox_override("pressed", Palette.box(Color("#2A2440", 0.9), Palette.ENERGY, 2, 14, 2, 2))
	_overlay.add_child(b)
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	return b


## Видимость и цвет меток: найденные указатели и входы — ярко, известные районы — тускло, остальное скрыто.
func _refresh_markers() -> void:
	for m in _markers:
		var b: Button = m.button
		if m.kind == "sign":
			var found := WorldData.is_sign_found(location_id, m.id)
			var status := WorldData.node_status(location_id, m.id)
			b.visible = found or status != "hidden"
			b.modulate = Color("#F5C542") if found else Color(1, 1, 1, 0.45)
			b.tooltip_text = _loc.nodes[m.id].name + ("" if found else "\n" + Loc.t("Указатель ещё не найден"))
		else:
			var known: bool = m.id in WorldData.node_state(location_id, m.region).get("exits", []) or WorldData.node_state(location_id, m.id).visited
			b.visible = known
			b.modulate = Color("#C9A8FF")
			b.tooltip_text = _loc.nodes[m.id].name
	_overlay.queue_redraw()


## Прямоугольник изображения внутри TextureRect (с сохранением пропорций).
func _image_rect() -> Rect2:
	var tex_size := _map_rect.texture.get_size()
	var box := _map_rect.size
	var k := minf(box.x / tex_size.x, box.y / tex_size.y)
	var s := tex_size * k
	return Rect2((box - s) * 0.5, s)


func _to_screen(world: Vector2) -> Vector2:
	var r := _image_rect()
	var w: float = _surf.w + PAD * 2
	var h: float = _surf.h + PAD * 2
	return r.position + Vector2((world.x + PAD) / w * r.size.x, (world.y + PAD) / h * r.size.y)


func _to_world(screen: Vector2) -> Vector2:
	var r := _image_rect()
	var w: float = _surf.w + PAD * 2
	var h: float = _surf.h + PAD * 2
	return Vector2((screen.x - r.position.x) / r.size.x * w - PAD, (screen.y - r.position.y) / r.size.y * h - PAD)


func _place_markers() -> void:
	for m in _markers:
		var b: Button = m.button
		b.position = _to_screen(m.world) - b.size * 0.5


func _draw_overlay() -> void:
	var font := Palette.FONT_UI_BOLD
	for r in _surf.regions:
		var status := WorldData.node_status(location_id, r.id)
		if status == "hidden":
			continue
		var p := _to_screen(r.center) + Vector2(0, -26)
		var text: String = r.name
		var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
		draw_string_outline_on(p - Vector2(tw * 0.5, 0), text, 14, Color(0, 0, 0, 0.85), Color("#FFF2D6") if r.id != _selected else Palette.ENERGY)
	for m in _markers:
		if m.kind == "cave" and m.button.visible:
			var p: Vector2 = _to_screen(m.world) + Vector2(0, 26)
			var text: String = _loc.nodes[m.id].name
			var tw := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, 11).x
			draw_string_outline_on(p - Vector2(tw * 0.5, 0), text, 11, Color(0, 0, 0, 0.85), Color("#D9C8FF"))
	if _player_pos != Vector2.INF:
		var c := _to_screen(_player_pos)
		var fwd := Vector2(sin(_player_yaw), cos(_player_yaw))
		var side := fwd.orthogonal()
		var tip := c + fwd * 13.0
		var pts := PackedVector2Array([tip, c - fwd * 7.0 + side * 8.0, c - fwd * 3.0, c - fwd * 7.0 - side * 8.0])
		_overlay.draw_colored_polygon(pts, Palette.MINT)
		_overlay.draw_polyline(PackedVector2Array([pts[0], pts[1], pts[2], pts[3], pts[0]]), Color(0, 0, 0, 0.9), 2.0)


func draw_string_outline_on(pos: Vector2, text: String, size_px: int, outline: Color, color: Color) -> void:
	_overlay.draw_string_outline(Palette.FONT_UI_BOLD, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, 5, outline)
	_overlay.draw_string(Palette.FONT_UI_BOLD, pos, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size_px, color)


func _on_map_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var wp := _to_world(event.position)
		var hgt := OutdoorGenerator.height_at(_surf.terrain, wp.x, wp.y)
		var rid := OutdoorGenerator.region_at(_surf, wp)
		var name := ""
		if WorldData.node_status(location_id, rid) != "hidden":
			name = _loc.nodes[rid].name + " · "
		_hover_label.text = Loc.t("%sвысота %d м · координаты %d, %d") % [name, roundi(hgt), roundi(wp.x), roundi(wp.y)]
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var rid := OutdoorGenerator.region_at(_surf, _to_world(event.position))
		if WorldData.node_status(location_id, rid) != "hidden":
			_on_marker(rid)


func _on_marker(id: String) -> void:
	Audio.play("select")
	_select(id)


# ---------------------------------------------------------------- Панель

func _select(node_id: String) -> void:
	_selected = node_id
	_overlay.queue_redraw()
	for c in _panel_box.get_children():
		c.queue_free()
	var n := WorldData.node(location_id, node_id)
	if n.is_empty():
		return
	var status := WorldData.node_status(location_id, node_id)
	var under := WorldData.is_underground(n)
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
	kind_label.text = Loc.t(kind.get("name", "")) + (" · " + Loc.t("под землёй") if under else "")
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
	if not under:
		var r := _region_data(node_id)
		if not r.is_empty():
			lines.append(Loc.t("Высота района: %d м") % roundi(float(r.elev)))
	var feat := Label.new()
	feat.text = "• " + "\n• ".join(lines)
	feat.add_theme_font_size_override("font_size", 13)
	_panel_box.add_child(feat)

	if status in ["visited", "cleared"]:
		var pl := Label.new()
		pl.text = Loc.t("Исследовано: %d%%") % roundi(WorldData.node_progress(location_id, node_id) * 100.0)
		pl.add_theme_color_override("font_color", Palette.MINT)
		_panel_box.add_child(pl)
	if not under:
		var sl := Label.new()
		sl.text = Loc.t("Указатель найден — точка быстрого перемещения") if WorldData.is_sign_found(location_id, node_id) else Loc.t("Указатель района ещё не найден")
		sl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sl.custom_minimum_size.x = 280
		sl.add_theme_color_override("font_color", Palette.GOLD if WorldData.is_sign_found(location_id, node_id) else Palette.TEXT_DIM)
		_panel_box.add_child(sl)
	if _in_sortie and _minimap_tex and node_id == _current:
		var here := Label.new()
		here.text = Loc.t("Ты здесь. Исследованная часть подземелья:")
		here.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		here.custom_minimum_size.x = 280
		here.add_theme_color_override("font_color", Palette.MINT)
		_panel_box.add_child(here)
		var mm := TextureRect.new()
		mm.texture = _minimap_tex
		mm.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		mm.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mm.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mm.custom_minimum_size = Vector2(290, 180)
		_panel_box.add_child(mm)

	var open := WorldData.is_open(location_id, node_id)
	if _view_only:
		pass
	elif _in_sortie:
		if open and node_id != _current:
			var tr := Button.new()
			tr.text = Loc.t("Быстрое перемещение")
			tr.icon = Palette.game_icon("footprint")
			tr.add_theme_constant_override("icon_max_width", 22)
			tr.theme_type_variation = &"AccentButton"
			tr.custom_minimum_size.y = 46
			tr.pressed.connect(_travel.bind(node_id))
			_panel_box.add_child(tr)
	elif open:
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
	elif status != "hidden":
		var lock := Label.new()
		lock.text = Loc.t("Сюда пока не добраться быстро: найди указатель района (или вход в пещеру) во время вылазки.")
		lock.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		lock.custom_minimum_size.x = 280
		lock.add_theme_color_override("font_color", Palette.ENERGY)
		_panel_box.add_child(lock)
	# Подземелья района
	if not under:
		for c in _surf.caves:
			if c.region != node_id:
				continue
			var known: bool = c.to in WorldData.node_state(location_id, node_id).get("exits", [])
			var cl := Button.new()
			cl.text = (Loc.t("Вход: %s") % c.to_name) if known else Loc.t("Неизвестный вход")
			cl.flat = true
			cl.alignment = HORIZONTAL_ALIGNMENT_LEFT
			cl.disabled = not known
			cl.pressed.connect(_select.bind(c.to))
			_panel_box.add_child(cl)


func _region_data(id: String) -> Dictionary:
	for r in _surf.regions:
		if r.id == id:
			return r
	return {}


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
