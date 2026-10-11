extends Control
## Глобальная карта: 100 локаций с рекомендуемым уровнем и процентом исследования.
## Идти можно в любую реализованную локацию (уровень — только рекомендация), остальные — «в разработке».
## Перетаскивание — панорама, колесо — масштаб.

const MAP_SIZE := Vector2(2400, 1500)
const SHADER := preload("res://shaders/world_map.gdshader")
const BIOME_ORDER := ["forest", "meadow", "ruins", "swamp", "mountains", "snow", "desert", "coast", "volcano", "dark", "caves"]
const MAP_COLORS := {
	"forest": "#4C8F35", "meadow": "#93C25A", "ruins": "#BFAE84", "swamp": "#5F7A45", "mountains": "#9C9283",
	"snow": "#E8F1F7", "desert": "#E4C47E", "coast": "#86C278", "volcano": "#8A3A2A", "dark": "#5B4A72", "caves": "#857A9B",
}

static var _land_tex: ImageTexture
static var _land_img: Image

var _view: Control
var _canvas: Control
var _decor: Control
var _markers: Dictionary = {}
var _glyph_cache: Dictionary = {}
var _zoom := 1.0
var _dragging := false
var _drag_moved := 0.0
var _panel: PanelContainer
var _panel_box: VBoxContainer
var _selected := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	clip_contents = true
	_view = Control.new()
	_view.set_anchors_preset(Control.PRESET_FULL_RECT)
	_view.clip_contents = true
	_view.mouse_filter = Control.MOUSE_FILTER_STOP
	_view.gui_input.connect(_on_view_input)
	add_child(_view)
	_canvas = Control.new()
	_canvas.size = MAP_SIZE
	_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_view.add_child(_canvas)
	_build_background()
	_decor = Control.new()
	_decor.size = MAP_SIZE
	_decor.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for g in ["pine-tree", "mountains", "volcano", "desert", "swamp", "evil-tree", "grass", "crystal-cluster"]:
		_glyph_cache[g] = Palette.game_icon(g)   # заранее: load() внутри draw даёт пустой квадрат
	_decor.draw.connect(_draw_decor)
	_canvas.add_child(_decor)
	_build_markers()
	_build_ui()
	_center_on(Vector2(WorldData.camp().pos[0], WorldData.camp().pos[1]) * MAP_SIZE, 1.0)
	_select("whisper_grove")


func on_resume() -> void:
	for id in _markers:
		_markers[id].refresh()
	_select(_selected)


# ---------------------------------------------------------------- Фон

func _build_background() -> void:
	if _land_tex == null:
		_land_img = _make_land()
		_land_tex = ImageTexture.create_from_image(_land_img)
	var sites := Image.create(128, 1, false, Image.FORMAT_RGBAF)
	var locs := WorldData.map_locations()
	for i in locs.size():
		var l: Dictionary = locs[i]
		sites.set_pixel(i, 0, Color(l.pos[0], l.pos[1], float(BIOME_ORDER.find(l.biome)), 0))
	var bg := ColorRect.new()
	bg.size = MAP_SIZE
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat := ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("land", _land_tex)
	mat.set_shader_parameter("sites", ImageTexture.create_from_image(sites))
	mat.set_shader_parameter("site_count", locs.size())
	var colors: Array[Color] = []
	for b in BIOME_ORDER:
		colors.append(Color(MAP_COLORS[b]))
	mat.set_shader_parameter("biome_colors", colors)
	mat.set_shader_parameter("aspect", MAP_SIZE.x / MAP_SIZE.y)
	bg.material = mat
	_canvas.add_child(bg)


## Карта высот: эллипс материка + шум + «холмы» под каждой локацией (все локации на суше).
static func _make_land() -> Image:
	var w := 384
	var h := 240
	var noise := FastNoiseLite.new()
	noise.seed = 1337
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 5
	var nimg := noise.get_image(w, h)
	var img := Image.create(w, h, false, Image.FORMAT_L8)   # 8 бит: float-текстуры в GLES3 не фильтруются
	var values := PackedFloat32Array()
	values.resize(w * h)
	for y in h:
		for x in w:
			var u := (x + 0.5) / w
			var v := (y + 0.5) / h
			var dx := (u - 0.5) / 0.47
			var dy := (v - 0.5) / 0.46
			var fall := 1.0 - clampf(dx * dx + dy * dy, 0.0, 1.4)
			values[y * w + x] = fall * 0.62 + nimg.get_pixel(x, y).r * 0.42 - 0.05
	for l in WorldData.map_locations():
		var cx := int(l.pos[0] * w)
		var cy := int(l.pos[1] * h)
		for yy in range(cy - 14, cy + 15):
			for xx in range(cx - 14, cx + 15):
				if xx < 0 or yy < 0 or xx >= w or yy >= h:
					continue
				var d := Vector2(xx - cx, yy - cy).length() / 14.0
				if d < 1.0:
					var i := yy * w + xx
					values[i] = maxf(values[i], 0.5 + (1.0 - d) * 0.08)
	for y in h:
		for x in w:
			var hv := clampf(values[y * w + x], 0.0, 1.0)
			img.set_pixel(x, y, Color(hv, hv, hv))
	return img


func _is_land(p: Vector2) -> bool:
	var x := clampi(int(p.x / MAP_SIZE.x * _land_img.get_width()), 0, _land_img.get_width() - 1)
	var y := clampi(int(p.y / MAP_SIZE.y * _land_img.get_height()), 0, _land_img.get_height() - 1)
	return _land_img.get_pixel(x, y).r > 0.45


## Декор (деревья, горы, дюны…) и дороги рисуются поверх шейдерного фона.
func _draw_decor() -> void:
	var locs := WorldData.map_locations()
	var by_id := {}
	for l in locs:
		by_id[l.id] = Vector2(l.pos[0], l.pos[1]) * MAP_SIZE
	by_id["camp"] = Vector2(WorldData.camp().pos[0], WorldData.camp().pos[1]) * MAP_SIZE
	# Глифы биомов
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var glyphs := {"forest": "pine-tree", "mountains": "mountains", "snow": "mountains", "volcano": "volcano",
		"desert": "desert", "swamp": "swamp", "dark": "evil-tree", "meadow": "grass", "caves": "crystal-cluster"}
	var glyph_tex := {}
	for b in glyphs:
		glyph_tex[b] = _glyph_cache.get(glyphs[b])
	for i in 900:
		var p := Vector2(rng.randf() * MAP_SIZE.x, rng.randf() * MAP_SIZE.y)
		if not _is_land(p):
			continue
		var nearest: Dictionary = {}
		var nd := INF
		for l in locs:
			var d := p.distance_squared_to(by_id[l.id])
			if d < nd:
				nd = d
				nearest = l
		if nd < 60.0 * 60.0 or nd > 170.0 * 170.0:
			continue
		var g: String = glyphs.get(nearest.biome, "")
		var tex: Texture2D = glyph_tex.get(nearest.biome)
		if g == "" or tex == null:
			continue
		var s := rng.randf_range(20.0, 34.0) * (1.4 if g == "mountains" else 1.0)
		var c := Color(MAP_COLORS[nearest.biome]).darkened(0.45)
		if nearest.biome == "snow":
			c = Color("#9FB6C8")
		c.a = 0.55
		_decor.draw_texture_rect(tex, Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), false, c)
	# Дороги: пунктир цвета охры
	for r in WorldData.roads():
		if not by_id.has(r[0]) or not by_id.has(r[1]):
			continue
		var a: Vector2 = by_id[r[0]]
		var b: Vector2 = by_id[r[1]]
		var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * (a.distance_to(b) * 0.12) * (1 if hash(r[0] + r[1]) % 2 == 0 else -1)
		var prev := a
		var steps := int(a.distance_to(b) / 9.0)
		for k in range(1, steps + 1):
			var t := float(k) / steps
			var q := a.lerp(mid, t).lerp(mid.lerp(b, t), t)
			if k % 2 == 0:
				_decor.draw_line(prev, q, Color("#5A3E22", 0.75), 3.0, true)
			prev = q


# ---------------------------------------------------------------- Маркеры

func _build_markers() -> void:
	var camp := MapMarker.new()
	camp.setup_camp()
	camp.position = Vector2(WorldData.camp().pos[0], WorldData.camp().pos[1]) * MAP_SIZE - camp.size * 0.5
	camp.pressed.connect(func(): EventBus.notify("Лагерь искателей: здесь лавка и Древо знаний", "info"))
	_canvas.add_child(camp)
	for l in WorldData.map_locations():
		var m := MapMarker.new()
		m.setup(l)
		m.position = Vector2(l.pos[0], l.pos[1]) * MAP_SIZE - m.size * 0.5
		m.pressed.connect(_on_marker.bind(l.id))
		_canvas.add_child(m)
		_markers[l.id] = m


func _on_marker(loc_id: String) -> void:
	if _drag_moved > 8.0:
		return
	if _selected == loc_id and WorldData.is_playable(loc_id):
		_open_location(loc_id)
		return
	Audio.play("select")
	_select(loc_id)


func _select(loc_id: String) -> void:
	_selected = loc_id
	for id in _markers:
		_markers[id].set_selected(id == loc_id)
	_refresh_panel()


# ---------------------------------------------------------------- Панель

func _build_ui() -> void:
	var top := HBoxContainer.new()
	top.position = Vector2(16, 12)
	top.add_theme_constant_override("separation", 12)
	add_child(top)
	var back := Button.new()
	back.text = "Назад"
	back.icon = Palette.icon("arrow-left")
	back.pressed.connect(EventBus.back)
	top.add_child(back)
	var title := Label.new()
	title.text = "Карта мира"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	title.add_theme_constant_override("outline_size", 8)
	top.add_child(title)
	var open_count := 0
	for l in WorldData.map_locations():
		if WorldData.is_playable(l.id):
			open_count += 1
	var count := Label.new()
	count.text = Loc.t("Локаций: %d · доступно: %d · остальные в разработке") % [WorldData.map_locations().size(), open_count]
	count.add_theme_color_override("font_color", Color("#FFF2D6"))
	count.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	count.add_theme_constant_override("outline_size", 6)
	count.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	top.add_child(count)
	var hint := Label.new()
	hint.text = "Перетаскивай карту мышью · колесо — масштаб · двойной клик по локации — открыть"
	hint.add_theme_color_override("font_color", Color("#FFF2D6"))
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	hint.add_theme_constant_override("outline_size", 6)
	hint.add_theme_font_size_override("font_size", 12)
	hint.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	hint.offset_left = 16
	hint.offset_top = -30
	hint.offset_right = 700
	add_child(hint)

	_panel = PanelContainer.new()
	_panel.theme_type_variation = &"GlassPanel"
	_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	_panel.offset_left = -330
	_panel.offset_right = -14
	_panel.offset_top = 14
	_panel.offset_bottom = -14
	add_child(_panel)
	_panel_box = VBoxContainer.new()
	_panel_box.add_theme_constant_override("separation", 10)
	_panel.add_child(_panel_box)


func _refresh_panel() -> void:
	for c in _panel_box.get_children():
		c.queue_free()
	var l := WorldData.location_info(_selected)
	if l.is_empty():
		return
	var b := WorldData.biome(l.biome)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	_panel_box.add_child(head)
	var icon := TextureRect.new()
	icon.texture = Palette.game_icon(b.icon)
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = Color(b.color).lightened(0.2)
	head.add_child(icon)
	var name_box := VBoxContainer.new()
	name_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(name_box)
	var name_label := Label.new()
	name_label.text = l.name
	name_label.theme_type_variation = &"HeaderLabel"
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.custom_minimum_size.x = 220
	name_box.add_child(name_label)
	var biome_label := Label.new()
	biome_label.text = b.name
	biome_label.theme_type_variation = &"DimLabel"
	name_box.add_child(biome_label)

	var lvl: int = l.level
	var plvl: int = GameManager.player_data.level
	var lvl_color := Palette.MINT if lvl <= plvl + 1 else (Palette.ENERGY if lvl <= plvl + 4 else Palette.HP)
	var lvl_label := Label.new()
	lvl_label.text = Loc.t("Рекомендуемый уровень: %d (твой: %d)") % [lvl, plvl]
	lvl_label.add_theme_color_override("font_color", lvl_color)
	_panel_box.add_child(lvl_label)

	var playable := WorldData.is_playable(l.id)
	if playable:
		var pct := roundi(WorldData.location_progress(l.id) * 100.0)
		var pl := Label.new()
		pl.text = Loc.t("Исследовано: %d%%") % pct
		_panel_box.add_child(pl)
		var bar := ProgressBar.new()
		bar.show_percentage = false
		bar.custom_minimum_size.y = 10
		bar.value = pct
		bar.theme_type_variation = &"XPBar"
		_panel_box.add_child(bar)
		var desc := Label.new()
		desc.text = WorldData.location(l.id).get("desc", "")
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 280
		_panel_box.add_child(desc)
		var count_nodes: int = WorldData.location(l.id).order.size()
		var nodes_label := Label.new()
		nodes_label.text = Loc.t("Подлокаций: %d") % count_nodes
		nodes_label.theme_type_variation = &"DimLabel"
		_panel_box.add_child(nodes_label)
		var go := Button.new()
		go.text = "Открыть карту локации"
		go.icon = Palette.game_icon("treasure-map")
		go.add_theme_constant_override("icon_max_width", 22)
		go.theme_type_variation = &"AccentButton"
		go.custom_minimum_size.y = 44
		go.pressed.connect(_open_location.bind(l.id))
		_panel_box.add_child(go)
		if lvl > plvl + 2:
			var warn := Label.new()
			warn.text = "Враги здесь сильнее тебя. Идти можно, но будь готов отступить."
			warn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			warn.custom_minimum_size.x = 280
			warn.add_theme_color_override("font_color", Palette.ENERGY)
			_panel_box.add_child(warn)
	else:
		var desc := Label.new()
		desc.text = b.desc
		desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc.custom_minimum_size.x = 280
		_panel_box.add_child(desc)
		var wip := Label.new()
		wip.text = "🔨 В разработке"
		wip.add_theme_color_override("font_color", Palette.ENERGY)
		wip.add_theme_font_override("font", Palette.FONT_UI_BOLD)
		_panel_box.add_child(wip)
		var wip2 := Label.new()
		wip2.text = "Эта земля ещё не нанесена на карты искателей. Загляни после следующего обновления!"
		wip2.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		wip2.custom_minimum_size.x = 280
		wip2.theme_type_variation = &"DimLabel"
		_panel_box.add_child(wip2)


func _open_location(loc_id: String) -> void:
	Audio.play("open")
	EventBus.go("location", {"location_id": loc_id})


# ---------------------------------------------------------------- Панорама и масштаб

func _center_on(map_point: Vector2, zoom: float) -> void:
	_zoom = zoom
	_canvas.scale = Vector2.ONE * _zoom
	_canvas.position = size * 0.5 - map_point * _zoom
	_clamp_canvas()


func _clamp_canvas() -> void:
	var vs := size if size.x > 0 else Vector2(1280, 656)
	var cs := MAP_SIZE * _zoom
	_canvas.position.x = clampf(_canvas.position.x, minf(vs.x - cs.x, 0.0), maxf(0.0, vs.x - cs.x))
	_canvas.position.y = clampf(_canvas.position.y, minf(vs.y - cs.y, 0.0), maxf(0.0, vs.y - cs.y))


func _on_view_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var old := _zoom
			var minz := maxf(size.x / MAP_SIZE.x, size.y / MAP_SIZE.y)
			_zoom = clampf(_zoom * (1.12 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 1.12), minz, 1.8)
			var local: Vector2 = (event.position - _canvas.position) / old
			_canvas.scale = Vector2.ONE * _zoom
			_canvas.position = event.position - local * _zoom
			_clamp_canvas()


func _input(event: InputEvent) -> void:
	# Перетаскивание карты, начатое на маркере
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_drag_moved = 0.0
			_dragging = _view.get_global_rect().has_point(event.position) and not _panel.get_global_rect().has_point(event.position)
		else:
			_dragging = false
	elif event is InputEventMouseMotion and _dragging and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_drag_moved += event.relative.length()
		if _drag_moved > 6.0:
			_canvas.position += event.relative
			_clamp_canvas()
