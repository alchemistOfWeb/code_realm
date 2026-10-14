extends Control
## Вылазка в локацию: единая поверхность (все наземные подлокации — районы одной карты с рельефом)
## и отдельные уровни пещер/гробниц/подземелий. Герой от третьего лица, враги, жители, сундуки, сейфы,
## двери-загадки, башни и плато, платформы над пропастью.
##
## Поток: карта локации → вылазка (−10 энергии) у найденного указателя района. Указатели — точки
## быстрого перемещения (сколько найдено из скольких — на карте). Вход в пещеру — шагни в проём в склоне.
## Поражение в бою — возврат в лагерь (без потери золота). Падение в пропасть — гибель: вся энергия
## теряется, герой возвращается на базу. Вместо мини-карты — полоска компаса.
## Управление: WASD, Shift — бег (выносливость), Space — прыжок, E — действие, I — инвентарь,
## M — карта локации (рельеф, указатели, быстрое перемещение, карта мира), P — пауза, Esc — меню.
## Камера: ПКМ — вращение, колесо — приближение, Q/R — поворот.

const NPC_LOOKS := {
	"greta": {"look": {"gender": "female", "race": "dwarf", "skin": 1, "hair": "Hair_Buns", "hair_color": 5, "outfit_variant": 1},
		"gear": {"outfit": {"body": "ranger", "arms": "ranger", "legs": "peasant", "feet": "ranger", "head": "", "shoulders": ""}, "variants": {"ranger": 0}, "weapon": "Hammer_Small", "offhand": ""}},
	"oracle": {"look": {"gender": "female", "race": "tiefling", "skin": 3, "hair": "Hair_Long", "hair_color": 7, "outfit_variant": 0},
		"gear": {"outfit": {"body": "ranger", "arms": "ranger", "legs": "ranger", "feet": "ranger", "head": "", "shoulders": "ranger"}, "variants": {"ranger": 1}, "weapon": "", "offhand": ""}},
	"lio": {"look": {"gender": "male", "race": "halfling", "skin": 1, "hair": "Hair_Long", "hair_color": 3, "outfit_variant": 1},
		"gear": {"outfit": {"body": "peasant", "arms": "peasant", "legs": "peasant", "feet": "peasant", "head": "", "shoulders": ""}, "variants": {"peasant": 1}, "weapon": "", "offhand": ""}},
	"cipher": {"look": {"gender": "male", "race": "elf", "skin": 3, "hair": "Hair_SimpleParted", "hair_color": 6, "outfit_variant": 0},
		"gear": {"outfit": {"body": "ranger", "arms": "ranger", "legs": "ranger", "feet": "ranger", "head": "ranger", "shoulders": ""}, "variants": {"ranger": 0}, "weapon": "", "offhand": ""}},
	"warden": {"scale": 1.4, "look": {"gender": "male", "race": "orc", "skin": 3, "hair": "Hair_Buzzed", "hair_color": 6, "outfit_variant": 0},
		"gear": {"outfit": {"body": "ranger", "arms": "ranger", "legs": "ranger", "feet": "ranger", "head": "", "shoulders": "ranger"}, "variants": {"ranger": 1}, "weapon": "Hammer_Double", "offhand": "Shield_Heater_2"}},
	"rzhavchik": {"monster": "Puglin", "scale": 1.1},
}
const INTERACT_DIST := 1.8
const DISCOVER_DIST := 4.0
const FOG_RADIUS := 9
## Указатель / проход считается найденным, когда герой подходит ближе этого.
const SIGN_DIST := 6.0
## Индексы сундуков на постройках (в node_state.chests рядом с обычными).
const HIGH_CHEST_BASE := 100
const COLUMN_CHEST_BASE := 200

var location_id := ""
var node_id := ""
var node: Dictionary = {}
var data: Dictionary = {}
var run := {}
var astar: AStarGrid2D

var _viewport: SubViewport
var _world: Node3D
var _player: SortiePlayer
var _interactables: Array = []      # {kind, node, pos, prompt, ...}
var _exits: Array = []              # {exit, trigger, armed, root, barrier, dir, sealed}
var _signs: Array = []              # {sign, pos}
var _surface := false
var _region_t := 0.0
var _compass: Control
var _explored_save_t := 0.0
var _gates: Array = []
var _gears: Array = []
var _enemies: Array = []
var _focus: Dictionary = {}
var _explored: PackedByteArray
var _map_image: Image
var _terrain_image: Image   # открытый рельеф мини-карты (без точек)
var _map_tex: ImageTexture
var _map_timer := 0.0
var _covered := false
var _paused := false
var _pending_actions: Array = []
var _combat_result: Dictionary = {}
var _combat_enemy: Node = null
var _combat_open_gate := false
var _ended := false
var _transitioning := false
var _falling := false

# UI
var _title: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _stamina_bar: ProgressBar
var _loot_label: Label
var _quests: RichTextLabel
var _prompt: PanelContainer
var _prompt_label: Label
var _pause_label: Control
var _menu: Control
var _fade: ColorRect
var _fps_label: Label
var _player_blob: MeshInstance3D   # тень-пятно героя, когда тени выключены
var _fps_t := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)
	EventBus.combat_finished.connect(_on_combat_finished)
	EventBus.dialogue_finished.connect(_on_dialogue_finished)
	EventBus.riddle_finished.connect(_on_riddle_finished)
	EventBus.safe_finished.connect(_on_safe_finished)
	GameManager.player_changed.connect(_update_hud)
	GameManager.world_changed.connect(_update_hud)


func setup(params: Dictionary) -> void:
	location_id = params.get("location_id", "whisper_grove")
	var start_id: String = params.get("node_id", "")
	if start_id == "":
		start_id = WorldData.start_node(location_id)
	_build_ui()
	if not params.get("free", false):
		if not GameManager.spend_energy(XPCalculator.SORTIE_ENERGY_COST):
			EventBus.notify(Loc.t("Не хватает энергии для вылазки"), "error")
			EventBus.back.call_deferred()
			return
	GameManager.player_data.hp = GameManager.player_data.max_hp
	GameManager.player_data.dungeon_runs = GameManager.player_data.get("dungeon_runs", 0) + 1
	GameManager.add_stat("expeditions")
	run = {"gold": 0, "fights": 0, "riddles": 0, "safes": 0, "items": [], "nodes": [], "seed_override": params.get("seed", -1),
		"used": {"riddles": [], "safes": []}}
	SaveSystem.save_all()
	var music: int = WorldData.location(location_id).get("music", 0)
	Audio.push_music(Audio.MUSIC[clampi(music, 0, Audio.MUSIC.size() - 1)].stream)
	if WorldData.is_underground(WorldData.node(location_id, start_id)):
		_load_node(start_id, _entry_for(start_id))
	else:
		var sp := _signpost_of(start_id)
		_load_surface(sp.get("arrive", OutdoorGenerator.generate_surface(location_id).start))


func _exit_tree() -> void:
	if not run.is_empty():
		Audio.pop_music()


## Откуда «входим» в пещеру при старте с карты: из района поверхности, где найден вход.
func _entry_for(id: String) -> String:
	for other in WorldData.node(location_id, id).get("links", []):
		if id in WorldData.node_state(location_id, other).exits:
			return other
	return ""


func _signpost_of(region: String) -> Dictionary:
	for sp in OutdoorGenerator.generate_surface(location_id).signposts:
		if sp.region == region:
			return sp
	return {}


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	var q := WorldStyle.quality()
	_viewport.msaa_3d = Viewport.MSAA_2X if q.msaa else Viewport.MSAA_DISABLED
	_viewport.scaling_3d_scale = float(q.scale_3d)
	_viewport.mesh_lod_threshold = float(q.lod)
	RenderingServer.directional_shadow_atlas_set_size(int(q.shadow_size), true)
	_viewport.handle_input_locally = false
	container.add_child(_viewport)

	var info := PanelContainer.new()
	info.theme_type_variation = &"GlassPanel"
	info.position = Vector2(14, 12)
	info.custom_minimum_size = Vector2(320, 0)
	add_child(info)
	var ib := VBoxContainer.new()
	ib.add_theme_constant_override("separation", 4)
	info.add_child(ib)
	_title = Label.new()
	_title.theme_type_variation = &"HeaderLabel"
	_title.add_theme_font_size_override("font_size", 15)
	_title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	ib.add_child(_title)
	var hp_row := HBoxContainer.new()
	ib.add_child(hp_row)
	var hp_icon := TextureRect.new()
	hp_icon.texture = Palette.icon("heart")
	hp_icon.custom_minimum_size = Vector2(16, 16)
	hp_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	hp_icon.modulate = Palette.HP
	hp_row.add_child(hp_icon)
	_hp_bar = ProgressBar.new()
	_hp_bar.theme_type_variation = &"HPBar"
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(170, 12)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(_hp_bar)
	_hp_label = Label.new()
	_hp_label.theme_type_variation = &"MonoLabel"
	_hp_label.add_theme_color_override("font_color", Palette.HP)
	hp_row.add_child(_hp_label)
	var st_row := HBoxContainer.new()
	ib.add_child(st_row)
	var st_icon := TextureRect.new()
	st_icon.texture = Palette.icon("flame")
	st_icon.custom_minimum_size = Vector2(16, 16)
	st_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	st_icon.modulate = Palette.MINT
	st_icon.tooltip_text = Loc.t("Выносливость: тратится на бег (Shift)")
	st_row.add_child(st_icon)
	_stamina_bar = ProgressBar.new()
	_stamina_bar.show_percentage = false
	_stamina_bar.custom_minimum_size = Vector2(170, 8)
	_stamina_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_stamina_bar.add_theme_stylebox_override("fill", Palette.box(Palette.MINT, Color.TRANSPARENT, 0, 4, 0, 0))
	st_row.add_child(_stamina_bar)
	_loot_label = Label.new()
	_loot_label.theme_type_variation = &"MonoLabel"
	_loot_label.add_theme_color_override("font_color", Palette.GOLD)
	_loot_label.add_theme_font_size_override("font_size", 12)
	ib.add_child(_loot_label)
	_quests = RichTextLabel.new()
	_quests.bbcode_enabled = true
	_quests.fit_content = true
	_quests.custom_minimum_size.x = 300
	_quests.add_theme_font_size_override("normal_font_size", 13)
	ib.add_child(_quests)

	_compass = preload("res://scenes/world/CompassBar.gd").new()
	add_child(_compass)

	var help := Label.new()
	help.text = Loc.t("WASD — ходьба · Shift — бег · %s — прыжок · E — действие · %s — инвентарь · %s — карта · %s — пауза · Esc — меню · ПКМ — камера") % [Settings.action_key_name("jump"), Settings.action_key_name("inventory"), Settings.action_key_name("map"), Settings.action_key_name("pause")]
	help.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	help.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	help.add_theme_constant_override("outline_size", 5)
	help.add_theme_font_size_override("font_size", 12)
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.offset_left = 14
	help.offset_top = -28
	help.offset_bottom = -10
	help.offset_right = 900
	add_child(help)

	_prompt = PanelContainer.new()
	_prompt.add_theme_stylebox_override("panel", Palette.glow_box(Color("#0B0A14", 0.92), Palette.ENERGY, Color(Palette.ENERGY, 0.25), 8, 10))
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -100
	_prompt.offset_bottom = -60
	_prompt.offset_left = -260
	_prompt.offset_right = 260
	_prompt.visible = false
	add_child(_prompt)
	_prompt_label = Label.new()
	_prompt_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt_label.add_theme_font_override("font", Palette.FONT_UI_BOLD)
	_prompt.add_child(_prompt_label)

	# Счётчик FPS (правый нижний угол)
	_fps_label = Label.new()
	_fps_label.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	_fps_label.add_theme_font_override("font", Palette.FONT_UI_BOLD)
	_fps_label.add_theme_font_size_override("font_size", 14)
	_fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_fps_label.add_theme_constant_override("outline_size", 6)
	_fps_label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_fps_label.offset_left = -130
	_fps_label.offset_top = -30
	_fps_label.offset_right = -14
	_fps_label.offset_bottom = -8
	_fps_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fps_label.visible = Settings.get_value("show_fps")
	add_child(_fps_label)

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _update_hud() -> void:
	if _hp_bar == null or run.is_empty() or node.is_empty():
		return
	var p := GameManager.player_data
	_title.text = "%s · %s" % [WorldData.location_info(location_id).get("name", ""), node.get("name", "")]
	_hp_bar.max_value = p.max_hp
	_hp_bar.value = p.hp
	_hp_label.text = " %d/%d" % [p.hp, p.max_hp]
	_loot_label.text = Loc.t("Добыча: %d золота · побед: %d · исследовано: %d%%") % [run.gold, run.fights,
		roundi(WorldData.node_progress(location_id, node_id) * 100.0)]
	var lines: PackedStringArray = []
	for q in GameManager.active_quests():
		lines.append("[color=#C792EA]◆ %s[/color]\n[color=#8C8CB0]%s[/color]" % [Loc.t(q.title), Loc.t(q.desc)])
	var signs := WorldData.signs_found(location_id)
	lines.append("[color=#F5C542]◆ %s[/color]" % (Loc.t("Указатели: %d из %d") % [signs.x, signs.y]))
	if _gates_closed():
		lines.append("[color=#F5C542]◆ %s[/color]" % Loc.t("Путь дальше перекрыт решёткой"))
	if GameManager.is_overloaded():
		lines.append("[color=#FF6B6B]◆ %s[/color]\n[color=#8C8CB0]%s[/color]" % [Loc.t("Перегруз: %s / %s кг") % [
			ItemDatabase.format_weight(GameManager.carried_weight()), ItemDatabase.format_weight(GameManager.carry_capacity())],
			Loc.t("Шаг медленный, бег недоступен. Открой инвентарь (%s) и выброси лишнее.") % Settings.action_key_name("inventory")])
	if _enemies.any(func(e): return is_instance_valid(e) and e.index < 0 and e.region == node_id):
		lines.append("[color=#FF6B6B]◆ %s[/color]" % Loc.t("Победи стража этого места"))
	_quests.text = "\n".join(lines)


# ---------------------------------------------------------------- Загрузка: поверхность и пещеры

func _clear_world() -> void:
	_fade.modulate.a = 1.0
	if _world:
		_world.queue_free()
		_world = null
	_interactables.clear()
	_exits.clear()
	_signs.clear()
	_gates.clear()
	_gears.clear()
	_enemies.clear()


## Поверхность локации (все наземные подлокации — районы одной карты). spawn — клетка появления.
func _load_surface(spawn: Vector2i, face_from: Vector2 = Vector2.INF) -> void:
	_clear_world()
	_surface = true
	data = OutdoorGenerator.generate_surface(location_id)
	node_id = OutdoorGenerator.region_at(data, Vector2(spawn) + Vector2(0.5, 0.5))
	node = WorldData.node(location_id, node_id)
	_world = Node3D.new()
	_viewport.add_child(_world)
	var built := LevelBuilder.build(_world, data, WorldData.location(location_id).get("sky", "day"))
	astar = built.astar
	_build_entities(spawn, -1000.0)
	if face_from != Vector2.INF:
		var d := _player.position - Vector3(face_from.x, _player.position.y, face_from.y)
		_player.face_yaw.call_deferred(atan2(d.x, d.z))
	_init_minimap()
	_enter_region(node_id, false)
	_finish_load(node.get("name", ""))


## Пещера / гробница / подземелье — отдельный уровень. entry — откуда пришли (район поверхности или пещера).
func _load_node(id: String, entry_from: String) -> void:
	_clear_world()
	_surface = false
	node_id = id
	node = WorldData.node(location_id, id)
	var neighbors: Array = []
	for link in node.get("links", []):
		var n := WorldData.node(location_id, link)
		neighbors.append({"id": link, "name": n.get("name", link), "kind": n.get("kind", ""), "pos": n.get("pos", [0.5, 0.5])})
	var seed_value: int = WorldData.node_seed(location_id, id) if int(run.seed_override) < 0 else int(run.seed_override)
	var opts: Dictionary = node.get("features", {}).duplicate()
	opts.neighbors = neighbors
	opts.entry = entry_from
	if not opts.has("npcs"):
		opts.npcs = []
	opts.boss = opts.get("boss", "")
	data = DungeonGenerator.generate(int(node.get("floor", 1)), seed_value, run.used, opts)
	data.kind = node.kind
	if data.get("riddle_id", "") != "":
		run.used.riddles.append(data.riddle_id)
	if not data.get("safe", {}).is_empty():
		run.used.safes.append(data.safe.id)
	_world = Node3D.new()
	_viewport.add_child(_world)
	var built := LevelBuilder.build(_world, data, "cave")
	astar = built.astar
	_build_entities(data.start, float(built.fall_y))
	if node.kind == "dungeon":
		_dungeon_decor()
	if entry_from != "":
		WorldData.mark_exit(location_id, id, entry_from)
		# Пришли «с той стороны» — через главный выход за решёткой: она открыта изнутри
		for e in data.exits:
			if e.to == entry_from and e.cell == data.get("exit", Vector2i(-99, -99)):
				_open_gates(true)
	_init_minimap()
	var ents := _entities()
	WorldData.visit_node(location_id, id, ents.chests.size(), ents.enemies.size() + ents.bosses.size())
	if not id in run.nodes:
		run.nodes.append(id)
	_finish_load(node.get("name", ""))


func _finish_load(title: String) -> void:
	_update_hud()
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 0.0, 0.7)
	EventBus.notify(title, "info")
	_transitioning = false


## Вход в район поверхности (по положению героя): посещение, итоги района для процента исследования.
func _enter_region(rid: String, announce: bool) -> void:
	node_id = rid
	node = WorldData.node(location_id, rid)
	var ents := _entities()
	var chests: int = ents.chests.filter(func(c): return c.region == rid).size()
	var enemies: int = ents.enemies.filter(func(e): return e.region == rid).size() + ents.bosses.filter(func(b): return b.region == rid).size()
	var first: bool = not WorldData.node_state(location_id, rid).visited
	WorldData.visit_node(location_id, rid, chests, enemies)
	if not rid in run.nodes:
		run.nodes.append(rid)
	if announce and first:
		EventBus.notify(node.get("name", ""), "info")
	_update_hud()


## Сущности уровня в одном формате для поверхности и подземелий (у каждой — район/подлокация и номер).
func _entities() -> Dictionary:
	if _surface:
		return {"chests": data.chests, "enemies": data.enemies, "bosses": data.bosses, "safes": data.safes,
			"npcs": data.npcs, "exits": data.caves}
	var chests: Array = []
	for i in data.chests.size():
		chests.append({"cell": data.chests[i], "region": node_id, "index": i})
	var enemies: Array = []
	for i in data.enemies.size():
		var e: Dictionary = data.enemies[i].duplicate()
		e.region = node_id
		e.index = i
		if e.has("room"):
			e.area = data.rooms[e.room].rect
		enemies.append(e)
	var bosses: Array = []
	if not data.boss.is_empty():
		var b: Dictionary = data.boss.duplicate()
		b.region = node_id
		if data.has("exit_room"):
			b.area = data.rooms[data.exit_room].rect
		bosses.append(b)
	var safes: Array = []
	if not data.safe.is_empty():
		var s: Dictionary = data.safe.duplicate()
		s.region = node_id
		safes.append(s)
	var npcs: Array = []
	for n in data.npcs:
		var c: Dictionary = n.duplicate()
		c.region = node_id
		npcs.append(c)
	return {"chests": chests, "enemies": enemies, "bosses": bosses, "safes": safes, "npcs": npcs, "exits": data.exits}


## Высота земли в точке уровня (поверхность — рельеф, подземелья — ровный пол).
func ground_y(x: float, z: float) -> float:
	return OutdoorGenerator.height_at(data.terrain, x, z) if _surface else 0.0


func _cell_pos(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, ground_y(cell.x + 0.5, cell.y + 0.5), cell.y + 0.5)


func _build_entities(spawn: Vector2i, fall_y: float) -> void:
	var ents := _entities()
	# Игрок
	_player = SortiePlayer.new()
	_player.position = _cell_pos(spawn) + Vector3(0, 0.3, 0)
	_player.fell.connect(_on_fell)
	_world.add_child(_player)
	_player.fall_y = fall_y
	_player_blob = null
	if not WorldStyle.quality().shadows:
		_player_blob = WorldStyle.blob_shadow(0.6)
		_world.add_child(_player_blob)
	if not _surface:
		_player.set_lantern(1.8)
	var center := Vector3(data.w * 0.5, 0, data.h * 0.5)
	if _surface:
		var r: Dictionary = _region(OutdoorGenerator.region_at(data, Vector2(spawn)))
		center = Vector3(r.center.x, 0, r.center.y) if not r.is_empty() else center
	var d := center - _player.position
	_player.face_yaw.call_deferred(atan2(d.x, d.z))

	# Решётки (подземелье с загадкой или стражем)
	var gate_scene := LevelBuilder.scene(LevelBuilder.D + "gate.glb")
	for cell in data.get("gates", []):
		var g: Node3D = gate_scene.instantiate()
		g.position = _cell_pos(cell)
		g.scale = Vector3(1, LevelBuilder.WALL_HEIGHT, 1)
		if data.has("exit_room") and data.rooms.size() > data.exit_room:
			var er: Rect2i = data.rooms[data.exit_room].rect
			if cell.x < er.position.x or cell.x >= er.end.x:
				g.rotation.y = PI / 2
		CharacterRig.tint(g, Color(0.85, 0.65, 0.4))
		_world.add_child(g)
		var body := StaticBody3D.new()
		body.collision_layer = LevelBuilder.WALL_LAYER
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1, 3, 1)
		cs.shape = box
		cs.position.y = 1.5
		body.add_child(cs)
		g.add_child(body)
		astar.set_point_solid(cell, true)
		_gates.append({"node": g, "body": body, "cell": cell})
		if data.gate_mode == "riddle":
			_interactables.append({"kind": "gate", "node": g, "pos": g.position, "riddle_id": data.riddle_id, "prompt": Loc.t("E — изучить механизм двери")})

	# Переходы: на поверхности — входы в пещеры, в подземелье — лестницы
	for e in ents.exits:
		_make_exit(e)
	# Указатели районов (точки быстрого перемещения)
	for sp in data.get("signposts", []):
		_make_signpost(sp)

	# Жители
	for n in ents.npcs:
		_spawn_npc(n.id, n.cell)
	if data.get("gate_mode", "") == "warden":
		_spawn_npc("warden", data.warden_cell)

	# Сейфы
	for s in ents.safes:
		var safe := _make_safe(s.cell)
		_interactables.append({"kind": "safe", "node": safe, "pos": safe.position, "data": s, "prompt": Loc.t("E — осмотреть сейф")})

	# Сундуки (открытые раньше не появляются снова)
	for c in ents.chests:
		if int(c.index) in WorldData.node_state(location_id, c.region).chests:
			continue
		var chest := LevelBuilder.place(_world, LevelBuilder.P + "Chest_Wood.gltf", _cell_pos(c.cell), randf() * TAU, 0.9)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.1, 0.7, 0.7)
		cs.shape = box
		cs.position.y = 0.35
		body.add_child(cs)
		chest.add_child(body)
		var glow := OmniLight3D.new()
		glow.light_color = Color("#FFD27A")
		glow.light_energy = 0.7
		glow.omni_range = 2.2
		glow.position.y = 0.8
		chest.add_child(glow)
		_interactables.append({"kind": "chest", "node": chest, "pos": chest.position, "index": c.index, "region": c.region, "prompt": Loc.t("E — открыть сундук")})

	_build_vertical()
	if _surface:
		_build_columns()
		_build_bridges()

	# Враги и стражи (побеждённые раньше не возвращаются)
	for e in ents.enemies:
		if int(e.index) in WorldData.node_state(location_id, e.region).kills:
			continue
		var area: Rect2i = e.get("area", Rect2i(e.cell - Vector2i(3, 3), Vector2i(6, 6)))
		_spawn_enemy(e.id, e.cell, area, int(e.index), e.region)
	for b in ents.bosses:
		if WorldData.node_state(location_id, b.region).get("boss", false):
			continue
		var area: Rect2i = b.get("area", Rect2i(b.cell - Vector2i(3, 3), Vector2i(6, 6)))
		_spawn_enemy(b.id, b.cell, area, -1, b.region)


func _region(rid: String) -> Dictionary:
	for r in data.get("regions", []):
		if r.id == rid:
			return r
	return {}


## Вертикальные постройки (OutdoorGenerator → data.vertical): на них надо запрыгнуть, наверху — сундук
## с ценной добычей. Визуал и коллизия совпадают (простые формы), так что «невидимых» препятствий нет.


func _build_vertical() -> void:
	for i in data.get("vertical", []).size():
		var v: Dictionary = data.vertical[i]
		var c: Vector2 = v.center
		var region: String = v.get("region", node_id)
		var st := WorldData.node_state(location_id, region)
		var root := Node3D.new()
		root.position = Vector3(c.x, ground_y(c.x, c.y) - 0.05, c.y)
		root.rotation.y = v.yaw
		_world.add_child(root)
		var body := StaticBody3D.new()
		body.collision_layer = 1
		root.add_child(body)
		var top := _build_spiral_tower(root, body, v)
		# Клетки под постройкой — препятствие для врагов
		for y in range(int(c.y) - 2, int(c.y) + 3):
			for x in range(int(c.x) - 2, int(c.x) + 3):
				if Vector2(x + 0.5, y + 0.5).distance_to(c) <= 1.8 and astar.region.has_point(Vector2i(x, y)):
					astar.set_point_solid(Vector2i(x, y), true)
		var index: int = HIGH_CHEST_BASE + i
		if index in st.chests:
			continue
		var chest := LevelBuilder.place(root, LevelBuilder.P + "Chest_Wood.gltf", Vector3(0, top, 0), 0.0, 0.9)
		var glow := OmniLight3D.new()
		glow.light_color = Color("#FFD27A")
		glow.light_energy = 1.2
		glow.omni_range = 3.0
		glow.position.y = 0.9
		chest.add_child(glow)
		var gpos := chest.global_position
		_interactables.append({"kind": "chest", "node": chest, "pos": gpos, "index": index, "region": region, "high": true, "prompt": Loc.t("E — открыть сундук")})


func _stone_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(LevelBuilder.V + "T_UnevenBrick_BaseColor.png")
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.5, 0.5, 0.5)
	m.albedo_color = Color(0.92, 0.88, 0.82)
	return m


func _wood_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(LevelBuilder.N + "Bark_NormalTree.png")
	m.uv1_triplanar = true
	m.uv1_scale = Vector3(0.7, 0.7, 0.7)
	return m


func _solid_box(root: Node3D, body: StaticBody3D, size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)


func _solid_cylinder(root: Node3D, body: StaticBody3D, radius: float, height: float, pos: Vector3, mat: Material, taper: float = 1.15) -> void:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.radial_segments = 20
	cm.top_radius = radius
	cm.bottom_radius = radius * taper
	cm.height = height
	mi.mesh = cm
	mi.material_override = mat
	mi.position = pos
	root.add_child(mi)
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	cs.shape = shape
	cs.position = pos
	body.add_child(cs)


## Полуразрушенная башня с винтовой лестницей: ствол-цилиндр, ступени-плиты по спирали (пологие — по ним
## идёшь пешком), часть ступеней обвалилась — провал надо перепрыгнуть. Наверху площадка с зубцами.
## Возвращает высоту площадки.
const SPIRAL_R := 1.5          # радиус ствола
const SPIRAL_W := 1.6          # ширина ступени


func _build_spiral_tower(root: Node3D, body: StaticBody3D, v: Dictionary) -> float:
	var height: float = v.height
	var steps: int = v.steps
	var stone := _stone_mat()
	_solid_cylinder(root, body, SPIRAL_R, height + 1.2, Vector3(0, (height - 1.2) * 0.5, 0), stone, 1.05)
	# Ступени-плиты: каждая — наклонный отрезок спирали
	for k in steps:
		if k in v.missing:
			# Обломок у стены — видно, что ступень была
			var stub := MeshInstance3D.new()
			var sb := BoxMesh.new()
			sb.size = Vector3(0.35, 0.25, 0.9)
			stub.mesh = sb
			stub.material_override = stone
			var am := _spiral_angle(k + 0.5, steps)
			stub.position = Vector3(cos(am) * (SPIRAL_R + 0.18), _spiral_y(k + 0.5, steps, height) - 0.2, sin(am) * (SPIRAL_R + 0.18))
			stub.rotation.y = -am
			root.add_child(stub)
			continue
		_spiral_slab(root, body, k, steps, height, stone)
	# Площадка наверху и разрушенные зубцы
	_solid_cylinder(root, body, SPIRAL_R + 0.25, 0.3, Vector3(0, height - 0.15, 0), stone, 1.0)
	var last_a := _spiral_angle(steps, steps)
	for k in 7:
		var a := TAU * k / 7.0
		if absf(angle_difference(a, last_a)) < 0.9 or k == 3:
			continue   # проход со стороны лестницы и обрушенный зубец
		var hs := randf_range(0.35, 0.7)
		_solid_box(root, body, Vector3(0.4, hs, 0.4), Vector3(cos(a) * (SPIRAL_R + 0.05), height + hs * 0.5, sin(a) * (SPIRAL_R + 0.05)), stone)
	# Обломки у подножия
	for k in 4:
		var a := randf() * TAU
		LevelBuilder.place(root, LevelBuilder.V + "Prop_Brick%d.gltf" % (1 + k % 2), Vector3(cos(a) * 3.6, 0.0, sin(a) * 3.6), randf() * TAU)
	return height


func _spiral_angle(k: float, steps: int) -> float:
	return k * deg_to_rad(32.0)


func _spiral_y(k: float, steps: int, height: float) -> float:
	return height * k / steps


func _spiral_slab(root: Node3D, body: StaticBody3D, k: int, steps: int, height: float, mat: Material) -> void:
	var r := SPIRAL_R + SPIRAL_W * 0.5 - 0.05
	var a0 := _spiral_angle(k, steps)
	var a1 := _spiral_angle(k + 1, steps)
	var p0 := Vector3(cos(a0) * r, _spiral_y(k, steps, height), sin(a0) * r)
	var p1 := Vector3(cos(a1) * r, _spiral_y(k + 1, steps, height), sin(a1) * r)
	var mid := (p0 + p1) * 0.5
	var along := p1 - p0
	var length := along.length() + 0.12
	var basis := Basis.looking_at(along.normalized(), Vector3.UP)
	var slab := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SPIRAL_W, 0.3, length)
	slab.mesh = bm
	slab.material_override = mat
	slab.transform = Transform3D(basis, mid - basis.y * 0.15)
	root.add_child(slab)
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = bm.size
	cs.shape = shape
	cs.transform = slab.transform
	body.add_child(cs)


## Точки маршрута по башне (для автотеста): центры ступеней по порядку и площадка наверху.
func spiral_route(v: Dictionary) -> Array:
	var pts: Array = []
	var r := SPIRAL_R + SPIRAL_W * 0.5
	for k in v.steps:
		if k in v.missing:
			continue
		var a := _spiral_angle(k + 0.5, v.steps)
		pts.append(Vector3(cos(a) * r, _spiral_y(k + 0.5, v.steps, v.height), sin(a) * r))
	pts.append(Vector3(0, v.height, 0))
	return pts


## Уступы из каменных столбов (шестигранные, как базальтовые колонны) с сундуком на вершине.
func _build_columns() -> void:
	var terrain: Dictionary = data.terrain
	var stone := StandardMaterial3D.new()
	stone.albedo_texture = load(LevelBuilder.V + "T_RockTrim_BaseColor.png")
	stone.uv1_triplanar = true
	stone.uv1_scale = Vector3(0.45, 0.45, 0.45)
	stone.albedo_color = Color(0.78, 0.76, 0.74)
	for i in data.get("columns", []).size():
		var cl: Dictionary = data.columns[i]
		var base_y := OutdoorGenerator.height_at(terrain, cl.center.x, cl.center.y)
		var body := StaticBody3D.new()
		body.collision_layer = 1 | 4
		_world.add_child(body)
		for c in cl.columns:
			var p: Vector2 = c.pos
			var gy := minf(OutdoorGenerator.height_at(terrain, p.x, p.y), base_y)
			var top: float = base_y + float(c.h)
			var hgt: float = top - gy + 1.0           # уходит в землю на метр
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.radial_segments = 6
			cm.rings = 1
			cm.top_radius = c.r
			cm.bottom_radius = c.r * 1.06
			cm.height = hgt
			mi.mesh = cm
			mi.material_override = stone
			mi.position = Vector3(p.x, top - hgt * 0.5, p.y)
			mi.rotation.y = randf() * TAU
			_world.add_child(mi)
			var cs := CollisionShape3D.new()
			var shape := CylinderShape3D.new()
			shape.radius = c.r
			shape.height = hgt
			cs.shape = shape
			cs.position = mi.position
			body.add_child(cs)
			for y in range(int(p.y - c.r), int(p.y + c.r) + 1):
				for x in range(int(p.x - c.r), int(p.x + c.r) + 1):
					if astar.region.has_point(Vector2i(x, y)):
						astar.set_point_solid(Vector2i(x, y), true)
		var index: int = COLUMN_CHEST_BASE + i
		if index in WorldData.node_state(location_id, cl.region).chests:
			continue
		var s: Vector2 = cl.summit
		var chest := LevelBuilder.place(_world, LevelBuilder.P + "Chest_Wood.gltf", Vector3(s.x, base_y + float(cl.top), s.y), randf() * TAU, 0.85)
		var glow := OmniLight3D.new()
		glow.light_color = Color("#FFD27A")
		glow.light_energy = 1.2
		glow.omni_range = 3.0
		glow.position.y = 0.9
		chest.add_child(glow)
		_interactables.append({"kind": "chest", "node": chest, "pos": chest.position, "index": index, "region": cl.region, "high": true, "prompt": Loc.t("E — открыть сундук")})


## Разрушенный каменный мост к острову: пролёты на опорах, между ними провалы.
func _build_bridges() -> void:
	var stone := _stone_mat()
	var body := StaticBody3D.new()
	body.collision_layer = 1 | 4
	_world.add_child(body)
	for b in data.get("bridges", []):
		var size: Vector3 = b.size
		var top: Vector3 = b.pos
		var node := Node3D.new()
		node.position = top
		node.rotation = Vector3(b.tilt, b.yaw, 0)
		_world.add_child(node)
		var deck := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = size
		deck.mesh = dm
		deck.material_override = stone
		deck.position.y = -size.y * 0.5
		node.add_child(deck)
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		cs.transform = node.transform * Transform3D(Basis(), Vector3(0, -size.y * 0.5, 0))
		body.add_child(cs)
		# Остатки парапета и опора, уходящая в провал
		for side in [-1.0, 1.0]:
			if randf() < 0.6:
				var rail := MeshInstance3D.new()
				var rm := BoxMesh.new()
				rm.size = Vector3(0.25, randf_range(0.25, 0.5), size.z * randf_range(0.4, 0.9))
				rail.mesh = rm
				rail.material_override = stone
				rail.position = Vector3(side * (size.x * 0.5 - 0.12), rm.size.y * 0.5, 0)
				node.add_child(rail)
		var pillar := MeshInstance3D.new()
		var pm := BoxMesh.new()
		pm.size = Vector3(size.x * 0.7, 14.0, minf(size.z, 1.2))
		pillar.mesh = pm
		pillar.material_override = stone
		pillar.position.y = -size.y - 7.0
		node.add_child(pillar)


func _make_exit(e: Dictionary) -> void:
	var under: bool = data.get("underground", false)
	var trigger := _cell_pos(e.cell)
	var root := Node3D.new()
	_world.add_child(root)
	var sealed: bool = e.get("sealed", false) and not GameManager.has_flag(_unseal_flag(e))
	var ex := {"exit": e, "trigger": trigger, "armed": true, "root": root, "barrier": null, "dir": Vector3.ZERO, "sealed": sealed}
	var label_pos := Vector3.ZERO
	if under:
		root.position = trigger
		var stairs := LevelBuilder.place(root, LevelBuilder.D + "stairs.glb", Vector3.ZERO)
		CharacterRig.tint(stairs, Color(0.9, 0.8, 0.65))
		var lamp := OmniLight3D.new()
		lamp.light_color = Color("#FFD9A0")
		lamp.light_energy = 0.8
		lamp.omni_range = 3.0
		lamp.position.y = 1.6
		root.add_child(lamp)
		label_pos = Vector3(0, 2.2, 0)
	else:
		var out := Vector3(e.dir.x, 0, e.dir.y).normalized()
		ex.dir = out
		# Вход в склоне холма: тёмный проём в скалах (пещера) или каменная арка (склеп, подземелье)
		root.position = trigger + out * 0.45
		root.rotation.y = atan2(-out.x, -out.z)   # лицом к тропе
		_cave_mouth(root, e.kind)
		label_pos = Vector3(0, 2.9, 0)
		if sealed:
			# Проход замурован: стена с запертой дверью поперёк тропы — открывается загадкой
			var gate_pos := _cell_pos(e.cell) - out * 2.0
			var g := Node3D.new()
			g.position = gate_pos
			g.rotation.y = atan2(out.x, out.z)
			_world.add_child(g)
			LevelBuilder.place(g, LevelBuilder.V + "Wall_UnevenBrick_Door_Round.gltf", Vector3.ZERO)
			for side in [-2.0, 2.0]:
				LevelBuilder.place(g, LevelBuilder.V + "Wall_UnevenBrick_Straight.gltf", Vector3(side, -0.15, 0), 0.0, 1.0)
			var door := LevelBuilder.place(g, LevelBuilder.V + "Door_1_Round.gltf", Vector3(-0.53, 0, -0.1))
			g.set_meta("door", door)
			# Боковые стены — навсегда, дверной проём — пока проход запечатан
			for part in [[Vector3(-2.0, 1.6, 0), false], [Vector3(2.0, 1.6, 0), false], [Vector3(0, 1.6, 0), true]]:
				var body := StaticBody3D.new()
				body.collision_layer = LevelBuilder.WALL_LAYER
				var cs := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(2.0, 3.2, 0.6)
				cs.shape = box
				cs.position = part[0]
				body.add_child(cs)
				g.add_child(body)
				if part[1]:
					g.set_meta("door_body", body)
			ex.barrier = g
			_interactables.append({"kind": "sealed", "node": g, "pos": gate_pos - out * 0.6, "riddle_id": e.get("riddle_id", ""), "prompt": Loc.t("E — проход запечатан загадкой")})
	var l := _label3d(root, ("🔒 " if sealed else "→ ") + String(e.to_name), Color("#FFE8B0"), label_pos.y, 40)
	l.position = label_pos
	l.visibility_range_end = 16.0
	# Появились рядом с проходом — он сработает только после того, как герой отойдёт
	if _player and Vector2(_player.position.x - trigger.x, _player.position.z - trigger.z).length() < 3.5:
		ex.armed = false
	_exits.append(ex)


func _unseal_flag(e: Dictionary) -> String:
	return "%s:unsealed:%s" % [location_id, e.to]


## Указатель района — точка быстрого перемещения: найден, когда герой подошёл (SIGN_DIST).
func _make_signpost(sp: Dictionary) -> void:
	var root := Node3D.new()
	root.position = _cell_pos(sp.cell)
	_world.add_child(root)
	_signpost(root, randf() * TAU)
	var l := _label3d(root, String(sp.name), Color("#FFE8B0"), 2.15, 40)
	l.visibility_range_end = 18.0
	_signs.append({"sign": sp, "pos": root.position})


func _signpost(root: Node3D, yaw: float) -> void:
	var wood := StandardMaterial3D.new()
	wood.albedo_color = Color("#6B4A2E")
	var post := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.09
	cyl.height = 1.8
	post.mesh = cyl
	post.material_override = wood
	post.position.y = 0.9
	root.add_child(post)
	var board := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 0.3, 1.0)
	board.mesh = bm
	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color("#A27A4E")
	board.material_override = bmat
	board.rotation.y = yaw
	board.position = Vector3(0, 1.5, 0) + Vector3(sin(yaw), 0, cos(yaw)) * 0.35
	root.add_child(board)
	if not WorldStyle.quality().shadows:
		root.add_child(WorldStyle.blob_shadow(0.3))


## Тёмный проём в склоне: камни аркой (пещера) или каменная арка (склеп, подземелье).
func _cave_mouth(root: Node3D, kind: String) -> void:
	var hole := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(1.9, 2.3)
	hole.mesh = quad
	var hm := StandardMaterial3D.new()
	hm.albedo_color = Color("#040308")
	hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hole.material_override = hm
	hole.position = Vector3(0, 1.1, -0.35)
	root.add_child(hole)
	if kind == "cave":
		for k in 5:
			var a := PI * (0.05 + 0.225 * k)
			LevelBuilder.place(root, LevelBuilder.N + "Rock_Medium_%d.gltf" % (1 + k % 3), Vector3(cos(a) * 1.45, sin(a) * 1.9 - 0.2, -0.2), a * 1.7, 0.75 + 0.1 * (k % 2))
	else:
		var arch := LevelBuilder.place(root, LevelBuilder.V + "Wall_Arch.gltf", Vector3(0, -0.1, -0.15), 0.0, 1.0)
		CharacterRig.tint(arch, Color(0.75, 0.78, 0.85) if kind == "crypt" else Color(0.85, 0.75, 0.6))
	var glow := OmniLight3D.new()
	glow.light_color = Color("#B08CFF") if kind == "cave" else Color("#9FB8E8")
	glow.light_energy = 0.9
	glow.omni_range = 3.5
	glow.position = Vector3(0, 1.4, 0.8)
	root.add_child(glow)


func _spawn_npc(npc_id: String, cell: Vector2i) -> void:
	var info := DialogueRunner.get_npc(npc_id)
	if info.is_empty():
		return
	var root := Node3D.new()
	root.position = _cell_pos(cell)
	_world.add_child(root)
	var vis: Dictionary = NPC_LOOKS.get(npc_id, {"look": Appearance.random_look(hash(npc_id))})
	var height := 1.9
	if vis.has("monster"):
		var m := MonsterRig.create(vis.monster, float(vis.get("scale", 1.0)))
		root.add_child(m)
		height = m.height()
	else:
		var rig := HeroRig.new()
		root.add_child(rig)
		rig.apply_look(vis.look)
		rig.apply_equipment(vis.get("gear", {"outfit": HeroRig.DEFAULT_OUTFIT, "variants": {}, "weapon": "", "offhand": ""}))
		rig.play("Idle_Talking" if npc_id != "warden" else "Sword_Idle")
		var s: float = vis.get("scale", 1.0)
		rig.scale = Vector3.ONE * s
		height = rig.height() * s
	if not WorldStyle.quality().shadows:
		root.add_child(WorldStyle.blob_shadow(0.5))
	# Повернуть лицом к центру поляны/комнаты
	root.rotation.y = randf() * TAU
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.35 if npc_id != "warden" else 0.6
	cyl.height = height
	cs.shape = cyl
	cs.position.y = height * 0.5
	body.add_child(cs)
	root.add_child(body)
	var color := Color.from_string(info.get("color", "#FFFFFF"), Color.WHITE)
	_label3d(root, Loc.f(info, "name"), color.lightened(0.3), height + 0.35)
	var marker := _label3d(root, "!" if not GameManager.has_flag(npc_id + "_met") else "…", Palette.ENERGY, height + 0.75, 80)
	root.set_meta("marker", marker)
	_interactables.append({"kind": "npc", "node": root, "pos": root.position, "id": npc_id, "prompt": Loc.t("E — поговорить: %s") % Loc.f(info, "name")})
	if npc_id == "warden":
		astar.set_point_solid(cell, true)


func _spawn_enemy(enemy_id: String, cell: Vector2i, area: Rect2i, index: int, region: String = "") -> void:
	var info: Dictionary = {}
	for e in CardDatabase.all_enemies():
		if e.id == enemy_id:
			info = e
	if info.is_empty():
		return
	var enemy := SortieEnemy.new()
	enemy.index = index
	enemy.region = region if region != "" else node_id
	enemy.ground_height = ground_y
	enemy.setup(info, _cell_pos(cell), area, astar, _player)
	enemy.contact.connect(_on_enemy_contact)
	_world.add_child(enemy)
	_enemies.append(enemy)


func _make_safe(cell: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.position = _cell_pos(cell)
	_world.add_child(root)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.7, 0.7, 0.55)
	box.mesh = bm
	box.material_override = _brass(Color("#8C6B2E"))
	box.position.y = 0.35
	root.add_child(box)
	var dial := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.13
	cyl.bottom_radius = 0.13
	cyl.height = 0.05
	dial.mesh = cyl
	dial.material_override = _brass(Color("#E8C872"))
	dial.rotation_degrees.x = 90
	dial.position = Vector3(0, 0.4, 0.3)
	root.add_child(dial)
	root.set_meta("dial", dial)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.7, 0.7, 0.55)
	cs.shape = shape
	cs.position.y = 0.35
	body.add_child(cs)
	root.add_child(body)
	_label3d(root, Loc.t("Сейф"), Color("#E8C872"), 1.05)
	return root


func _brass(color := Color("#C9A24A")) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.35
	mat.roughness = 0.4
	mat.emission_enabled = true
	mat.emission = color.darkened(0.6)
	mat.emission_energy_multiplier = 0.4
	return mat


func _label3d(parent: Node3D, text: String, color: Color, height: float, font_size := 40) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	l.font_size = font_size
	l.outline_size = 10
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.005
	l.no_depth_test = true
	l.position.y = height
	parent.add_child(l)
	return l


## Подземелье Феррограда: шестерни, трубы, знамёна, бочки и колонны.
func _dungeon_decor() -> void:
	var decor: Dictionary = data.get("decor", {})
	for c in decor.get("columns", []):
		var n := LevelBuilder.place(_world, LevelBuilder.D + "column.glb", _cell_pos(c))
		n.scale = Vector3(1, LevelBuilder.WALL_HEIGHT, 1)
		CharacterRig.tint(n, Color(0.85, 0.72, 0.55))
	for c in decor.get("barrels", []):
		LevelBuilder.place(_world, LevelBuilder.P + "Barrel.gltf", _cell_pos(c), randf() * TAU)
	for c in decor.get("banners", []):
		var b := LevelBuilder.place(_world, LevelBuilder.D + "banner.glb", _cell_pos(c))
		b.position.z = c.y + 1.0 + 0.48
		b.position.y = 1.0
		b.scale = Vector3.ONE * 1.5
		CharacterRig.tint(b, Color(0.9, 0.6, 0.4))
	for g in decor.get("gears", []):
		_make_gear(g.cell, g.size)
	for p in decor.get("pipes", []):
		_make_pipe(p.from, p.to)


func _make_gear(cell: Vector2i, radius: float) -> void:
	var pivot := Node3D.new()
	pivot.position = Vector3(cell.x + 0.5, 1.5, cell.y + 1.02)
	_world.add_child(pivot)
	var body := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.08
	cyl.radial_segments = 14
	body.mesh = cyl
	body.material_override = _brass()
	body.rotation_degrees.x = 90
	pivot.add_child(body)
	for i in 10:
		var tooth := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.09, 0.08, 0.12)
		tooth.mesh = box
		tooth.material_override = body.material_override
		var a := TAU * i / 10.0
		tooth.position = Vector3(cos(a), sin(a), 0) * (radius + 0.04)
		tooth.rotation.z = a
		pivot.add_child(tooth)
	pivot.set_meta("speed", randf_range(0.3, 1.0) * (1 if randf() < 0.5 else -1))
	_gears.append(pivot)


func _make_pipe(from: Vector2i, to: Vector2i) -> void:
	var length := float(to.x - from.x + 1)
	if length < 2:
		return
	var pipe := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.07
	cyl.bottom_radius = 0.07
	cyl.height = length
	pipe.mesh = cyl
	pipe.material_override = _brass(Color("#B87333"))
	pipe.rotation_degrees.z = 90
	pipe.position = Vector3(from.x + length / 2.0, 1.9, from.y + 1.08)
	_world.add_child(pipe)


# ---------------------------------------------------------------- Цикл и ввод

func _process(delta: float) -> void:
	_fps_t -= delta
	if _fps_t <= 0.0 and _fps_label and _fps_label.visible:
		_fps_t = 0.25
		var fps := Engine.get_frames_per_second()
		_fps_label.text = "FPS %d" % fps
		_fps_label.add_theme_color_override("font_color", Palette.MINT if fps >= 50 else (Palette.ENERGY if fps >= 30 else Palette.HP))
	if _world == null or _player == null or not is_instance_valid(_player):
		return
	for g in _gears:
		if is_instance_valid(g):
			g.rotation.z += delta * g.get_meta("speed")
	if _stamina_bar:
		_stamina_bar.max_value = _player.max_stamina
		_stamina_bar.value = _player.stamina
		_stamina_bar.modulate = Color(1, 0.55, 0.55) if _player.exhausted else Color.WHITE
	if is_instance_valid(_player_blob):
		var pp := _player.global_position
		_player_blob.visible = _player.is_on_floor()
		_player_blob.global_position = Vector3(pp.x, pp.y + 0.06, pp.z)
	if _covered or _ended or _paused or _transitioning:
		return
	_update_focus()
	_check_exits()
	if _surface:
		_check_signs()
		_check_chasm_fall()
		_region_t -= delta
		if _region_t <= 0.0:
			_region_t = 0.5
			var rid := OutdoorGenerator.region_at(data, Vector2(_player.global_position.x, _player.global_position.z))
			if rid != node_id:
				_enter_region(rid, true)
	if _compass:
		_compass.update_view(_player.cam_yaw + PI, _player.global_position, _compass_markers())
	_explored_save_t -= delta
	if _explored_save_t <= 0.0:
		_explored_save_t = 3.0
		_store_explored()
	_map_timer -= delta
	if _map_timer <= 0.0:
		_map_timer = 0.15
		_update_minimap()


func _update_focus() -> void:
	var best: Dictionary = {}
	var best_d := INTERACT_DIST
	for it in _interactables:
		if not is_instance_valid(it.node):
			continue
		var d: float = Vector2(_player.global_position.x, _player.global_position.z).distance_to(Vector2(it.pos.x, it.pos.z))
		if absf(_player.global_position.y - it.pos.y) > 1.6:
			continue   # сундук на башне не открыть снизу
		if d < best_d:
			best_d = d
			best = it
	_focus = best
	_prompt.visible = not best.is_empty() and _menu == null
	if not best.is_empty():
		_prompt_label.text = best.prompt


## Проходы: подошёл к указателю или входу — проход найден (открыт на карте локации навсегда);
## ушёл по тропе за край / шагнул в пещеру или на лестницу — переход в соседнюю подлокацию.
func _check_exits() -> void:
	var p := _player.global_position
	for ex in _exits:
		var e: Dictionary = ex.exit
		var sealed: bool = ex.sealed
		var trig: Vector3 = ex.trigger
		var flat := Vector2(p.x - trig.x, p.z - trig.z)
		if not sealed and flat.length() < SIGN_DIST:
			_discover(e)
		if not ex.armed:
			if flat.length() > 3.5:
				ex.armed = true
			continue
		if sealed or absf(p.y - trig.y) > 2.0:
			continue
		var crossed := false
		var dir: Vector3 = ex.dir
		if dir != Vector3.ZERO:
			var along := flat.dot(Vector2(dir.x, dir.z))
			var lateral := absf(flat.cross(Vector2(dir.x, dir.z)))
			crossed = along > -0.6 and along < 2.5 and lateral < 2.6
		else:
			crossed = flat.length() < 0.9
		if crossed:
			ex.armed = false
			_use_exit(ex)
			return


## Найден вход в пещеру / проход подземелья: открыт на карте локации навсегда.
func _discover(e: Dictionary) -> void:
	var was_open := WorldData.is_open(location_id, e.to)
	if WorldData.mark_exit(location_id, e.get("region", node_id), e.to):
		_update_hud()
		if not was_open:
			Audio.play_jingle("discovery")
			EventBus.notify(Loc.t("Найден проход: %s. Теперь туда можно отправиться прямо с карты локации.") % e.to_name, "success")


## Указатели районов: подошёл — указатель найден (быстрое перемещение с карты).
func _check_signs() -> void:
	var p := Vector2(_player.global_position.x, _player.global_position.z)
	for s in _signs:
		if p.distance_to(Vector2(s.pos.x, s.pos.z)) < SIGN_DIST and WorldData.mark_sign(location_id, s.sign.region):
			var n := WorldData.signs_found(location_id)
			Audio.play_jingle("discovery")
			EventBus.notify(Loc.t("Найден указатель «%s» (%d из %d) — сюда можно быстро переместиться с карты.") % [s.sign.name, n.x, n.y], "success")
			_update_hud()


## Падение в пропасть или реку на поверхности: ниже уровня берега внутри её контура.
func _check_chasm_fall() -> void:
	if _falling:
		return
	var p := _player.global_position
	for ch in data.chasms:
		# Кольцо провала (края сглажены по окружности — проверяем по расстоянию, а не по клетке)
		var dc := Vector2(p.x, p.z).distance_to(ch.center)
		if dc > float(ch.r_in) - 0.8 and dc < float(ch.r_out) + 0.8:
			if p.y < float(ch.level) - (0.9 if ch.water else 4.5):
				_falling = true
				_player.fell.emit()
				_player.input_enabled = false
			return
	# Страховка: оказался под рельефом (не в пропасти) — вернуть на поверхность
	var gy := ground_y(p.x, p.z)
	if p.y < gy - 2.5:
		_player.global_position = Vector3(p.x, gy + 0.5, p.z)
		_player.velocity = Vector3.ZERO


## Метки на полосе компаса: указатели, входы в пещеры, ближайшие враги.
func _compass_markers() -> Array:
	var list: Array = []
	var me := _player.global_position
	# Неизвестные места («?») — только поблизости, найденные указатели и входы — всегда
	for s in _signs:
		var found: bool = WorldData.is_sign_found(location_id, s.sign.region)
		if found or me.distance_to(s.pos) < 45.0:
			list.append({"pos": s.pos, "kind": "sign" if found else "unknown", "label": s.sign.name if found else "?"})
	for ex in _exits:
		if _surface:
			var known: bool = ex.exit.to in WorldData.node_state(location_id, ex.exit.region).exits
			if known or me.distance_to(ex.trigger) < 45.0:
				list.append({"pos": ex.trigger, "kind": "cave" if known else "unknown", "label": ex.exit.to_name if known else "?"})
		else:
			list.append({"pos": ex.trigger, "kind": "cave", "label": ex.exit.to_name})
	for e in _enemies:
		if is_instance_valid(e) and e.global_position.distance_to(_player.global_position) < 22.0:
			list.append({"pos": e.global_position, "kind": "enemy", "label": ""})
	return list


func _gui_input(event: InputEvent) -> void:
	if _player and not _covered and not _paused and _menu == null:
		_player.handle_camera_input(event)


func _unhandled_input(event: InputEvent) -> void:
	if _covered or _ended or run.is_empty() or _transitioning:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		if _paused:
			_toggle_pause()
		_toggle_menu()
	elif event.is_action_pressed("pause") and _menu == null:
		get_viewport().set_input_as_handled()
		_toggle_pause()
	elif event.is_action_pressed("map") and _menu == null and not _paused:
		get_viewport().set_input_as_handled()
		_open_location_map()
	elif event.is_action_pressed("inventory") and _menu == null and not _paused:
		get_viewport().set_input_as_handled()
		Audio.play("open")
		EventBus.go("inventory", {"overlay": true})
	elif event.is_action_pressed("interact") and not _focus.is_empty() and not _paused and _menu == null:
		get_viewport().set_input_as_handled()
		_interact(_focus)


func _interact(it: Dictionary) -> void:
	_player.face(it.pos)
	match it.kind:
		"npc":
			var marker = it.node.get_meta("marker")
			if is_instance_valid(marker):
				marker.text = "…"
			EventBus.go("dialogue", {"npc_id": it.id, "overlay": true})
		"gate":
			EventBus.go("riddle", {"riddle_id": it.riddle_id, "overlay": true})
		"safe":
			EventBus.go("safe", {"safe_id": it.data.id, "overlay": true})
		"chest":
			_player.act("PickUp_Table")
			_open_chest(it)
		"sealed":
			EventBus.go("riddle", {"riddle_id": it.riddle_id, "overlay": true})


func _use_exit(ex: Dictionary) -> void:
	var e: Dictionary = ex.exit
	if ex.sealed:
		return
	if _gates_closed() and e.cell in _gated_cells():
		EventBus.notify(Loc.t("Путь перекрыт решёткой"), "warning")
		return
	if _boss_alive() and not _surface and e.cell == data.get("exit", Vector2i(-99, -99)):
		EventBus.notify(Loc.t("Страж этого места не даст пройти — победи его"), "warning")
		return
	_discover(e)
	if _surface:
		_go_to_node(e.to, e.region)
		return
	var target := WorldData.node(location_id, e.to)
	if WorldData.is_underground(target):
		_go_to_node(e.to, node_id)
	else:
		# Выход из пещеры на поверхность — у её входа в склоне
		var surf := OutdoorGenerator.generate_surface(location_id)
		for c in surf.caves:
			if c.to == node_id and c.region == e.to:
				_go_to_surface(c.arrive, Vector2(c.cell))
				return
		_go_to_surface(_signpost_of(e.to).get("arrive", surf.start), Vector2.INF)


## Быстрое перемещение с карты локации (M) к найденному указателю района (или в посещённую пещеру).
func _fast_travel(id: String) -> void:
	if _transitioning or not WorldData.is_open(location_id, id):
		return
	if WorldData.is_underground(WorldData.node(location_id, id)):
		if id != node_id or _surface:
			_go_to_node(id, _entry_for(id))
		return
	var sp := _signpost_of(id)
	if not sp.is_empty():
		_go_to_surface(sp.arrive, Vector2.INF)


func _go_to_node(id: String, entry: String) -> void:
	_begin_transition()
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.5)
	tw.tween_callback(_load_node.bind(id, entry))


func _go_to_surface(spawn: Vector2i, face_from: Vector2) -> void:
	_begin_transition()
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.5)
	if _surface:
		# Уже на поверхности: переносим героя, не перестраивая мир
		tw.tween_callback(func():
			_player.global_position = _cell_pos(spawn) + Vector3(0, 0.3, 0)
			_player.velocity = Vector3.ZERO
			_enter_region(OutdoorGenerator.region_at(data, Vector2(spawn)), true)
			_player.input_enabled = true
			_finish_load(node.get("name", "")))
	else:
		tw.tween_callback(_load_surface.bind(spawn, face_from))


func _begin_transition() -> void:
	_store_explored()
	_transitioning = true
	_prompt.visible = false
	_player.input_enabled = false
	Audio.play("whoosh")
	SaveSystem.save_all()


func _gated_cells() -> Array:
	# Выход в комнате за решёткой — главный выход подземелья
	return [data.get("exit", Vector2i(-99, -99))] if data.get("underground", false) else []


# ---------------------------------------------------------------- Перекрытие экранами

func on_cover() -> void:
	_store_explored()
	_covered = true
	_prompt.visible = false
	if _player:
		_player.input_enabled = false
	if _world:
		_world.process_mode = Node.PROCESS_MODE_DISABLED


func on_resume() -> void:
	_covered = false
	if _world and not _paused:
		_world.process_mode = Node.PROCESS_MODE_INHERIT
	if _player and not _paused:
		_player.input_enabled = true
		_player.refresh_gear()
	_update_hud()
	if not _combat_result.is_empty():
		var r := _combat_result
		_combat_result = {}
		_after_combat(r)
		return
	var actions := _pending_actions
	_pending_actions = []
	for a in actions:
		_world_action(a)


# ---------------------------------------------------------------- Бой

func _on_enemy_contact(enemy) -> void:
	if _covered or _ended or _paused or _menu != null or _transitioning:
		enemy.resume()
		return
	_start_combat(enemy, enemy.enemy_data.id)


func _start_combat(enemy, enemy_id: String) -> void:
	_combat_enemy = enemy
	Audio.play("hit_heavy")
	if _player:
		_player.act("Sword_Attack")
	var region: String = enemy.region if enemy != null and is_instance_valid(enemy) else node_id
	EventBus.go("combat", {"enemy_id": enemy_id, "context": "expedition", "power": _enemy_power(region)})


## Сила врагов района / подлокации (глубже в локации — сильнее).
func _enemy_power(region: String) -> float:
	return XPCalculator.enemy_power(WorldData.node_depth(location_id, region), int(WorldData.location_info(location_id).get("level", 1)))


func _on_combat_finished(result: Dictionary) -> void:
	if result.get("context") == "expedition" and not run.is_empty():
		_combat_result = result


func _after_combat(result: Dictionary) -> void:
	if result.won:
		run.fights += 1
		run.gold += int(result.get("gold", 0))
		if is_instance_valid(_combat_enemy):
			var idx: int = _combat_enemy.index
			var region: String = _combat_enemy.region
			if idx >= 0:
				WorldData.mark_kill(location_id, region, idx)
			else:
				WorldData.node_state(location_id, region).boss = true
				var st := WorldData.node_state(location_id, region)
				if not -1 in st.kills:
					st.kills.append(-1)
				EventBus.notify(Loc.t("Страж повержен! Путь свободен."), "success")
				_on_boss_defeated(_combat_enemy.enemy_data)
			_combat_enemy.die()
			_enemies.erase(_combat_enemy)
		if _combat_open_gate:
			_combat_open_gate = false
			_open_gates()
		_combat_enemy = null
		SaveSystem.save_all()
		_update_hud()
	else:
		_combat_enemy = null
		_end_run("defeat")


func _on_boss_defeated(enemy: Dictionary) -> void:
	GameManager.player_data.lootboxes = GameManager.lootbox_count() + 1
	if enemy.get("is_boss", false):
		GameManager.gain_xp(50)
		GameManager.set_flag(location_id + "_cleared")
		if location_id == "ferrograd_ruins":
			GameManager.set_flag("ruins_cleared")
		EventBus.notify(Loc.t("Сердце этого края спасено: +50 XP и сундук с картой"), "success")


# ---------------------------------------------------------------- Диалоги, загадки, сейфы

func _on_dialogue_finished(npc_id: String, actions: Array) -> void:
	if not run.is_empty():
		for a in actions:
			_pending_actions.append(a)
		if actions.any(func(a): return a.get("world") == "npc_leave"):
			_pending_actions.append({"world": "_leave", "npc": npc_id})


func _world_action(a: Dictionary) -> void:
	match a.get("world", ""):
		"open_gate":
			_open_gates()
		"reveal_map":
			for y in data.h:
				for x in data.w:
					_reveal_cell(x, y)
			_update_minimap()
			EventBus.notify(Loc.t("Карта открыта"), "success")
		"combat":
			_combat_open_gate = a.get("open_gate_on_win", false)
			_start_combat(null, a.get("enemy", "syntax_error"))
		"riddle":
			EventBus.go("riddle", {"riddle_id": data.riddle_id, "overlay": true})
		"_leave":
			for it in _interactables.duplicate():
				if it.kind == "npc" and it.get("id") == a.npc:
					_interactables.erase(it)
					var n: Node3D = it.node
					var tw := n.create_tween()
					tw.tween_property(n, "scale", Vector3(1, 0.01, 1), 0.6)
					tw.tween_callback(n.queue_free)
					if a.npc == "warden" and data.get("warden_cell", Vector2i(-1, -1)) != Vector2i(-1, -1):
						astar.set_point_solid(data.warden_cell, false)


func _on_riddle_finished(riddle_id: String, solved: bool) -> void:
	if not solved:
		return
	var for_cave := _exits.any(func(ex): return ex.sealed and ex.exit.get("riddle_id", "") == riddle_id)
	if riddle_id != data.get("riddle_id", "") and not for_cave:
		return
	run.riddles += 1
	_pending_actions.append({"world": "open_gate"})
	if data.get("gate_mode") == "warden":
		_pending_actions.append({"world": "_leave", "npc": "warden"})
	# Запечатанный загадкой проход открывается
	for ex in _exits:
		if ex.sealed and ex.exit.get("riddle_id", data.get("riddle_id", "")) == riddle_id:
			ex.sealed = false
			GameManager.set_flag(_unseal_flag(ex.exit))
			if is_instance_valid(ex.barrier):
				var g: Node3D = ex.barrier
				var door_body: Node = g.get_meta("door_body")
				if is_instance_valid(door_body):
					door_body.queue_free()
				var door: Node3D = g.get_meta("door")
				if is_instance_valid(door):
					door.create_tween().tween_property(door, "rotation:y", deg_to_rad(-100), 1.2).set_trans(Tween.TRANS_CUBIC)
				Audio.play("gate")
			for it in _interactables.duplicate():
				if it.kind == "sealed":
					_interactables.erase(it)
			EventBus.notify(Loc.t("Печать спала — проход открыт!"), "success")


func _on_safe_finished(safe_id: String, opened: bool) -> void:
	if not opened or not _interactables.any(func(it): return it.kind == "safe" and it.data.id == safe_id):
		return
	run.safes += 1
	GameManager.add_stat("safes")
	GameManager.gain_xp(15)
	for it in _interactables.duplicate():
		if it.kind == "safe" and it.data.id == safe_id:
			_interactables.erase(it)
			var dial = it.node.get_meta("dial")
			if is_instance_valid(dial):
				dial.create_tween().tween_property(dial, "rotation:y", TAU * 2, 1.0)
	var has_greta: bool = _entities().npcs.any(func(n): return n.id == "greta")
	if has_greta and GameManager.item_count("valve") == 0 and not GameManager.has_flag("valve_returned"):
		GameManager.add_item("valve")
		EventBus.notify(Loc.t("В сейфе — латунный клапан Греты!"), "success")
	else:
		# Сейф — награда за решённую задачу: всегда предмет снаряжения (из лучших по уровню) и золото
		var gold := randi_range(25, 45)
		GameManager.add_gold(gold)
		run.gold += gold
		var msg := Loc.t("Сейф открыт: +%d золота") % gold
		var item := _roll_item(1.0, 5, true)
		if not item.is_empty():
			msg += ", " + Loc.t("предмет «%s»") % item.name
		if randf() < 0.5:
			var card := CardDatabase.roll_card(CardDatabase.all_cards(), 2.0)
			GameManager.add_card_to_collection(card.id)
			msg += ", " + Loc.t("карта «%s»") % card.name
		EventBus.notify(msg, "success")
	SaveSystem.save_all()


func _open_gates(silent := false) -> void:
	if _gates.is_empty():
		return
	if not silent:
		Audio.play("gate")
	for g in _gates:
		var n: Node3D = g.node
		if is_instance_valid(g.body):
			g.body.queue_free()
		astar.set_point_solid(g.cell, false)
		if silent:
			n.position.y = -2.0
		else:
			var tw := n.create_tween()
			tw.tween_property(n, "position:y", -2.0, 1.2).set_trans(Tween.TRANS_CUBIC)
	_gates.clear()
	for it in _interactables.duplicate():
		if it.kind == "gate":
			_interactables.erase(it)
	if not silent:
		EventBus.notify(Loc.t("Решётка поднята!"), "success")
	_update_hud()


func _gates_closed() -> bool:
	return not _gates.is_empty()


func _boss_alive() -> bool:
	for e in _enemies:
		if is_instance_valid(e) and e.index < 0:
			return true
	return false


## Предмет снаряжения из сундука/сейфа: подходящий по уровню локации (+extra_levels).
## prefer_high — выбор из верхней половины доступных по уровню (награда сейфа, лут на башнях).
func _roll_item(chance: float, extra_levels: int = 3, prefer_high: bool = false) -> Dictionary:
	if randf() > chance:
		return {}
	var lvl: int = int(WorldData.location_info(location_id).get("level", 1)) + extra_levels
	var pool := ItemDatabase.all_items().filter(func(it): return it.get("price", 0) > 0 and int(it.get("level", 1)) <= lvl)
	if pool.is_empty():
		return {}
	if prefer_high and pool.size() > 3:
		pool.sort_custom(func(a, b): return int(a.level) > int(b.level))
		pool = pool.slice(0, maxi(3, pool.size() / 2))
	var it: Dictionary = pool.pick_random()
	GameManager.player_data.inventory.append(it.id)
	GameManager.equipment_changed.emit()
	run.items.append(it.id)
	return it


func _open_chest(it: Dictionary) -> void:
	_interactables.erase(it)
	WorldData.mark_chest(location_id, it.get("region", node_id), it.index)
	var lid: Node3D = it.node
	var tw := lid.create_tween()
	tw.tween_property(lid, "scale", Vector3(1.0, 1.15, 1.0) * lid.scale.x, 0.12)
	tw.tween_property(lid, "scale", Vector3.ONE * lid.scale.x, 0.2)
	Audio.play("chest_creak")
	var level: int = int(WorldData.location_info(location_id).get("level", 1))
	var high: bool = it.get("high", false)
	var gold: int = randi_range(8, 18) + level * 4 + (randi_range(20, 35) if high else 0)
	GameManager.add_gold(gold)
	run.gold += gold
	var msg := Loc.t("Сундук: +%d золота") % gold
	# Сундук на башне/вышке — награда за паркур: чаще и лучше снаряжение
	var item := _roll_item(0.75, 5, true) if high else _roll_item(0.25)
	if not item.is_empty():
		msg += ", " + Loc.t("предмет «%s»") % item.name
	if randf() < 0.35:
		var healed := GameManager.heal_player(8)
		msg += ", " + Loc.t("зелье (+%d HP)") % healed
	if randf() < 0.2:
		var card := CardDatabase.roll_card(CardDatabase.all_cards(), 1.5)
		GameManager.add_card_to_collection(card.id)
		msg += ", " + Loc.t("карта «%s»") % card.name
	Audio.play("coins")
	EventBus.notify(msg, "success")
	var sparkle := CPUParticles3D.new()
	sparkle.position = lid.global_position + Vector3(0, 0.8, 0)
	sparkle.one_shot = true
	sparkle.amount = 30
	sparkle.lifetime = 1.0
	sparkle.explosiveness = 0.9
	sparkle.direction = Vector3.UP
	sparkle.spread = 50
	sparkle.initial_velocity_min = 2.0
	sparkle.initial_velocity_max = 4.0
	sparkle.scale_amount_min = 0.05
	sparkle.scale_amount_max = 0.1
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Palette.GOLD
	sm.material = mat
	sparkle.mesh = sm
	_world.add_child(sparkle)
	sparkle.emitting = true
	SaveSystem.save_all()
	_update_hud()


# ---------------------------------------------------------------- Мини-карта

func _init_minimap() -> void:
	_explored = PackedByteArray()
	_explored.resize(data.w * data.h)
	_map_image = Image.create(data.w, data.h, false, Image.FORMAT_RGBA8)
	_terrain_image = Image.create(data.w, data.h, false, Image.FORMAT_RGBA8)
	_map_tex = ImageTexture.create_from_image(_map_image)
	_restore_explored()
	_update_minimap()


## Исследованная часть карты хранится в состоянии подлокации (сжатая маска клеток).
func _store_explored() -> void:
	if _explored.is_empty() or node_id == "" or int(run.get("seed_override", -1)) >= 0:
		return
	var st := _explored_state()
	st["explored"] = Marshalls.raw_to_base64(_explored.compress(FileAccess.COMPRESSION_DEFLATE))
	st["explored_size"] = _explored.size()
	var walk := 0
	var seen := 0
	var grid: PackedByteArray = data.grid
	for i in grid.size():
		if grid[i] == OutdoorGenerator.FLOOR or grid[i] == OutdoorGenerator.PATH:
			walk += 1
			seen += _explored[i]
	st["explored_pct"] = float(seen) / maxf(walk, 1)


## Где хранится маска исследованного: у поверхности — в состоянии локации, у пещеры — в её состоянии.
func _explored_state() -> Dictionary:
	if _surface:
		var ls := WorldData.loc_state(location_id)
		if not ls.has("surface"):
			ls["surface"] = {}
		return ls.surface
	return WorldData.node_state(location_id, node_id)


func _restore_explored() -> void:
	var st := _explored_state()
	if int(st.get("explored_size", 0)) != _explored.size() or int(run.get("seed_override", -1)) >= 0:
		return
	var raw := Marshalls.base64_to_raw(String(st.get("explored", ""))).decompress(_explored.size(), FileAccess.COMPRESSION_DEFLATE)
	if raw.size() != _explored.size():
		return
	for i in raw.size():
		if raw[i] == 1:
			_reveal_cell(i % data.w, i / data.w)


func _update_minimap() -> void:
	if _player == null or _map_image == null:
		return
	var w: int = data.w
	var h: int = data.h
	var pc := Vector2i(int(_player.global_position.x), int(_player.global_position.z))
	# Рельеф копится в _terrain_image: рисуются только клетки, открытые на этом шаге
	for y in range(pc.y - FOG_RADIUS, pc.y + FOG_RADIUS + 1):
		for x in range(pc.x - FOG_RADIUS, pc.x + FOG_RADIUS + 1):
			if x < 0 or y < 0 or x >= w or y >= h or Vector2i(x, y).distance_to(pc) > FOG_RADIUS:
				continue
			_reveal_cell(x, y)
	_map_image.copy_from(_terrain_image)
	for g in _gates:
		_dot(g.cell, Color("#FF9F43"))
	for it in _interactables:
		var c := Vector2i(int(it.pos.x), int(it.pos.z))
		match it.kind:
			"npc":
				_dot(c, Color("#C792EA"))
			"safe", "chest":
				_dot(c, Palette.GOLD)
			"sealed":
				_dot(c, Color("#7FDBFF"), true)
	for ex in _exits:
		_dot(Vector2i(int(ex.trigger.x), int(ex.trigger.z)), Color("#7FDBFF"), true)
	for sg in _signs:
		_dot(Vector2i(int(sg.pos.x), int(sg.pos.z)), Palette.GOLD, true)
	for e in _enemies:
		if is_instance_valid(e):
			_dot(Vector2i(int(e.global_position.x), int(e.global_position.z)), Palette.HP)
	_dot(pc, Palette.MINT, true, true)
	_map_tex.update(_map_image)


func _reveal_cell(x: int, y: int) -> void:
	var i: int = y * data.w + x
	if _explored[i] == 1:
		return
	_explored[i] = 1
	var outdoor: bool = not data.get("underground", false)
	match int(data.grid[i]):
		0:
			if _near_walkable(x, y):
				_terrain_image.set_pixel(x, y, Color(0.18, 0.32, 0.16, 0.9) if outdoor else Color(0.35, 0.28, 0.2, 0.9))
		1:
			_terrain_image.set_pixel(x, y, Color(0.55, 0.78, 0.42, 0.85) if outdoor else Color(0.75, 0.68, 0.58, 0.75))
		2:
			_terrain_image.set_pixel(x, y, Color(0.82, 0.7, 0.5, 0.85) if outdoor else Color(0.55, 0.5, 0.45, 0.7))
		3:
			_terrain_image.set_pixel(x, y, Color(0.25, 0.5, 0.75, 0.8) if data.get("water", false) else Color(0.05, 0.04, 0.08, 0.9))


func _near_walkable(x: int, y: int) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and ny >= 0 and nx < data.w and ny < data.h and data.grid[ny * data.w + nx] in [1, 2]:
				return true
	return false


func _dot(c: Vector2i, color: Color, big := false, force := false) -> void:
	var w: int = data.w
	var h: int = data.h
	for dy in ([-1, 0, 1] if big else [0]):
		for dx in ([-1, 0, 1] if big else [0]):
			var p := c + Vector2i(dx, dy)
			if p.x >= 0 and p.y >= 0 and p.x < w and p.y < h and (force or _explored[p.y * w + p.x] == 1):
				_map_image.set_pixel(p.x, p.y, color)


# ---------------------------------------------------------------- Пауза, меню и итоги

## M — карта всей локации поверх вылазки: где ты, найденные проходы, быстрое перемещение, карта мира.
func _open_location_map() -> void:
	_store_explored()
	Audio.play("open")
	EventBus.go("location", {"location_id": location_id, "in_sortie": true, "current": node_id,
		"minimap": _map_tex if not _surface else null, "on_travel": _fast_travel,
		"player": Vector2(_player.global_position.x, _player.global_position.z) if _surface else Vector2.INF,
		"player_yaw": _player.cam_yaw + PI})


## P — просто пауза: мир замирает, по центру белая надпись «ПАУЗА».
func _toggle_pause() -> void:
	_paused = not _paused
	if _paused:
		_player.input_enabled = false
		_world.process_mode = Node.PROCESS_MODE_DISABLED
		_pause_label = Control.new()
		_pause_label.set_anchors_preset(Control.PRESET_FULL_RECT)
		_pause_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.25)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_pause_label.add_child(dim)
		var l := Label.new()
		l.text = Loc.t("ПАУЗА")
		l.set_anchors_preset(Control.PRESET_FULL_RECT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		l.add_theme_font_override("font", Palette.FONT_DISPLAY)
		l.add_theme_font_size_override("font_size", 72)
		l.add_theme_color_override("font_color", Color.WHITE)
		l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		l.add_theme_constant_override("outline_size", 12)
		_pause_label.add_child(l)
		add_child(_pause_label)
	else:
		if is_instance_valid(_pause_label):
			_pause_label.queue_free()
		_pause_label = null
		if _menu == null:
			_player.input_enabled = true
			_world.process_mode = Node.PROCESS_MODE_INHERIT


## Esc — меню вылазки: продолжить, настройки, вернуться в лагерь, выйти из игры.
func _toggle_menu() -> void:
	if _menu != null:
		_menu.queue_free()
		_menu = null
		_player.input_enabled = true
		_world.process_mode = Node.PROCESS_MODE_INHERIT
		return
	_player.input_enabled = false
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	_menu = _overlay_panel(Loc.t("Меню вылазки"), Loc.t("%s\nДобыча: %d золота. Найденное золото, предметы и карты остаются с тобой.") % [node.get("name", ""), run.gold],
		[[Loc.t("Продолжить"), _toggle_menu, "AccentButton"],
		[Loc.t("Настройки"), func(): EventBus.go("settings"), ""],
		[Loc.t("Вернуться в лагерь"), func(): _end_run("leave"), ""],
		[Loc.t("Выйти из игры"), EventBus.quit_game, "GhostButton"]])


func _on_fell() -> void:
	if _ended:
		return
	Audio.play("drop")
	await get_tree().create_timer(0.8).timeout
	_end_run("fall")


## reason: "leave" — вернулся сам, "defeat" — проиграл бой, "fall" — сорвался в пропасть.
func _end_run(reason: String) -> void:
	if _ended:
		return
	_store_explored()
	_ended = true
	if is_instance_valid(_menu):
		_menu.queue_free()
		_menu = null
	if _paused:
		_toggle_pause()
	_prompt.visible = false
	if _player:
		_player.input_enabled = false
	var lines: PackedStringArray = []
	var title := ""
	match reason:
		"defeat":
			title = Loc.t("Вылазка прервана")
			lines.append(Loc.t("Ты теряешь сознание, и тебя выносят к лагерю. Золото и добыча остаются с тобой."))
		"fall":
			title = Loc.t("Падение")
			var lost: int = GameManager.player_data.energy
			GameManager.player_data.energy = 0
			GameManager.energy_changed.emit(0, GameManager.player_data.max_energy)
			GameManager.add_stat("falls")
			if data.get("water", false):
				lines.append(Loc.t("Тебя подхватило течение и вынесло к лагерю. Потеряна вся энергия (%d).") % lost)
			else:
				lines.append(Loc.t("Ты сорвался в пропасть и очнулся в лагере. Потеряна вся энергия (%d).") % lost)
		_:
			title = Loc.t("Возвращение в лагерь")
			lines.append(Loc.t("Ты возвращаешься с добычей."))
	var found := 0
	for id in run.nodes:
		found += WorldData.node_state(location_id, id).exits.size()
	lines.append(Loc.t("Подлокаций: %d · побед: %d · загадок: %d · сейфов: %d · золота: %d · предметов: %d") % [
		run.nodes.size(), run.fights, run.riddles, run.safes, run.gold, run.items.size()])
	lines.append(Loc.t("Исследовано «%s»: %d%%") % [WorldData.location_info(location_id).get("name", ""), roundi(WorldData.location_progress(location_id) * 100.0)])
	GameManager.player_data.hp = GameManager.player_data.max_hp
	GameManager.player_changed.emit()
	SaveSystem.save_all()
	Audio.play_jingle("levelup" if reason == "leave" else "drop")
	_overlay_panel(title, "\n".join(lines), [[Loc.t("Вернуться"), _return_to_camp, "AccentButton"]])


func _return_to_camp() -> void:
	run = {}
	Audio.pop_music()
	EventBus.back()


func _overlay_panel(title: String, text: String, buttons: Array) -> Control:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"GlassPanel"
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 500
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var t := Label.new()
	t.text = title
	t.theme_type_variation = &"TitleLabel"
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(t)
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(l)
	for b in buttons:
		var btn := Button.new()
		btn.text = b[0]
		if b[2] != "":
			btn.theme_type_variation = StringName(b[2])
		btn.pressed.connect(b[1])
		box.add_child(btn)
	return overlay
