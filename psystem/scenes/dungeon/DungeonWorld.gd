extends Control
## Экспедиция в руины Феррограда — 3D top-down роглайт в SubViewport.
##
## Поток: вход (−30 энергии, колода ≥ 10) → 3 этажа (BSP) → на каждом: NPC с диалогами,
## сейф с Python-кодом, сундуки, враги (бой при касании), выход за решёткой (загадка или Страж).
## Этаж пройден: +10 золота, +5 энергии. Финал — босс «Порченый Компилятор».
## Поражение в бою: экспедиция прервана, −20% золота. HP после экспедиции восстанавливается.
##
## Управление: WASD — ходьба, Shift — бег, E — действие, Space/Esc — пауза.

const PLAYER_SCRIPT := preload("res://scenes/dungeon/Player.gd")
const ENEMY_SCRIPT := preload("res://scenes/dungeon/Enemy.gd")
const M := "res://assets/models/dungeon/"
const INTERACT_DIST := 1.5
const CHUNK := 8
const FOG_RADIUS := 6

var data: Dictionary = {}
var run := {}
var astar: AStarGrid2D

var _viewport: SubViewport
var _world: Node3D
var _camera: Camera3D
var _player: CharacterBody3D
var _interactables: Array = []      # {kind, node, pos: Vector3, data}
var _gates: Array = []              # {node, body, cell}
var _gears: Array = []
var _enemies: Array = []
var _focus: Dictionary = {}
var _explored: PackedByteArray
var _map_image: Image
var _map_tex: ImageTexture
var _map_timer := 0.0
var _covered := false
var _pending_actions: Array = []
var _combat_result: Dictionary = {}
var _combat_enemy: Node = null
var _combat_open_gate := false
var _ended := false

# UI
var _floor_label: Label
var _hp_bar: ProgressBar
var _hp_label: Label
var _gold_label: Label
var _quests: RichTextLabel
var _prompt: PanelContainer
var _prompt_label: Label
var _minimap: TextureRect
var _pause: Control
var _fade: ColorRect


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
	_build_ui()
	if not params.get("free", false):
		if not GameManager.spend_energy(XPCalculator.DUNGEON_ENERGY_COST):
			EventBus.notify("Не хватает энергии для экспедиции", "error")
			EventBus.back.call_deferred()
			return
	GameManager.player_data.hp = GameManager.player_data.max_hp
	GameManager.player_data.dungeon_runs = GameManager.player_data.get("dungeon_runs", 0) + 1
	GameManager.add_stat("expeditions")
	run = {"floor": 1, "gold": 0, "fights": 0, "riddles": 0, "safes": 0, "seed": params.get("seed", randi()),
		"used": {"riddles": [], "safes": []}}
	SaveSystem.save_all()
	Audio.push_music(Audio.MUSIC[1].stream)
	_load_floor(1)


func _exit_tree() -> void:
	if not run.is_empty():
		Audio.pop_music()


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
	info.custom_minimum_size = Vector2(300, 0)
	add_child(info)
	var ib := VBoxContainer.new()
	ib.add_theme_constant_override("separation", 4)
	info.add_child(ib)
	_floor_label = Label.new()
	_floor_label.theme_type_variation = &"HeaderLabel"
	_floor_label.add_theme_font_size_override("font_size", 15)
	ib.add_child(_floor_label)
	var hp_row := HBoxContainer.new()
	ib.add_child(hp_row)
	_hp_bar = ProgressBar.new()
	_hp_bar.theme_type_variation = &"HPBar"
	_hp_bar.show_percentage = false
	_hp_bar.custom_minimum_size = Vector2(180, 12)
	_hp_bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_row.add_child(_hp_bar)
	_hp_label = Label.new()
	_hp_label.theme_type_variation = &"MonoLabel"
	_hp_label.add_theme_color_override("font_color", Palette.HP)
	hp_row.add_child(_hp_label)
	_gold_label = Label.new()
	_gold_label.theme_type_variation = &"MonoLabel"
	_gold_label.add_theme_color_override("font_color", Palette.GOLD)
	_gold_label.add_theme_font_size_override("font_size", 13)
	ib.add_child(_gold_label)
	_quests = RichTextLabel.new()
	_quests.bbcode_enabled = true
	_quests.fit_content = true
	_quests.custom_minimum_size.x = 280
	_quests.add_theme_font_size_override("normal_font_size", 13)
	ib.add_child(_quests)

	_minimap = TextureRect.new()
	_minimap.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_minimap.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	_minimap.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_minimap.offset_left = -232
	_minimap.offset_top = 12
	_minimap.offset_right = -12
	_minimap.offset_bottom = 200
	_minimap.modulate = Color(1, 1, 1, 0.9)
	_minimap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_minimap)

	var help := Label.new()
	help.text = "WASD — ходьба · Shift — бег · E — действие · Space — пауза"
	help.theme_type_variation = &"DimLabel"
	help.add_theme_font_size_override("font_size", 12)
	help.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	help.offset_left = 14
	help.offset_top = -28
	help.offset_bottom = -10
	help.offset_right = 600
	add_child(help)

	_prompt = PanelContainer.new()
	_prompt.add_theme_stylebox_override("panel", Palette.glow_box(Color("#0B0A14", 0.92), Palette.ENERGY, Color(Palette.ENERGY, 0.25), 8, 10))
	_prompt.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_prompt.offset_top = -96
	_prompt.offset_bottom = -56
	_prompt.offset_left = -220
	_prompt.offset_right = 220
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


func _update_hud() -> void:
	if _hp_bar == null or run.is_empty():
		return
	var p := GameManager.player_data
	_floor_label.text = "Этаж %d/%d · %s" % [run.floor, DungeonGenerator.MAX_FLOORS, data.get("name", "")]
	_hp_bar.max_value = p.max_hp
	_hp_bar.value = p.hp
	_hp_label.text = " %d/%d" % [p.hp, p.max_hp]
	_gold_label.text = "Добыча: %d золота · побед: %d · загадок: %d · сейфов: %d" % [run.gold, run.fights, run.riddles, run.safes]
	var lines: PackedStringArray = []
	for q in GameManager.active_quests():
		lines.append("[color=#C792EA]◆ %s[/color]\n[color=#8C8CB0]%s[/color]" % [q.title, q.desc])
	if _gates_closed():
		lines.append("[color=#F5C542]◆ Найди выход[/color]\n[color=#8C8CB0]%s[/color]" % ("Путь к лестнице перекрыт решёткой с загадкой." if data.get("gate_mode") == "riddle" else "Путь к лестнице охраняет Страж Моста."))
	elif not data.get("boss", {}).is_empty() and _boss_alive():
		lines.append("[color=#FF6B6B]◆ Победи стража выхода[/color]")
	else:
		lines.append("[color=#00D4AA]◆ Лестница вниз открыта[/color]")
	_quests.text = "\n".join(lines)


# ---------------------------------------------------------------- Построение этажа

func _load_floor(n: int) -> void:
	_fade.modulate.a = 1.0
	run.floor = n
	if _world:
		_world.queue_free()
	_interactables.clear()
	_gates.clear()
	_gears.clear()
	_enemies.clear()
	data = DungeonGenerator.generate(n, int(run.seed) + n * 7919, run.used)
	run.used.riddles.append(data.riddle_id)
	if not data.safe.is_empty():
		run.used.safes.append(data.safe.id)
	_world = Node3D.new()
	_viewport.add_child(_world)
	_build_environment()
	_build_level()
	_build_entities()
	_init_minimap()
	_update_hud()
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 0.0, 0.6)
	EventBus.notify("Этаж %d: %s" % [n, data.name], "info")


func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color("#06050A")
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#5E4C3A")
	env.ambient_light_energy = 0.9
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.fog_enabled = true
	env.fog_light_color = Color("#1A1410")
	env.fog_density = 0.025
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.05
	var we := WorldEnvironment.new()
	we.environment = env
	_world.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-62, 35, 0)
	sun.light_color = Color("#9DB4D9")
	sun.light_energy = 0.35
	_world.add_child(sun)
	_camera = Camera3D.new()
	_camera.fov = 48
	_world.add_child(_camera)


func _build_level() -> void:
	var w: int = data.w
	var h: int = data.h
	var grid: PackedByteArray = data.grid
	var floor_mesh := CharacterRig.first_mesh(load(M + "floor.glb"))
	var detail_mesh := CharacterRig.first_mesh(load(M + "floor-detail.glb"))
	var wall_mesh := CharacterRig.first_mesh(load(M + "wall.glb"))
	var floor_tint := _tinted(floor_mesh, Color(0.62, 0.56, 0.5))
	var detail_tint := _tinted(detail_mesh, Color(0.66, 0.58, 0.48))
	var wall_tint := _tinted(wall_mesh, Color(0.78, 0.64, 0.48))
	astar = AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	var walls_body := StaticBody3D.new()
	_world.add_child(walls_body)
	var chunks := {}
	for y in h:
		for x in w:
			var v := grid[y * w + x]
			var key := Vector2i(x / CHUNK, y / CHUNK)
			if not chunks.has(key):
				chunks[key] = {"floor": [], "detail": [], "wall": []}
			if v != DungeonGenerator.WALL:
				if (x * 7 + y * 13) % 9 == 0:
					chunks[key].detail.append(Vector3(x + 0.5, 0, y + 0.5))
				else:
					chunks[key].floor.append(Vector3(x + 0.5, 0, y + 0.5))
			else:
				astar.set_point_solid(Vector2i(x, y), true)
				if _near_floor(x, y):
					chunks[key].wall.append(Vector3(x + 0.5, 0, y + 0.5))
					var cs := CollisionShape3D.new()
					var box := BoxShape3D.new()
					box.size = Vector3(1, 2, 1)
					cs.shape = box
					cs.position = Vector3(x + 0.5, 1, y + 0.5)
					walls_body.add_child(cs)
	for key in chunks:
		var c: Dictionary = chunks[key]
		_multimesh(floor_mesh, c.floor, floor_tint)
		_multimesh(detail_mesh, c.detail, detail_tint)
		_multimesh(wall_mesh, c.wall, wall_tint)
	var ground := StaticBody3D.new()
	var gshape := CollisionShape3D.new()
	var plane := WorldBoundaryShape3D.new()
	gshape.shape = plane
	ground.add_child(gshape)
	_world.add_child(ground)

	# Свет комнат
	for r in data.rooms:
		var rect: Rect2i = r.rect
		var light := OmniLight3D.new()
		light.position = Vector3(rect.position.x + rect.size.x / 2.0, 2.6, rect.position.y + rect.size.y / 2.0)
		light.light_color = Color("#FFB070") if r.id != data.exit_room else Color("#8FD8FF")
		light.light_energy = 1.4
		light.omni_range = maxf(rect.size.x, rect.size.y) * 0.85
		light.omni_attenuation = 0.9
		_world.add_child(light)

	# Декор
	var column := load(M + "column.glb")
	for c in data.decor.columns:
		_place(column, c, Color(0.85, 0.72, 0.55))
	var barrel := load(M + "barrel.glb")
	for c in data.decor.barrels:
		_place(barrel, c, Color(0.9, 0.8, 0.7), randf() * TAU)
	var banner := load(M + "banner.glb")
	for c in data.decor.banners:
		var b := _place(banner, c, Color(0.9, 0.6, 0.4))
		b.position.z = c.y + 1.0 + 0.48
	for g in data.decor.gears:
		_make_gear(g.cell, g.size)
	for p in data.decor.pipes:
		_make_pipe(p.from, p.to)


func _near_floor(x: int, y: int) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and ny >= 0 and nx < data.w and ny < data.h and data.grid[ny * data.w + nx] != DungeonGenerator.WALL:
				return true
	return false


func _tinted(mesh: Mesh, color: Color) -> Material:
	if mesh == null:
		return null
	var base := mesh.surface_get_material(0)
	if base is StandardMaterial3D:
		var mat: StandardMaterial3D = base.duplicate()
		mat.albedo_color = color
		return mat
	return null


func _multimesh(mesh: Mesh, points: Array, mat: Material) -> void:
	if points.is_empty() or mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = points.size()
	for i in points.size():
		mm.set_instance_transform(i, Transform3D(Basis(), points[i]))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat:
		mmi.material_override = mat
	_world.add_child(mmi)


func _place(scene: PackedScene, cell: Vector2i, tint: Color, rot := 0.0) -> Node3D:
	var n: Node3D = scene.instantiate()
	n.position = Vector3(cell.x + 0.5, 0, cell.y + 0.5)
	n.rotation.y = rot
	CharacterRig.tint(n, tint)
	_world.add_child(n)
	return n


func _brass(color := Color("#C9A24A")) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.metallic = 0.35
	mat.roughness = 0.4
	mat.emission_enabled = true
	mat.emission = color.darkened(0.6)
	mat.emission_energy_multiplier = 0.4
	return mat


func _make_gear(cell: Vector2i, radius: float) -> void:
	var pivot := Node3D.new()
	pivot.position = Vector3(cell.x + 0.5, 0.75, cell.y + 1.02)
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
	var hub := MeshInstance3D.new()
	var hcyl := CylinderMesh.new()
	hcyl.top_radius = radius * 0.3
	hcyl.bottom_radius = radius * 0.3
	hcyl.height = 0.14
	hub.mesh = hcyl
	hub.material_override = _brass(Color("#6E4A26"))
	hub.rotation_degrees.x = 90
	pivot.add_child(hub)
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
	pipe.position = Vector3(from.x + length / 2.0, 0.95, from.y + 1.08)
	_world.add_child(pipe)
	var steam := CPUParticles3D.new()
	steam.position = Vector3(to.x + 0.9, 0.95, from.y + 1.1)
	steam.amount = 14
	steam.lifetime = 1.8
	steam.direction = Vector3(0.2, 1, 0.3)
	steam.spread = 18
	steam.initial_velocity_min = 0.3
	steam.initial_velocity_max = 0.7
	steam.gravity = Vector3(0, 0.15, 0)
	steam.scale_amount_min = 0.15
	steam.scale_amount_max = 0.4
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 8
	sm.rings = 4
	var smat := StandardMaterial3D.new()
	smat.albedo_color = Color(1, 1, 1, 0.12)
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	sm.material = smat
	steam.mesh = sm
	_world.add_child(steam)


func _build_entities() -> void:
	# Игрок
	_player = PLAYER_SCRIPT.new()
	_player.position = _cell_pos(data.start)
	_world.add_child(_player)

	# Решётки к выходу
	var gate_scene := load(M + "gate.glb")
	for cell in data.gates:
		var g: Node3D = gate_scene.instantiate()
		g.position = _cell_pos(cell)
		var er: Rect2i = data.rooms[data.exit_room].rect
		if cell.x < er.position.x or cell.x >= er.end.x:
			g.rotation.y = PI / 2
		CharacterRig.tint(g, Color(0.85, 0.65, 0.4))
		_world.add_child(g)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1, 2, 1)
		cs.shape = box
		cs.position.y = 1
		body.add_child(cs)
		g.add_child(body)
		astar.set_point_solid(cell, true)
		_gates.append({"node": g, "body": body, "cell": cell})
		if data.gate_mode == "riddle":
			_interactables.append({"kind": "gate", "node": g, "pos": g.position, "prompt": "E — изучить механизм двери"})

	# Лестница вниз
	var stairs: Node3D = _place(load(M + "stairs.glb"), data.exit, Color(0.9, 0.8, 0.65))
	var glow := OmniLight3D.new()
	glow.light_color = Color("#7FDBFF")
	glow.light_energy = 2.0
	glow.omni_range = 3.0
	glow.position.y = 1.0
	stairs.add_child(glow)
	_label3d(stairs, "Спуск ↓" if run.floor < DungeonGenerator.MAX_FLOORS else "Выход из руин", Color("#7FDBFF"), 1.5)
	_interactables.append({"kind": "stairs", "node": stairs, "pos": stairs.position, "prompt": "E — спуститься ниже" if run.floor < DungeonGenerator.MAX_FLOORS else "E — покинуть руины с добычей"})

	# NPC
	for n in data.npcs:
		_spawn_npc(n.id, n.cell)
	if data.gate_mode == "warden":
		_spawn_npc("warden", data.warden_cell)

	# Сейф
	if not data.safe.is_empty():
		var safe := _make_safe(data.safe.cell)
		_interactables.append({"kind": "safe", "node": safe, "pos": safe.position, "data": data.safe, "prompt": "E — осмотреть сейф"})

	# Сундуки
	var chest_scene := load(M + "chest.glb")
	for c in data.chests:
		var chest: Node3D = _place(chest_scene, c, Color(1, 0.9, 0.75), randf() * TAU)
		_interactables.append({"kind": "chest", "node": chest, "pos": chest.position, "prompt": "E — открыть сундук"})

	# Враги
	for e in data.enemies:
		_spawn_enemy(e.id, e.cell, data.rooms[e.room].rect)
	if not data.boss.is_empty():
		_spawn_enemy(data.boss.id, data.boss.cell, data.rooms[data.exit_room].rect)
	_camera_follow(1.0)


func _spawn_npc(npc_id: String, cell: Vector2i) -> void:
	var info := DialogueRunner.get_npc(npc_id)
	if info.is_empty():
		return
	var model_path := M + ("character-orc.glb" if info.get("model") == "orc" else "character-human.glb")
	var root := Node3D.new()
	root.position = _cell_pos(cell)
	_world.add_child(root)
	var model: Node3D = load(model_path).instantiate()
	if npc_id == "warden":
		model.scale = Vector3.ONE * 1.7
	root.add_child(model)
	CharacterRig.tint(model, Color.from_string(info.get("tint", "#FFFFFF"), Color.WHITE))
	var anim: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	CharacterRig.setup_loops(anim)
	if anim and anim.has_animation("idle"):
		anim.play("idle")
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.3 if npc_id != "warden" else 0.5
	cyl.height = 1.5
	cs.shape = cyl
	cs.position.y = 0.75
	body.add_child(cs)
	root.add_child(body)
	var color := Color.from_string(info.get("color", "#FFFFFF"), Color.WHITE)
	_label3d(root, info.name, color.lightened(0.3), 1.35 if npc_id != "warden" else 1.95)
	var marker := _label3d(root, "!" if not GameManager.has_flag(npc_id + "_met") else "…", Palette.ENERGY, 1.65 if npc_id != "warden" else 2.25, 80)
	root.set_meta("marker", marker)
	_interactables.append({"kind": "npc", "node": root, "pos": root.position, "id": npc_id, "prompt": "E — поговорить: %s" % info.name})
	if npc_id == "warden":
		astar.set_point_solid(cell, true)


func _spawn_enemy(enemy_id: String, cell: Vector2i, rect: Rect2i) -> void:
	var info: Dictionary = {}
	for e in CardDatabase.all_enemies():
		if e.id == enemy_id:
			info = e
	if info.is_empty():
		return
	var enemy: CharacterBody3D = ENEMY_SCRIPT.new()
	enemy.setup(info, _cell_pos(cell), rect, astar, _player)
	enemy.contact.connect(_on_enemy_contact)
	_world.add_child(enemy)
	_enemies.append(enemy)


func _make_safe(cell: Vector2i) -> Node3D:
	var root := Node3D.new()
	root.position = _cell_pos(cell)
	_world.add_child(root)
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.62, 0.6, 0.5)
	box.mesh = bm
	box.material_override = _brass(Color("#8C6B2E"))
	box.position.y = 0.3
	root.add_child(box)
	var dial := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.12
	cyl.bottom_radius = 0.12
	cyl.height = 0.05
	dial.mesh = cyl
	dial.material_override = _brass(Color("#E8C872"))
	dial.rotation_degrees.x = 90
	dial.position = Vector3(0, 0.34, 0.27)
	root.add_child(dial)
	root.set_meta("dial", dial)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.62, 0.6, 0.5)
	cs.shape = shape
	cs.position.y = 0.3
	body.add_child(cs)
	root.add_child(body)
	_label3d(root, "Сейф", Color("#E8C872"), 0.95)
	return root


func _label3d(parent: Node3D, text: String, color: Color, height: float, size := 40) -> Label3D:
	var l := Label3D.new()
	l.text = text
	l.font_size = size
	l.outline_size = 10
	l.modulate = color
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.pixel_size = 0.004
	l.no_depth_test = true
	l.position.y = height
	parent.add_child(l)
	return l


func _cell_pos(cell: Vector2i) -> Vector3:
	return Vector3(cell.x + 0.5, 0, cell.y + 0.5)


# ---------------------------------------------------------------- Цикл

func _process(delta: float) -> void:
	if _world == null or _player == null:
		return
	for g in _gears:
		if is_instance_valid(g):
			g.rotation.z += delta * g.get_meta("speed")
	if _covered or _ended:
		return
	_camera_follow(delta)
	_update_focus()
	_map_timer -= delta
	if _map_timer <= 0.0:
		_map_timer = 0.15
		_update_minimap()


func _camera_follow(delta: float) -> void:
	var target := _player.global_position + Vector3(0, 9.5, 4.4)
	_camera.position = target if delta >= 1.0 else _camera.position.lerp(target, minf(1.0, delta * 6.0))
	_camera.look_at(_player.global_position + Vector3(0, 0.3, 0), Vector3.UP)


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
	_prompt.visible = not best.is_empty()
	if not best.is_empty():
		_prompt_label.text = best.prompt


func _unhandled_input(event: InputEvent) -> void:
	if _covered or _ended or run.is_empty():
		return
	if event.is_action_pressed("pause") or event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_toggle_pause()
	elif event.is_action_pressed("interact") and not _focus.is_empty() and _pause == null:
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
			_open_chest(it)
		"stairs":
			_use_stairs()


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
	if _world:
		_world.process_mode = Node.PROCESS_MODE_INHERIT
	if _player:
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
	if _covered or _ended or _pause != null:
		enemy.resume()
		return
	_start_combat(enemy, enemy.enemy_data.id)


func _start_combat(enemy, enemy_id: String) -> void:
	_combat_enemy = enemy
	Audio.play("hit_heavy")
	EventBus.go("combat", {"enemy_id": enemy_id, "context": "expedition"})


func _on_combat_finished(result: Dictionary) -> void:
	if result.get("context") == "expedition" and not run.is_empty():
		_combat_result = result


func _after_combat(result: Dictionary) -> void:
	if result.won:
		run.fights += 1
		run.gold += int(result.get("gold", 0))
		if is_instance_valid(_combat_enemy):
			_combat_enemy.die()
			_enemies.erase(_combat_enemy)
		if _combat_open_gate:
			_combat_open_gate = false
			_open_gates()
		_combat_enemy = null
		_update_hud()
	else:
		_combat_enemy = null
		_end_run(false)


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
			EventBus.notify("Карта этажа открыта", "success")
		"combat":
			_combat_open_gate = a.get("open_gate_on_win", false)
			_start_combat(null, a.get("enemy", "syntax_error"))
		"riddle":
			EventBus.go("riddle", {"riddle_id": data.riddle_id, "overlay": true})
		"_leave":
			for it in _interactables.duplicate():
				if it.kind == "npc" and it.get("id") == a.npc:
					_interactables.erase(it)
					var node: Node3D = it.node
					var tw := node.create_tween()
					tw.tween_property(node, "scale", Vector3(1, 0.01, 1), 0.6)
					tw.tween_callback(node.queue_free)
					if a.npc == "warden" and data.warden_cell != Vector2i(-1, -1):
						astar.set_point_solid(data.warden_cell, false)


func _on_riddle_finished(riddle_id: String, solved: bool) -> void:
	if solved and riddle_id == data.get("riddle_id", ""):
		run.riddles += 1
		_pending_actions.append({"world": "open_gate"})
		if data.get("gate_mode") == "warden":
			_pending_actions.append({"world": "_leave", "npc": "warden"})


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
	if data.safe.reward == "valve":
		GameManager.add_item("valve")
		EventBus.notify("В сейфе — латунный клапан Греты!", "success")
	else:
		var gold := randi_range(15, 30)
		GameManager.add_gold(gold)
		run.gold += gold
		var msg := "Сейф открыт: +%d золота" % gold
		if randf() < 0.6:
			var card := CardDatabase.roll_card(CardDatabase.all_cards(), 2.0)
			GameManager.add_card_to_collection(card.id)
			msg += ", карта «%s»" % card.name
		EventBus.notify(msg, "success")
	SaveSystem.save_all()


func _open_gates() -> void:
	if _gates.is_empty():
		return
	Audio.play("gate")
	for g in _gates:
		var node: Node3D = g.node
		if is_instance_valid(g.body):
			g.body.queue_free()
		astar.set_point_solid(g.cell, false)
		var tw := node.create_tween()
		tw.tween_property(node, "position:y", -0.9, 1.2).set_trans(Tween.TRANS_CUBIC)
	_gates.clear()
	for it in _interactables.duplicate():
		if it.kind == "gate":
			_interactables.erase(it)
	EventBus.notify("Решётка к выходу поднята!", "success")
	_update_hud()


func _gates_closed() -> bool:
	return not _gates.is_empty()


func _boss_alive() -> bool:
	for e in _enemies:
		if is_instance_valid(e) and e.is_boss:
			return true
	return false


func _open_chest(it: Dictionary) -> void:
	_interactables.erase(it)
	var anim: AnimationPlayer = it.node.find_child("AnimationPlayer", true, false)
	if anim and anim.get_animation_list().size() > 0:
		var list := anim.get_animation_list()
		anim.play("open" if anim.has_animation("open") else list[list.size() - 1])
	Audio.play("chest_creak")
	var gold: int = randi_range(8, 20) + int(run.floor) * 4
	GameManager.add_gold(gold)
	run.gold += gold
	var msg := "Сундук: +%d золота" % gold
	if randf() < 0.35:
		var healed := GameManager.heal_player(8)
		msg += ", зелье (+%d HP)" % healed
	if randf() < 0.2:
		var card := CardDatabase.roll_card(CardDatabase.all_cards(), 1.5)
		GameManager.add_card_to_collection(card.id)
		msg += ", карта «%s»" % card.name
	Audio.play("coins")
	EventBus.notify(msg, "success")
	_update_hud()


func _use_stairs() -> void:
	if _gates_closed():
		EventBus.notify("Путь к лестнице закрыт", "warning")
		return
	if _boss_alive():
		EventBus.notify("Страж выхода не даст уйти — победи его", "warning")
		return
	GameManager.add_gold(10)
	GameManager.gain_energy(5)
	run.gold += 10
	GameManager.world.stats.deepest_floor = maxi(GameManager.world.stats.get("deepest_floor", 0), run.floor)
	SaveSystem.save_all()
	if run.floor >= DungeonGenerator.MAX_FLOORS:
		_end_run(true)
		return
	Audio.play("whoosh")
	EventBus.notify("Этаж пройден: +10 золота, +5 энергии", "success")
	var tw := create_tween()
	tw.tween_property(_fade, "modulate:a", 1.0, 0.5)
	tw.tween_callback(_load_floor.bind(run.floor + 1))


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
	var pc := Vector2i(int(_player.global_position.x), int(_player.global_position.z))
	for y in range(pc.y - FOG_RADIUS, pc.y + FOG_RADIUS + 1):
		for x in range(pc.x - FOG_RADIUS, pc.x + FOG_RADIUS + 1):
			if x >= 0 and y >= 0 and x < data.w and y < data.h and Vector2i(x, y).distance_to(pc) <= FOG_RADIUS:
				_explored[y * data.w + x] = 1
	_map_image.fill(Color(0, 0, 0, 0))
	for y in data.h:
		for x in data.w:
			var i: int = y * data.w + x
			if _explored[i] == 0:
				continue
			var v: int = data.grid[i]
			if v == DungeonGenerator.WALL:
				if _near_floor(x, y):
					_map_image.set_pixel(x, y, Color(0.35, 0.28, 0.2, 0.9))
			else:
				_map_image.set_pixel(x, y, Color(0.75, 0.68, 0.58, 0.75) if v == DungeonGenerator.FLOOR else Color(0.55, 0.5, 0.45, 0.7))
	for g in _gates:
		_dot(g.cell, Color("#FF9F43"))
	_dot(data.exit, Color("#7FDBFF"))
	for it in _interactables:
		var c := Vector2i(int(it.pos.x), int(it.pos.z))
		match it.kind:
			"npc":
				_dot(c, Color("#C792EA"))
			"safe", "chest":
				_dot(c, Palette.GOLD)
	for e in _enemies:
		if is_instance_valid(e):
			_dot(Vector2i(int(e.global_position.x), int(e.global_position.z)), Palette.HP)
	_map_image.set_pixel(clampi(pc.x, 0, data.w - 1), clampi(pc.y, 0, data.h - 1), Palette.MINT)
	_map_tex.update(_map_image)


func _dot(c: Vector2i, color: Color) -> void:
	if c.x >= 0 and c.y >= 0 and c.x < data.w and c.y < data.h and _explored[c.y * data.w + c.x] == 1:
		_map_image.set_pixel(c.x, c.y, color)


# ---------------------------------------------------------------- Пауза и итоги

func _toggle_pause() -> void:
	if _pause != null:
		_pause.queue_free()
		_pause = null
		_player.input_enabled = true
		_world.process_mode = Node.PROCESS_MODE_INHERIT
		return
	_player.input_enabled = false
	_world.process_mode = Node.PROCESS_MODE_DISABLED
	_pause = _overlay_panel("Пауза", "Этаж %d · добыча %d золота.\nМожно вернуться в лагерь — найденное золото и карты останутся с тобой." % [run.floor, run.gold],
		[["Продолжить", _toggle_pause, "AccentButton"], ["Вернуться в лагерь", func(): _end_run(true, true), ""]])


func _end_run(success: bool, left_early: bool = false) -> void:
	if _ended:
		return
	_ended = true
	if _pause:
		_pause.queue_free()
		_pause = null
	var lines: PackedStringArray = []
	var title := ""
	if not success:
		var lost := int(GameManager.player_data.gold * 0.2)
		GameManager.add_gold(-lost)
		title = "Экспедиция прервана"
		lines.append("Ты теряешь сознание, и тебя выносят к лагерю. Потеряно %d золота (20%%)." % lost)
	elif left_early:
		title = "Возвращение в лагерь"
		lines.append("Ты благоразумно отступаешь с добычей.")
	else:
		title = "Руины покорены!"
		GameManager.gain_xp(50)
		GameManager.player_data.lootboxes = GameManager.lootbox_count() + 1
		GameManager.set_flag("ruins_cleared")
		lines.append("Порченый Компилятор повержен — сердце Механизма снова бьётся. +50 XP и сундук с картой.")
	lines.append("Этажей: %d · побед: %d · загадок: %d · сейфов: %d · золота: %d" % [run.floor, run.fights, run.riddles, run.safes, run.gold])
	GameManager.player_data.hp = GameManager.player_data.max_hp
	GameManager.player_changed.emit()
	SaveSystem.save_all()
	Audio.play_jingle("fanfare" if success and not left_early else ("levelup" if success else "drop"))
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
	box.custom_minimum_size.x = 480
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
