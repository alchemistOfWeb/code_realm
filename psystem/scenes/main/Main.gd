extends Control
## Корневая сцена: фон, стек экранов (навигация), HUD, уведомления, баннер уровня, игровое меню.
##
## Старт — главное меню (выбор профиля). После выбора профиля корнем стека становится WorldTree.
## Навигация: EventBus.go("screen_key", params) кладёт экран на стек, EventBus.back() снимает.
## params.root = true — очистить стек и сделать экран корневым.
## Экран может реализовать setup(params) и on_resume() (вызывается при возврате на него).
## params.replace = true — заменить верхний экран вместо добавления.
## params.overlay = true — экран-оверлей: предыдущий экран остаётся видимым под ним.
##
## Dev-аргументы (после "--" в командной строке):
##   --screen=menu | creator | credits | shop | map | location:<id> | sortie:<loc>:<node> | world | mini:<spec_id> | lesson:<node_id> | character[:tab] | settings
##            test:<spec_id> [--answer=N [--finish]] | reward:<spec_id> | lootbox [--open]
##            combat:<enemy_id> [--auto=N] | dungeon[:seed] [--walk=N] | dialogue:<npc> [--pick=N] | riddle:<id> | safe:<id>
##   --shot=<abs_path.png> [--shot-delay=1.5]  — сделать скриншот и выйти (пишет в user://dev_saves/)
##   --demo  — демо-прогресс (user://demo_saves/), --levelup, --toast=<текст>

const SCREENS := {
	"main_menu": "res://scenes/menu/MainMenu.tscn",
	"creator": "res://scenes/menu/CharacterCreator.tscn",
	"credits": "res://scenes/menu/Credits.tscn",
	"shop": "res://scenes/shop/ShopScreen.tscn",
	"world_map": "res://scenes/world/WorldMap.tscn",
	"location": "res://scenes/world/LocationMap.tscn",
	"sortie": "res://scenes/world/SortieWorld.tscn",
	"world": "res://scenes/knowledge/WorldTree.tscn",
	"mini_tree": "res://scenes/knowledge/MiniTree.tscn",
	"lesson": "res://scenes/knowledge/LessonPage.tscn",
	"character": "res://scenes/character/CharacterScreen.tscn",
	"settings": "res://scenes/settings/SettingsScreen.tscn",
	"test": "res://scenes/knowledge/TestScreen.tscn",
	"reward": "res://scenes/rewards/RewardScroll.tscn",
	"lootbox": "res://scenes/rewards/LootBox.tscn",
	"combat": "res://scenes/combat/CombatScreen.tscn",
	"dialogue": "res://scenes/dialogue/DialogueScreen.tscn",
	"riddle": "res://scenes/dungeon/RiddleScreen.tscn",
	"safe": "res://scenes/dungeon/SafeScreen.tscn",
}
const RAYS := preload("res://shaders/rays.gdshader")
## Экраны на всё окно: без верхней панели HUD.
const FULLSCREEN := ["main_menu", "creator", "credits", "sortie"]
const HUD_HEIGHT := 64.0

const TOAST_ICONS := {
	"info": "info", "success": "check", "warning": "info", "error": "x", "xp": "sparkles",
}
const TOAST_COLORS := {
	"info": Palette.ACCENT, "success": Palette.MINT, "warning": Palette.ENERGY,
	"error": Palette.HP, "xp": Palette.ACCENT,
}

@onready var screen_root: Control = $ScreenRoot
@onready var toast_box: VBoxContainer = $Overlay/ToastBox
@onready var overlay: CanvasLayer = $Overlay

var _stack: Array[Control] = []
var _level_banner: Control
var _game_menu: Control


func _ready() -> void:
	EventBus.navigate.connect(_push)
	EventBus.navigate_back.connect(_pop)
	EventBus.navigate_home.connect(_home)
	EventBus.toast.connect(_show_toast)
	EventBus.quit_requested.connect(_quit)
	EventBus.game_menu_requested.connect(_toggle_game_menu)
	GameManager.level_up.connect(_on_level_up)
	var args := _dev_args()
	if args.has("lang"):
		Loc.setup(args.lang)   # dev: язык без сохранения в настройки
	if args.has("graphics"):
		Settings.values.graphics = args.graphics   # dev: качество графики без сохранения
	if args.has("screen") or args.has("demo"):
		_dev_profile(args)
		var screen: String = args.get("screen", "")
		if screen in ["menu", "creator", "credits"]:
			_push("main_menu", {})
		else:
			_push("world", {})
		_apply_dev_args(args)
	else:
		_push("main_menu", {})


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		_save_before_exit()


func _save_before_exit() -> void:
	SaveSystem.save_all()
	if SaveSystem.has_active_profile() and not GameManager.claude_notes.is_empty():
		ClaudeNotesExporter.export_all()


func _quit() -> void:
	_save_before_exit()
	get_tree().quit()


func _unhandled_input(event: InputEvent) -> void:
	var back := event.is_action_pressed("ui_cancel")
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_XBUTTON1:
		back = true
	if not back:
		return
	if is_instance_valid(_game_menu):
		_toggle_game_menu()
		get_viewport().set_input_as_handled()
	elif _stack.size() > 1:
		_pop()
		get_viewport().set_input_as_handled()
	elif current_screen_key() == "world" and event.is_action_pressed("ui_cancel"):
		_toggle_game_menu()
		get_viewport().set_input_as_handled()


# ---------------------------------------------------------------- Навигация

func _push(key: String, params: Dictionary) -> void:
	if not SCREENS.has(key):
		push_error(Loc.t("Main: неизвестный экран ") + key)
		return
	if is_instance_valid(_game_menu):
		_game_menu.queue_free()
	if params.get("root", false):
		while not _stack.is_empty():
			_stack.pop_back().queue_free()
	if params.get("replace", false) and _stack.size() > 1:
		_stack.pop_back().queue_free()
	if not _stack.is_empty() and _stack[-1].has_method("on_cover"):
		_stack[-1].on_cover()
	if not _stack.is_empty():
		if params.get("overlay", false):
			_stack[-1].show()   # оверлей лежит поверх видимого экрана (в т.ч. после replace)
		else:
			_stack[-1].hide()
	var screen: Control = load(SCREENS[key]).instantiate()
	screen.set_meta("screen_key", key)
	screen_root.add_child(screen)
	_stack.append(screen)
	if screen.has_method("setup"):
		screen.setup(params)
	_update_chrome()
	_fade_in(screen)


func _pop() -> void:
	if _stack.size() <= 1:
		return
	Audio.play("back")
	_stack.pop_back().queue_free()
	_resume_top()


func _home() -> void:
	if _stack.size() > 1:
		Audio.play("back")
	while _stack.size() > 1:
		_stack.pop_back().queue_free()
	_resume_top()


func _resume_top() -> void:
	_update_chrome()
	var top := _stack[-1]
	var was_visible := top.visible   # под оверлеем экран оставался видимым
	top.show()
	if top.has_method("on_resume"):
		top.on_resume()
	if not was_visible:
		_fade_in(top)


func _fade_in(screen: Control) -> void:
	screen.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(screen, "modulate:a", 1.0, 0.18)


## HUD скрыт на полноэкранных экранах (меню, создание героя, вылазка).
func _update_chrome() -> void:
	if _stack.is_empty():
		return
	var full := current_screen_key() in FULLSCREEN
	$HUD.visible = not full
	screen_root.offset_top = 0.0 if full else HUD_HEIGHT


func current_screen_key() -> String:
	return _stack[-1].get_meta("screen_key", "") if not _stack.is_empty() else ""


# ---------------------------------------------------------------- Игровое меню (Esc)

func _toggle_game_menu() -> void:
	if is_instance_valid(_game_menu):
		_game_menu.queue_free()
		_game_menu = null
		return
	Audio.play("open")
	var layer := Control.new()
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_STOP
	overlay.add_child(layer)
	_game_menu = layer
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.add_child(center)
	var panel := PanelContainer.new()
	panel.theme_type_variation = &"GlassPanel"
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 320
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = Loc.t("Меню")
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var items := [
		[Loc.t("Продолжить"), "chevron-right", _toggle_game_menu, "AccentButton"],
		[Loc.t("Настройки"), "settings", func(): EventBus.go("settings"), ""],
		[Loc.t("Титры"), "scroll-text", func(): EventBus.go("credits"), ""],
		[Loc.t("Главное меню"), "arrow-left", EventBus.go_main_menu, ""],
		[Loc.t("Выйти из игры"), "x", _quit, "GhostButton"],
	]
	for it in items:
		var b := Button.new()
		b.text = it[0]
		b.icon = Palette.icon(it[1])
		b.custom_minimum_size.y = 42
		if it[3] != "":
			b.theme_type_variation = StringName(it[3])
		b.pressed.connect(it[2])
		box.add_child(b)


# ---------------------------------------------------------------- Уведомления

func _show_toast(text: String, kind: String) -> void:
	match kind:
		"error":
			Audio.play("error")
		"xp":
			pass
		_:
			Audio.play("notify")
	var color: Color = TOAST_COLORS.get(kind, Palette.ACCENT)
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := Palette.glow_box(Color("#0B0B18", 0.95), Color(color, 0.8), Color(color, 0.25), 8, 10)
	sb.content_margin_left = 14
	sb.content_margin_right = 16
	sb.content_margin_top = 10
	sb.content_margin_bottom = 10
	panel.add_theme_stylebox_override("panel", sb)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)
	var icon := TextureRect.new()
	icon.texture = Palette.icon(TOAST_ICONS.get(kind, "info"))
	icon.custom_minimum_size = Vector2(20, 20)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = color
	row.add_child(icon)
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.custom_minimum_size.x = 300
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	toast_box.add_child(panel)
	while toast_box.get_child_count() > 5:
		toast_box.get_child(0).free()

	panel.modulate.a = 0.0
	var tw := panel.create_tween()
	tw.tween_property(panel, "modulate:a", 1.0, 0.2)
	tw.tween_interval(2.8)
	tw.tween_property(panel, "modulate:a", 0.0, 0.4)
	tw.tween_callback(panel.queue_free)


func _on_level_up(new_level: int) -> void:
	if "--shot" in " ".join(OS.get_cmdline_user_args()) and not "--levelup" in " ".join(OS.get_cmdline_user_args()):
		return   # скриншоты без баннера
	# Несколько уровней подряд — показываем один баннер с последним уровнем
	if is_instance_valid(_level_banner):
		_level_banner.queue_free()
	Audio.play_jingle("levelup")
	var layer := Control.new()
	_level_banner = layer
	layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	overlay.add_child(layer)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(center)

	# Лучи света за баннером
	var rays := ColorRect.new()
	rays.size = Vector2(760, 760)
	rays.position = get_viewport_rect().size / 2.0 - rays.size / 2.0
	rays.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var rm := ShaderMaterial.new()
	rm.shader = RAYS
	rm.set_shader_parameter("ray_color", Palette.ENERGY)
	rm.set_shader_parameter("intensity", 0.55)
	rm.set_shader_parameter("speed", 0.35)
	rays.material = rm
	rays.pivot_offset = rays.size / 2.0
	rays.scale = Vector2(0.3, 0.3)
	layer.add_child(rays)
	layer.move_child(rays, 0)
	rays.create_tween().tween_property(rays, "scale", Vector2.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# Золотые искры
	var sparks := CPUParticles2D.new()
	sparks.position = get_viewport_rect().size / 2.0
	sparks.one_shot = true
	sparks.amount = 90
	sparks.lifetime = 1.6
	sparks.explosiveness = 0.9
	sparks.spread = 180.0
	sparks.initial_velocity_min = 160.0
	sparks.initial_velocity_max = 460.0
	sparks.gravity = Vector2(0, 260)
	sparks.scale_amount_min = 2.0
	sparks.scale_amount_max = 6.0
	var ramp := Gradient.new()
	ramp.set_color(0, Color("#FFF6C8"))
	ramp.set_color(1, Color(Palette.ENERGY, 0.0))
	sparks.color_ramp = ramp
	layer.add_child(sparks)
	sparks.emitting = true

	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := Palette.glow_box(Color("#0B0B18", 0.95), Palette.ENERGY, Color(Palette.ENERGY, 0.35), 30, 18)
	sb.content_margin_left = 60
	sb.content_margin_right = 60
	sb.content_margin_top = 26
	sb.content_margin_bottom = 26
	panel.add_theme_stylebox_override("panel", sb)
	center.add_child(panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_child(box)
	var caption := Label.new()
	caption.text = Loc.t("НОВЫЙ УРОВЕНЬ")
	caption.theme_type_variation = &"MonoLabel"
	caption.add_theme_color_override("font_color", Palette.ENERGY)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)
	var title := Label.new()
	title.text = str(new_level)
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 64)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var sub := Label.new()
	sub.text = Loc.t("+1 очко атрибутов  ·  HP %d  ·  сундук с картой") % GameManager.player_data.max_hp
	sub.theme_type_variation = &"DimLabel"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(sub)

	panel.pivot_offset = panel.get_combined_minimum_size() / 2.0
	panel.scale = Vector2(0.6, 0.6)
	layer.modulate.a = 0.0
	var tw := layer.create_tween().set_parallel()
	tw.tween_property(layer, "modulate:a", 1.0, 0.25)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.45).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.chain().tween_interval(2.6)
	tw.chain().tween_property(layer, "modulate:a", 0.0, 0.5)
	tw.chain().tween_callback(layer.queue_free)


# ---------------------------------------------------------------- Dev-аргументы

func _dev_args() -> Dictionary:
	var args := {}
	for arg in OS.get_cmdline_user_args():
		var kv := arg.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	return args


## Dev-запуск: профиль не выбирается вручную. --demo → демо-прогресс, --shot → user://dev_saves/,
## иначе — последний профиль (или dev_saves, если профилей нет).
func _dev_profile(args: Dictionary) -> void:
	if args.has("demo"):
		_fill_demo_progress()
	elif args.has("shot") or SaveSystem.last_profile_id() == "":
		SaveSystem.use_dir("user://dev_saves/", true)
	else:
		SaveSystem.select_profile(SaveSystem.last_profile_id())


func _apply_dev_args(args: Dictionary) -> void:
	if args.has("autodeck"):
		GameManager.grant_starter_pack()
		for i in 12:
			GameManager.add_card_to_collection(CardDatabase.roll_card([], 2.0).id)
		GameManager.auto_build_deck()
	if args.has("screen"):
		var parts: PackedStringArray = args.screen.split(":", true, 1)
		match parts[0]:
			"mini":
				EventBus.go("mini_tree", {"spec_id": parts[1]})
			"lesson":
				var node := ContentParser.get_node_data(parts[1])
				EventBus.go("mini_tree", {"spec_id": node.get("spec_id", "")})
				EventBus.go("lesson", {"node_id": parts[1]})
			"character":
				EventBus.go("character", {"tab": parts[1].to_int() if parts.size() > 1 else 0})
			"settings":
				EventBus.go("settings")
			"test":
				EventBus.go("mini_tree", {"spec_id": parts[1]})
				EventBus.go("test", {"mode": "tree", "spec_id": parts[1]})
				if args.has("answer"):
					var ts = _stack[-1]
					ts._on_answer(args.answer.to_int())
					if args.has("finish"):
						while ts.result.is_empty():
							ts._on_next()
							if ts.result.is_empty():
								ts._on_answer(ts.questions[ts.index].correct)
			"reward":
				EventBus.go("mini_tree", {"spec_id": parts[1]})
				EventBus.go("reward", {"overlay": true, "result": {"spec_id": parts[1], "first": true, "correct": 9, "total": 10,
					"xp": GameManager.tree_xp_bonus(parts[1]), "energy": 20, "nodes_marked": 42,
					"cards": CardDatabase.roll_tree_cards(parts[1], 3)}})
			"combat":
				GameManager.grant_starter_pack()
				EventBus.go("combat", {"enemy_id": parts[1] if parts.size() > 1 else "syntax_error", "context": "training"})
				if args.has("layout"):
					await get_tree().create_timer(1.0).timeout
					var col: Control = _stack[-1]._hand.get_parent()
					print("screen ", _stack[-1].get_global_rect(), " viewport ", get_viewport_rect().size)
					for c in col.get_children():
						print("  ", c.get_class(), " ", c.get_global_rect(), " min ", c.get_combined_minimum_size())
					for c in _stack[-1]._hand.get_children():
						print("    card ", c.get_global_rect())
				if args.has("auto"):
					var cs = _stack[-1]
					for i in args.auto.to_int():
						cs._on_end_turn()
						await get_tree().create_timer(2.5).timeout
			"creator", "credits", "shop":
				EventBus.go(parts[0])
			"map":
				EventBus.go("world_map")
			"location":
				EventBus.go("world_map")
				EventBus.go("location", {"location_id": parts[1] if parts.size() > 1 else "whisper_grove"})
			"sortie":
				GameManager.grant_starter_pack()
				var bits: PackedStringArray = (parts[1] if parts.size() > 1 else "whisper_grove:edge").split(":")
				EventBus.go("sortie", {"free": true, "location_id": bits[0], "node_id": bits[1] if bits.size() > 1 else "",
					"seed": bits[2].to_int() if bits.size() > 2 else 7})
				if args.has("look"):
					# Dev: поставить героя у переправы (platforms) или у выхода (exit) для скриншота
					await get_tree().create_timer(0.8).timeout
					var sw = _stack[-1]
					var target := Vector3.ZERO
					if args.look == "platforms" and not sw.data.platforms.is_empty():
						target = sw.data.platforms[0].a
						sw._player.global_position = target + Vector3(-4.5, 0.3, 0)
					elif args.look == "exit" and not sw.data.exits.is_empty():
						target = Vector3(sw.data.exits[-1].cell.x + 0.5, 0, sw.data.exits[-1].cell.y + 0.5)
						var toward_center: Vector3 = (Vector3(sw.data.w * 0.5, 0, sw.data.h * 0.5) - target).normalized()
						sw._player.global_position = target + toward_center * 3.5 + Vector3(0, 0.3, 0)
					var d: Vector3 = target - sw._player.global_position
					sw._player.face_yaw(atan2(d.x, d.z))
				if args.has("walk"):
					var steps: int = args.walk.to_int()
					await get_tree().create_timer(1.0).timeout
					for i in steps:
						Input.action_press("move_forward")
						await get_tree().create_timer(0.1).timeout
					Input.action_release("move_forward")
			"dialogue", "riddle", "safe":
				var key: String = {"dialogue": "npc_id", "riddle": "riddle_id", "safe": "safe_id"}[parts[0]]
				EventBus.go(parts[0], {key: parts[1], "overlay": true})
				if args.has("pick"):
					await get_tree().create_timer(1.5).timeout
					var ds = _stack[-1]
					ds._pick(ds._choices.get_child(args.pick.to_int()).get_meta("entry"))
			"lootbox":
				GameManager.player_data.lootboxes = 3
				EventBus.go("lootbox", {"overlay": true})
				if args.has("open"):
					_stack[-1]._open()
	if args.has("toast"):
		EventBus.notify(args.toast, "success")
	if args.has("levelup"):
		_on_level_up(GameManager.player_data.level)
	if args.has("fps"):
		_log_fps(args.fps.to_float() if args.fps != "" else 8.0)
	if args.has("shot"):
		_take_screenshot(args.shot, args.get("shot-delay", "1.5").to_float())


## Демо-прогресс для скриншотов/отладки. Пишет в user://demo_saves/, реальные сохранения не трогает.
func _fill_demo_progress() -> void:
	SaveSystem.use_dir("user://demo_saves/")
	GameManager.create_hero(Loc.t("Демо"), Appearance.default_look())
	GameManager.player_data.gold = 400
	var count := {"python_developer": 14, "ai_developer": 9, "python_backend": 5, "game_designer": 3}
	for spec_id in count:
		var flat := ContentParser.get_flat_nodes(spec_id)
		for i in mini(count[spec_id], flat.size()):
			GameManager.learn_node(flat[i])
		for i in range(count[spec_id], mini(count[spec_id] + 3, flat.size())):
			GameManager.mark_in_progress(flat[i].id)
	for i in 14:
		GameManager.add_card_to_collection(CardDatabase.roll_card([], 2.5).id)
	EventBus.progress_changed.emit("")


## Dev: замер FPS (после прогрева) и выход.
func _log_fps(seconds: float) -> void:
	await get_tree().create_timer(3.0).timeout
	var frames := Engine.get_frames_drawn()
	var t0 := Time.get_ticks_msec()
	await get_tree().create_timer(seconds).timeout
	var fps := (Engine.get_frames_drawn() - frames) * 1000.0 / (Time.get_ticks_msec() - t0)
	print("FPS_AVG %.1f  draw_calls %d  objects %d  prims %d" % [fps,
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_OBJECTS_IN_FRAME),
		RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME)])
	get_tree().quit()


func _take_screenshot(path: String, delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(path)
	print("Screenshot saved: ", path)
	get_tree().quit()
