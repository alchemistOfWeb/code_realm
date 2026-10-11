extends Control
## Вылазка в подлокацию: 3D-уровень (поверхность или подземелье), герой от третьего лица, враги,
## жители, сундуки, сейфы, двери-загадки, переходы в соседние подлокации, платформы над пропастью.
##
## Поток: карта локации → вылазка (−10 энергии) → подлокация; найденные переходы открывают соседние
## точки на карте. Поражение в бою — возврат в лагерь (без потери золота). Падение в пропасть —
## гибель: вся энергия теряется, герой возвращается на базу.
## Управление: WASD, Shift — бег (выносливость), F — прыжок, E — действие, M — карта,
## Space — пауза, Esc — меню. Камера: ПКМ — вращение, колесо — приближение, Q/R — поворот.

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
var _gates: Array = []
var _gears: Array = []
var _enemies: Array = []
var _focus: Dictionary = {}
var _explored: PackedByteArray
var _map_image: Image
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

# UI
var _title: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _stamina_bar: ProgressBar
var _loot_label: Label
var _quests: RichTextLabel
var _prompt: PanelContainer
var _prompt_label: Label
var _minimap: TextureRect
var _pause_label: Control
var _menu: Control
var _fade: ColorRect
var _big_map := false


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
			EventBus.notify("Не хватает энергии для вылазки", "error")
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
	_load_node(start_id, _entry_for(start_id))


func _exit_tree() -> void:
	if not run.is_empty():
		Audio.pop_music()


## Откуда «входим» при старте с карты: через найденный проход из соседней подлокации.
func _entry_for(id: String) -> String:
	if id == WorldData.start_node(location_id):
		return ""
	for other in WorldData.node(location_id, id).get("links", []):
		if id in WorldData.node_state(location_id, other).exits:
			return other
	return ""


# ---------------------------------------------------------------- UI

func _build_ui() -> void:
	var container := SubViewportContainer.new()
	container.set_anchors_preset(Control.PRESET_FULL_RECT)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(container)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_2X
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
	st_icon.tooltip_text = "Выносливость: тратится на бег (Shift)"
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

	_minimap = TextureRect.new()
	_minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_minimap.modulate = Color(1, 1, 1, 0.92)
	add_child(_minimap)
	_layout_minimap()

	var help := Label.new()
	help.text = Loc.t("WASD — ходьба · Shift — бег · %s — прыжок · E — действие · M — карта · Space — пауза · Esc — меню · ПКМ — камера") % Settings.action_key_name("jump")
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

	_fade = ColorRect.new()
	_fade.color = Color.BLACK
	_fade.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_fade)


func _layout_minimap() -> void:
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT if not _big_map else Control.PRESET_CENTER)
	if _big_map:
		_minimap.offset_left = -380
		_minimap.offset_right = 380
		_minimap.offset_top = -260
		_minimap.offset_bottom = 260
	else:
		_minimap.offset_left = -250
		_minimap.offset_top = 12
		_minimap.offset_right = -12
		_minimap.offset_bottom = 200


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
		lines.append("[color=#C792EA]◆ %s[/color]\n[color=#8C8CB0]%s[/color]" % [q.title, q.desc])
	var st := WorldData.node_state(location_id, node_id)
	var unfound: PackedStringArray = []
	for e in data.get("exits", []):
		if not e.to in st.exits:
			unfound.append(e.to_name)
	if not unfound.is_empty():
		lines.append("[color=#F5C542]◆ %s[/color]\n[color=#8C8CB0]%s[/color]" % [Loc.t("Найди проходы"), ", ".join(unfound)])
	if _gates_closed():
		lines.append("[color=#F5C542]◆ %s[/color]" % Loc.t("Путь дальше перекрыт решёткой"))
	if _boss_alive():
		lines.append("[color=#FF6B6B]◆ %s[/color]" % Loc.t("Победи стража этого места"))
	_quests.text = "\n".join(lines)


# ---------------------------------------------------------------- Загрузка подлокации

func _load_node(id: String, entry_from: String) -> void:
	_fade.modulate.a = 1.0
	node_id = id
	node = WorldData.node(location_id, id)
	if _world:
		_world.queue_free()
		_world = null
	_interactables.clear()
	_gates.clear()
	_gears.clear()
	_enemies.clear()
	var neighbors: Array = []
	for link in node.get("links", []):
		var n := WorldData.node(location_id, link)
		neighbors.append({"id": link, "name": n.get("name", link), "kind": n.get("kind", "")})
	var seed_value: int = WorldData.node_seed(location_id, id) if int(run.seed_override) < 0 else int(run.seed_override)
	var f: Dictionary = node.get("features", {})
	if WorldData.is_underground(node):
		var opts := f.duplicate()
		opts.neighbors = neighbors
		opts.entry = entry_from
		if not opts.has("npcs"):
			opts.npcs = []
		opts.boss = f.get("boss", "")
		data = DungeonGenerator.generate(int(node.get("floor", 1)), seed_value, run.used, opts)
		data.kind = node.kind
	else:
		data = OutdoorGenerator.generate(node, neighbors, seed_value, entry_from, run.used)
	if data.get("riddle_id", "") != "":
		run.used.riddles.append(data.riddle_id)
	if not data.get("safe", {}).is_empty():
		run.used.safes.append(data.safe.id)
	_world = Node3D.new()
	_viewport.add_child(_world)
	var sky: String = WorldData.location(location_id).get("sky", "day")
	var built := LevelBuilder.build(_world, data, sky)
	astar = built.astar
	_build_entities(float(built.fall_y))
	if node.kind == "dungeon":
		_dungeon_decor()
	_init_minimap()
	var total_enemies: int = data.enemies.size() + (0 if data.boss.is_empty() else 1)
	WorldData.visit_node(location_id, id, data.chests.size(), total_enemies)
	if not id in run.nodes:
		run.nodes.append(id)
	_update_hud()
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 0.0, 0.7)
	EventBus.notify(node.get("name", ""), "info")
	_transitioning = false


func _cell_pos(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0, cell.y + 0.5)


func _build_entities(fall_y: float) -> void:
	var st := WorldData.node_state(location_id, node_id)
	# Игрок
	_player = SortiePlayer.new()
	_player.position = _cell_pos(data.start) + Vector3(0, 0.2, 0)
	_player.fell.connect(_on_fell)
	_world.add_child(_player)
	_player.fall_y = fall_y
	if data.get("underground", false):
		_player.set_lantern(1.8)
	# Смотреть в сторону центра карты
	var center := Vector3(data.w * 0.5, 0, data.h * 0.5)
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
			_interactables.append({"kind": "gate", "node": g, "pos": g.position, "prompt": Loc.t("E — изучить механизм двери")})

	# Переходы в соседние подлокации
	for e in data.exits:
		_make_exit(e)

	# Жители
	for n in data.npcs:
		_spawn_npc(n.id, n.cell)
	if data.get("gate_mode", "") == "warden":
		_spawn_npc("warden", data.warden_cell)

	# Сейф
	if not data.safe.is_empty():
		var safe := _make_safe(data.safe.cell)
		_interactables.append({"kind": "safe", "node": safe, "pos": safe.position, "data": data.safe, "prompt": Loc.t("E — осмотреть сейф")})

	# Сундуки (открытые раньше не появляются снова)
	for i in data.chests.size():
		if i in st.chests:
			continue
		var c: Vector2i = data.chests[i]
		var chest := LevelBuilder.place(_world, LevelBuilder.P + "Chest_Wood.gltf", _cell_pos(c), randf() * TAU, 0.9)
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
		_interactables.append({"kind": "chest", "node": chest, "pos": chest.position, "index": i, "prompt": Loc.t("E — открыть сундук")})

	# Платформы над пропастью / рекой
	for pl in data.get("platforms", []):
		var visual := _platform_visual(pl.size)
		var p := MovingPlatform.create(pl.a, pl.b, pl.size, null, pl.period, pl.phase, visual)
		if data.get("water", false):
			p.bob = 0.08
		else:
			p.bob = 0.03
		_world.add_child(p)

	# Враги (побеждённые раньше не возвращаются)
	for i in data.enemies.size():
		if i in st.kills:
			continue
		var e: Dictionary = data.enemies[i]
		var area: Rect2i = e.get("area", Rect2i(e.cell - Vector2i(3, 3), Vector2i(6, 6)))
		if data.get("underground", false) and e.has("room"):
			area = data.rooms[e.room].rect
		_spawn_enemy(e.id, e.cell, area, i)
	if not data.boss.is_empty() and not st.get("boss", false):
		var area: Rect2i = data.boss.get("area", Rect2i(data.boss.cell - Vector2i(3, 3), Vector2i(6, 6)))
		if data.get("underground", false) and data.has("exit_room"):
			area = data.rooms[data.exit_room].rect
		_spawn_enemy(data.boss.id, data.boss.cell, area, -1)


func _platform_visual(size: Vector3) -> Node3D:
	var root := Node3D.new()
	var path := LevelBuilder.V + ("Floor_UnevenBrick.gltf" if node.kind == "ruins" else "Floor_WoodDark.gltf")
	var top := LevelBuilder.place(root, path, Vector3(0, -0.02, 0), 0.0, size.x / 2.0)
	top.scale.y = 1.0
	var under := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size.x * 0.96, size.y, size.z * 0.96)
	under.mesh = bm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color("#6B4A2E") if node.kind != "ruins" else Color("#7D776E")
	under.material_override = m
	under.position.y = -size.y * 0.5 - 0.03
	root.add_child(under)
	return root


func _make_exit(e: Dictionary) -> void:
	var root := Node3D.new()
	root.position = _cell_pos(e.cell)
	_world.add_child(root)
	var color := Color("#7FDBFF")
	match e.kind:
		"stairs_down", "stairs_up":
			var stairs := LevelBuilder.place(root, LevelBuilder.D + "stairs.glb", Vector3.ZERO)
			CharacterRig.tint(stairs, Color(0.9, 0.8, 0.65))
			if e.kind == "stairs_up":
				color = Color("#FFF2B0")
		"cave", "crypt":
			color = Color("#B08CFF") if e.kind == "cave" else Color("#9FB8E8")
			var arch_path := LevelBuilder.V + ("Wall_Arch.gltf" if e.kind == "crypt" else "")
			if e.kind == "crypt":
				var arch := LevelBuilder.place(root, arch_path, Vector3(0, 0, 0.4), 0.0, 1.0)
				CharacterRig.tint(arch, Color(0.75, 0.78, 0.85))
			else:
				for k in 3:
					var a := PI * (0.15 + 0.35 * k)
					LevelBuilder.place(root, LevelBuilder.N + "Rock_Medium_%d.gltf" % (1 + k), Vector3(cos(a) * 1.3, -0.3, 0.6 + sin(a) * 0.4), a, 0.65)
			var hole := MeshInstance3D.new()
			var disc := CylinderMesh.new()
			disc.top_radius = 0.9
			disc.bottom_radius = 0.9
			disc.height = 0.02
			hole.mesh = disc
			var hm := StandardMaterial3D.new()
			hm.albedo_color = Color("#05040A")
			hm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			hole.material_override = hm
			hole.position = Vector3(0, 0.03, 0)
			root.add_child(hole)
		_:
			# Указатель на тропе
			var post := MeshInstance3D.new()
			var cyl := CylinderMesh.new()
			cyl.top_radius = 0.07
			cyl.bottom_radius = 0.09
			cyl.height = 1.8
			post.mesh = cyl
			var pm := StandardMaterial3D.new()
			pm.albedo_color = Color("#6B4A2E")
			post.material_override = pm
			post.position.y = 0.9
			root.add_child(post)
			var board := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(1.1, 0.32, 0.06)
			board.mesh = bm
			var bmat := StandardMaterial3D.new()
			bmat.albedo_color = Color("#A27A4E")
			board.material_override = bmat
			board.position = Vector3(0.35, 1.5, 0)
			board.rotation.y = randf_range(-0.4, 0.4)
			root.add_child(board)
			color = Color("#FFE08A")
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.95
	tor.outer_radius = 1.1
	ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.albedo_color = color
	rm.emission_enabled = true
	rm.emission = color
	rm.emission_energy_multiplier = 1.5
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ring.material_override = rm
	ring.position.y = 0.05
	root.add_child(ring)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 1.3
	light.omni_range = 3.5
	light.position.y = 1.2
	root.add_child(light)
	var sealed: bool = e.get("sealed", false)
	var label_text := ("🔒 " if sealed else "→ ") + String(e.to_name)
	_label3d(root, label_text, color.lightened(0.3), 2.3, 44)
	var prompt := Loc.t("E — перейти: %s") % e.to_name
	if sealed:
		prompt = Loc.t("E — проход запечатан загадкой")
	_interactables.append({"kind": "exit", "node": root, "pos": root.position, "exit": e, "prompt": prompt})


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


func _spawn_enemy(enemy_id: String, cell: Vector2i, area: Rect2i, index: int) -> void:
	var info: Dictionary = {}
	for e in CardDatabase.all_enemies():
		if e.id == enemy_id:
			info = e
	if info.is_empty():
		return
	var enemy := SortieEnemy.new()
	enemy.index = index
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
	if _world == null or _player == null or not is_instance_valid(_player):
		return
	for g in _gears:
		if is_instance_valid(g):
			g.rotation.z += delta * g.get_meta("speed")
	if _stamina_bar:
		_stamina_bar.max_value = _player.max_stamina
		_stamina_bar.value = _player.stamina
		_stamina_bar.modulate = Color(1, 0.55, 0.55) if _player.exhausted else Color.WHITE
	if _covered or _ended or _paused or _transitioning:
		return
	_update_focus()
	_discover_exits()
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
		if d < best_d:
			best_d = d
			best = it
	_focus = best
	_prompt.visible = not best.is_empty() and _menu == null
	if not best.is_empty():
		_prompt_label.text = best.prompt


## Подошёл к переходу — он открыт на карте локации навсегда.
func _discover_exits() -> void:
	for it in _interactables:
		if it.kind != "exit":
			continue
		var e: Dictionary = it.exit
		if e.get("sealed", false):
			continue
		if _player.global_position.distance_to(it.pos) < DISCOVER_DIST:
			if WorldData.mark_exit(location_id, node_id, e.to):
				Audio.play("reward")
				EventBus.notify(Loc.t("Найден проход: %s. Теперь туда можно отправиться прямо с карты локации.") % e.to_name, "success")
				_update_hud()


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
	elif event.is_action_pressed("map") and _menu == null:
		get_viewport().set_input_as_handled()
		_big_map = not _big_map
		_layout_minimap()
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
			EventBus.go("riddle", {"riddle_id": data.riddle_id, "overlay": true})
		"safe":
			EventBus.go("safe", {"safe_id": it.data.id, "overlay": true})
		"chest":
			_player.act("PickUp_Table")
			_open_chest(it)
		"exit":
			_use_exit(it)


func _use_exit(it: Dictionary) -> void:
	var e: Dictionary = it.exit
	if e.get("sealed", false):
		EventBus.go("riddle", {"riddle_id": data.riddle_id, "overlay": true})
		return
	if _gates_closed() and e.cell in _gated_cells():
		EventBus.notify("Путь перекрыт решёткой", "warning")
		return
	if _boss_alive() and data.underground and e.cell == data.get("exit", Vector2i(-99, -99)):
		EventBus.notify("Страж этого места не даст пройти — победи его", "warning")
		return
	WorldData.mark_exit(location_id, node_id, e.to)
	_transitioning = true
	_prompt.visible = false
	_player.input_enabled = false
	Audio.play("whoosh")
	SaveSystem.save_all()
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.5)
	tw.tween_callback(_load_node.bind(e.to, node_id))


func _gated_cells() -> Array:
	# Выход в комнате за решёткой — главный выход подземелья
	return [data.get("exit", Vector2i(-99, -99))] if data.get("underground", false) else []


# ---------------------------------------------------------------- Перекрытие экранами

func on_cover() -> void:
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
	EventBus.go("combat", {"enemy_id": enemy_id, "context": "expedition"})


func _on_combat_finished(result: Dictionary) -> void:
	if result.get("context") == "expedition" and not run.is_empty():
		_combat_result = result


func _after_combat(result: Dictionary) -> void:
	if result.won:
		run.fights += 1
		run.gold += int(result.get("gold", 0))
		if is_instance_valid(_combat_enemy):
			var idx: int = _combat_enemy.index
			if idx >= 0:
				WorldData.mark_kill(location_id, node_id, idx)
			else:
				WorldData.node_state(location_id, node_id).boss = true
				var st := WorldData.node_state(location_id, node_id)
				if not -1 in st.kills:
					st.kills.append(-1)
				EventBus.notify("Страж повержен! Путь свободен.", "success")
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
		EventBus.notify("Сердце этого края спасено: +50 XP и сундук с картой", "success")


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
			_explored.fill(1)
			_update_minimap()
			EventBus.notify("Карта открыта", "success")
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
	if not solved or riddle_id != data.get("riddle_id", ""):
		return
	run.riddles += 1
	_pending_actions.append({"world": "open_gate"})
	if data.get("gate_mode") == "warden":
		_pending_actions.append({"world": "_leave", "npc": "warden"})
	# Запечатанный загадкой проход открывается
	for it in _interactables:
		if it.kind == "exit" and it.exit.get("sealed", false):
			it.exit.sealed = false
			it.prompt = Loc.t("E — перейти: %s") % it.exit.to_name
			EventBus.notify("Печать спала — проход открыт!", "success")


func _on_safe_finished(safe_id: String, opened: bool) -> void:
	if not opened or data.get("safe", {}).get("id", "") != safe_id:
		return
	run.safes += 1
	GameManager.add_stat("safes")
	GameManager.gain_xp(15)
	for it in _interactables.duplicate():
		if it.kind == "safe":
			_interactables.erase(it)
			var dial = it.node.get_meta("dial")
			if is_instance_valid(dial):
				dial.create_tween().tween_property(dial, "rotation:y", TAU * 2, 1.0)
	var has_greta: bool = data.npcs.any(func(n): return n.id == "greta")
	if has_greta and GameManager.item_count("valve") == 0 and not GameManager.has_flag("valve_returned"):
		GameManager.add_item("valve")
		EventBus.notify("В сейфе — латунный клапан Греты!", "success")
	else:
		var gold := randi_range(15, 30)
		GameManager.add_gold(gold)
		run.gold += gold
		var msg := Loc.t("Сейф открыт: +%d золота") % gold
		var item := _roll_item(0.5)
		if not item.is_empty():
			msg += ", " + Loc.t("предмет «%s»") % item.name
		elif randf() < 0.6:
			var card := CardDatabase.roll_card(CardDatabase.all_cards(), 2.0)
			GameManager.add_card_to_collection(card.id)
			msg += ", " + Loc.t("карта «%s»") % card.name
		EventBus.notify(msg, "success")
	SaveSystem.save_all()


func _open_gates() -> void:
	if _gates.is_empty():
		return
	Audio.play("gate")
	for g in _gates:
		var n: Node3D = g.node
		if is_instance_valid(g.body):
			g.body.queue_free()
		astar.set_point_solid(g.cell, false)
		var tw := n.create_tween()
		tw.tween_property(n, "position:y", -2.0, 1.2).set_trans(Tween.TRANS_CUBIC)
	_gates.clear()
	for it in _interactables.duplicate():
		if it.kind == "gate":
			_interactables.erase(it)
	EventBus.notify("Решётка поднята!", "success")
	_update_hud()


func _gates_closed() -> bool:
	return not _gates.is_empty()


func _boss_alive() -> bool:
	for e in _enemies:
		if is_instance_valid(e) and e.index < 0:
			return true
	return false


## Предмет снаряжения из сундука/сейфа: подходящий по уровню локации.
func _roll_item(chance: float) -> Dictionary:
	if randf() > chance:
		return {}
	var lvl: int = int(WorldData.location_info(location_id).get("level", 1)) + 3
	var pool := ItemDatabase.all_items().filter(func(it): return it.get("price", 0) > 0 and int(it.get("level", 1)) <= lvl)
	if pool.is_empty():
		return {}
	var it: Dictionary = pool.pick_random()
	GameManager.player_data.inventory.append(it.id)
	GameManager.equipment_changed.emit()
	run.items.append(it.id)
	return it


func _open_chest(it: Dictionary) -> void:
	_interactables.erase(it)
	WorldData.mark_chest(location_id, node_id, it.index)
	var lid: Node3D = it.node
	var tw := lid.create_tween()
	tw.tween_property(lid, "scale", Vector3(1.0, 1.15, 1.0) * lid.scale.x, 0.12)
	tw.tween_property(lid, "scale", Vector3.ONE * lid.scale.x, 0.2)
	Audio.play("chest_creak")
	var level: int = int(WorldData.location_info(location_id).get("level", 1))
	var gold: int = randi_range(8, 18) + level * 4
	GameManager.add_gold(gold)
	run.gold += gold
	var msg := Loc.t("Сундук: +%d золота") % gold
	var item := _roll_item(0.25)
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
	sparkle.position = lid.position + Vector3(0, 0.8, 0)
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
	_map_tex = ImageTexture.create_from_image(_map_image)
	_minimap.texture = _map_tex
	_update_minimap()


func _update_minimap() -> void:
	if _player == null or _map_image == null:
		return
	var w: int = data.w
	var h: int = data.h
	var pc := Vector2i(int(_player.global_position.x), int(_player.global_position.z))
	for y in range(pc.y - FOG_RADIUS, pc.y + FOG_RADIUS + 1):
		for x in range(pc.x - FOG_RADIUS, pc.x + FOG_RADIUS + 1):
			if x >= 0 and y >= 0 and x < w and y < h and Vector2i(x, y).distance_to(pc) <= FOG_RADIUS:
				_explored[y * w + x] = 1
	_map_image.fill(Color(0, 0, 0, 0))
	var outdoor: bool = not data.get("underground", false)
	for y in h:
		for x in w:
			var i: int = y * w + x
			if _explored[i] == 0:
				continue
			var v: int = data.grid[i]
			match v:
				0:
					if _near_walkable(x, y):
						_map_image.set_pixel(x, y, Color(0.18, 0.32, 0.16, 0.9) if outdoor else Color(0.35, 0.28, 0.2, 0.9))
				1:
					_map_image.set_pixel(x, y, Color(0.55, 0.78, 0.42, 0.85) if outdoor else Color(0.75, 0.68, 0.58, 0.75))
				2:
					_map_image.set_pixel(x, y, Color(0.82, 0.7, 0.5, 0.85) if outdoor else Color(0.55, 0.5, 0.45, 0.7))
				3:
					_map_image.set_pixel(x, y, Color(0.25, 0.5, 0.75, 0.8) if data.get("water", false) else Color(0.05, 0.04, 0.08, 0.9))
	for g in _gates:
		_dot(g.cell, Color("#FF9F43"))
	for it in _interactables:
		var c := Vector2i(int(it.pos.x), int(it.pos.z))
		match it.kind:
			"npc":
				_dot(c, Color("#C792EA"))
			"safe", "chest":
				_dot(c, Palette.GOLD)
			"exit":
				_dot(c, Color("#7FDBFF"), true)
	for e in _enemies:
		if is_instance_valid(e):
			_dot(Vector2i(int(e.global_position.x), int(e.global_position.z)), Palette.HP)
	_dot(pc, Palette.MINT, true, true)
	_map_tex.update(_map_image)


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

## Space — просто пауза: мир замирает, по центру белая надпись «ПАУЗА».
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
		l.text = "ПАУЗА"
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
	_menu = _overlay_panel("Меню вылазки", Loc.t("%s\nДобыча: %d золота. Найденное золото, предметы и карты остаются с тобой.") % [node.get("name", ""), run.gold],
		[["Продолжить", _toggle_menu, "AccentButton"],
		["Настройки", func(): EventBus.go("settings"), ""],
		["Вернуться в лагерь", func(): _end_run("leave"), ""],
		["Выйти из игры", EventBus.quit_game, "GhostButton"]])


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
	_overlay_panel(title, "\n".join(lines), [["Вернуться", _return_to_camp, "AccentButton"]])


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
