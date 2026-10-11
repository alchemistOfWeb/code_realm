extends Node
## Smoke-тест логики и навигации. Не трогает реальные сохранения и профили (user://test_saves/,
## user://test_profiles/) и NOTES_FOR_CLAUDE.md (пишет в user://test_notes.md).
## Запуск: Godot --headless --path <project> res://tools/SmokeTest.tscn
## Код выхода 0 — все проверки прошли.

var _failures := 0
var _checks := 0


func _ready() -> void:
	_run.call_deferred()


## Автоигрок: разыгрывает доступные карты, бьёт оружием и существами.
func _auto_play_turn(cs: CombatState) -> void:
	var guard := 0
	var played := true
	while played and not cs.over and guard < 20:
		guard += 1
		played = false
		for i in cs.player.hand.size():
			if not cs.can_play(i).ok:
				continue
			var tt := CombatState.target_type(cs.player.hand[i])
			var target := {}
			if tt == "enemy_any":
				target = {"side": "enemy", "kind": "hero", "uid": -1}
			elif tt == "enemy_creature" and not cs.enemy.board.is_empty():
				target = {"side": "enemy", "kind": "creature", "uid": cs.enemy.board[0].uid}
			elif tt == "friendly_creature" and not cs.player.board.is_empty():
				target = {"side": "player", "kind": "creature", "uid": cs.player.board[0].uid}
			if cs.play_card(i, target):
				if not cs.pending_discover.is_empty():
					cs.choose_discover(0)
				played = true
				break
	for c in cs.player.board.duplicate():
		if cs.over:
			return
		if cs.can_attack_with(c):
			var targets := cs.valid_attack_targets(cs.enemy)
			cs.creature_attack(c.uid, targets[0])
	var w: String = cs.weapons[0]
	if not cs.over and cs.player.stamina >= cs.weapon_cost(w):
		cs.weapon_attack(w, cs.valid_attack_targets(cs.enemy)[0])


func check(cond: bool, label: String) -> void:
	_checks += 1
	if cond:
		print("  ok   ", label)
	else:
		_failures += 1
		print("  FAIL ", label)


func _run() -> void:
	var gm := GameManager
	var ss := SaveSystem
	var cp := ContentParser
	var bus := EventBus
	var root := get_tree().root
	ss.profiles_file = "user://test_profiles.json"
	ss.profiles_dir = "user://test_profiles/"
	ss.reload_profiles()
	ss.use_dir("user://test_saves/")
	ClaudeNotesExporter.override_path = ProjectSettings.globalize_path("user://test_notes.md")
	Loc.setup("ru")
	gm.reset_all()

	print("== XP и уровни")
	gm.gain_xp(20)
	check(gm.player_data.level == 2 and gm.player_data.xp == 0, "20 XP → уровень 2")
	check(gm.player_data.xp_to_next == 30 and gm.player_data.max_hp == XPCalculator.max_hp_for_level(2) and gm.player_data.attribute_points == 1, "уровень 2: 30 XP до след., HP 21, 1 очко")
	gm.gain_xp(65)
	check(gm.player_data.level == 3 and gm.player_data.xp == 35, "ещё 65 XP → уровень 3, 35 XP")

	print("== Энергия")
	check(gm.spend_energy(30) and gm.player_data.energy == 20, "трата энергии: 50 → 20")
	check(not gm.spend_energy(30), "нельзя потратить больше, чем есть")

	print("== Изучение узлов")
	var flat: Array = cp.get_flat_nodes("python_developer")
	check(flat.size() > 10, "python_developer распарсен (%d узлов)" % flat.size())
	var sub: Dictionary = flat[1]
	var xp_before: int = gm.player_data.total_xp
	var gained: int = gm.learn_node(sub)
	check(gained == sub.xp_reward and gm.player_data.total_xp == xp_before + gained, "изучение даёт xp_reward (%d)" % gained)
	check(gm.player_data.energy == 25, "изучение даёт +5 энергии")
	check(gm.learn_node(sub) == 0, "повторное изучение не даёт XP")
	check(gm.count_learned("python_developer") == 1, "count_learned = 1")
	gm.reset_spec("python_developer")
	check(gm.count_learned("python_developer") == 0, "сброс дерева")
	check(gm.learn_node(sub) == 0 and gm.is_learned(sub.id), "после сброса XP повторно не выдаётся")
	check(cp.get_neighbor_node(sub.id, -1).get("id") == flat[0].id, "навигация: предыдущий узел")

	print("== Атрибуты")
	var str_before: int = gm.player_data.attributes.strength
	check(gm.increase_attribute("strength") and gm.player_data.attributes.strength == str_before + 1, "вложение очка в силу")

	print("== Сохранение / загрузка")
	gm.set_note(sub.id, "Тестовая заметка")
	ss.save_all()
	var level: int = gm.player_data.level
	gm.reset_all()
	ss.load_all()
	check(gm.player_data.level == level, "уровень восстановлен")
	check(typeof(gm.player_data.level) == TYPE_INT and typeof(gm.player_data.attributes.strength) == TYPE_INT, "числа после JSON — int")
	check(gm.is_learned(sub.id) and gm.rewarded_nodes.has(sub.id), "прогресс и rewarded восстановлены")
	check(gm.get_note(sub.id) == "Тестовая заметка", "заметка восстановлена")

	print("== Экспорт заметок")
	var path := ClaudeNotesExporter.export_all()
	var text := FileAccess.get_file_as_string(path)
	check(text.contains("Тестовая заметка") and text.contains(sub.id), "NOTES_FOR_CLAUDE содержит заметку и id")

	print("== Markdown → BBCode")
	var bb := MarkdownBBCode.to_bbcode("## H\n**bold** `x[0]` *it* [link](http://a.b)\n| a | b |\n|---|---|\n| 1 | 2 |\n```python\nx = 1  # c\n```")
	check(bb.contains("[b][color=#FFFFFF]bold") and bb.contains("x[lb]0]") and bb.contains("[url=http://a.b]") and bb.contains("[table=2]"), "конвертация инлайнов, таблиц, ссылок")

	print("== UI-навигация")
	var main: Control = load("res://scenes/main/Main.tscn").instantiate()
	root.add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame
	check(main.current_screen_key() == "main_menu", "стартовый экран — главное меню")
	bus.go("world", {"root": true})
	await get_tree().process_frame
	check(main.current_screen_key() == "world" and main._stack.size() == 1 and main.get_node("HUD").visible, "WorldTree — корень стека, HUD виден")
	bus.go("mini_tree", {"spec_id": "ai_developer"})
	await get_tree().process_frame
	check(main.current_screen_key() == "mini_tree", "открыт MiniTree")
	var lesson_id: String = flat[3].id
	bus.go("lesson", {"node_id": lesson_id})
	await get_tree().process_frame
	var lesson = main._stack[-1]
	check(main.current_screen_key() == "lesson" and lesson.node_data.id == lesson_id, "открыт LessonPage")
	check(gm.get_node_status(lesson_id) == gm.STATUS_IN_PROGRESS, "открытие урока → «в процессе»")
	lesson._on_learn_pressed()
	check(gm.is_learned(lesson_id) and lesson.learn_btn.disabled, "кнопка «Изучено» работает")
	lesson._go_neighbor(1)
	await get_tree().process_frame
	check(main._stack.size() == 3 and main._stack[-1].node_data.id == flat[4].id, "«След.» заменяет урок, стек не растёт")
	bus.back()
	await get_tree().process_frame
	check(main.current_screen_key() == "mini_tree", "назад → MiniTree")
	bus.go("character", {"tab": 1})
	await get_tree().process_frame
	check(main.current_screen_key() == "character", "экран персонажа")
	bus.go("settings")
	await get_tree().process_frame
	check(main.current_screen_key() == "settings", "экран настроек")
	bus.navigate_home.emit()
	await get_tree().process_frame
	check(main._stack.size() == 1, "домой → WorldTree")

	print("== Итерация 2: тесты, награды, карты")
	for sid in cp.get_all_spec_ids():
		var qs: Array = QuizGenerator.for_tree(sid)
		var valid := qs.all(func(q): return q.options.size() >= 2 and q.correct >= 0 and q.correct < q.options.size())
		check(qs.size() >= 8 and valid, "общий тест %s: %d вопросов, все корректны" % [sid, qs.size()])
	var kinds := {}
	for i in 5:
		for q in QuizGenerator.for_tree("python_developer"):
			kinds[q.kind] = true
	check(kinds.has("authored") and kinds.has("fill_gap"), "виды вопросов: %s" % ", ".join(kinds.keys()))
	var main_node: Dictionary = cp.get_specialization("python_backend").nodes[0]
	check(QuizGenerator.for_node(main_node).size() >= 3, "тест узла «%s» сгенерирован" % main_node.title)
	check(QuizGenerator.for_node(cp.get_flat_nodes("ai_developer")[3]).size() >= 2, "тест узла-вопроса AI сгенерирован")
	var missing_icons := CardDatabase.all_cards().filter(func(c): return not ResourceLoader.exists("res://assets/icons/game/%s.svg" % c.get("icon", "")))
	check(CardDatabase.all_cards().size() >= 38 and missing_icons.is_empty(), "каталог %d карт, иконки на месте" % CardDatabase.all_cards().size())
	for sid in cp.get_all_spec_ids():
		check(CardDatabase.cards_for_spec(sid).size() >= 7, "карт специализации %s: %d" % [sid, CardDatabase.cards_for_spec(sid).size()])
	var legendary := 0
	for i in 4000:
		if CardDatabase.roll_rarity(3.0) == "legendary":
			legendary += 1
	check(legendary > 100 and legendary < 320, "шанс legendary при сложности 3 ≈5%% (%d/4000)" % legendary)

	gm.reset_all()
	var fail: Dictionary = gm.complete_tree_test("game_designer", 3, 10)
	check(not fail.passed and gm.count_learned("game_designer") == 0, "тест 3/10 не засчитан")
	var level_before: int = gm.player_data.level
	var win: Dictionary = gm.complete_tree_test("game_designer", 9, 10)
	var expected_cards := XPCalculator.tree_card_count(CardDatabase.avg_tree_difficulty("game_designer"))
	check(win.passed and win.first and win.cards.size() == expected_cards and win.xp == gm.tree_xp_bonus("game_designer"), "первый зачёт: +%d XP, карт %d" % [win.xp, win.cards.size()])
	check(gm.collection_size() == win.cards.size() and gm.player_data.level > level_before, "карты в коллекции, уровень вырос до %d" % gm.player_data.level)
	check(gm.lootbox_count() >= gm.player_data.level - level_before, "за уровни выданы сундуки (%d)" % gm.lootbox_count())
	var required := cp.get_flat_nodes("game_designer").filter(func(n): return not n.is_purple).size()
	check(gm.count_learned("game_designer") == required, "все обязательные темы изучены (%d)" % required)
	var again: Dictionary = gm.complete_tree_test("game_designer", 10, 10)
	check(again.passed and not again.first and again.cards.is_empty() and again.cooldown_left > 0, "повтор сразу — без награды, перезарядка")
	var sub_node: Dictionary = cp.get_flat_nodes("level_designer")[1]
	var nt: Dictionary = gm.complete_node_test(sub_node, 3, 3)
	check(nt.passed and nt.first and nt.learned_now and gm.is_learned(sub_node.id), "тест узла: тема изучена, +%d XP" % nt.xp)
	check(not gm.complete_node_test(sub_node, 3, 3).first, "бонус за тест узла — один раз")
	check(not gm.complete_node_test(sub_node, 1, 3).passed, "1/3 — тест узла не сдан")
	var boxes := gm.lootbox_count()
	var got: Array = gm.open_lootbox()
	check(got.size() == 1 and gm.lootbox_count() == boxes - 1, "сундук открыт: %s" % ", ".join(got))
	ss.save_all()
	gm.reset_all()
	ss.load_all()
	check(gm.test_record("tree:game_designer").get("passes", 0) == 2, "результаты тестов сохраняются")

	print("== UI итерации 2")
	bus.go("mini_tree", {"spec_id": "python_developer"})
	await get_tree().process_frame
	bus.go("test", {"mode": "tree", "spec_id": "python_developer"})
	await get_tree().process_frame
	var ts = main._stack[-1]
	check(main.current_screen_key() == "test" and ts.questions.size() == 10, "экран общего теста")
	for i in ts.questions.size():
		ts._on_answer(ts.questions[ts.index].correct)
		ts._on_next()
		await get_tree().process_frame
	check(not ts.result.is_empty() and ts.result.passed, "тест пройден через UI, результат %d/%d" % [ts.correct_count, ts.questions.size()])
	ts._open_reward()
	await get_tree().process_frame
	var scroll = main._stack[-1]
	check(main.current_screen_key() == "reward" and main._stack[-2].visible, "свиток наград открыт оверлеем")
	scroll._open()
	for i in 10:
		await get_tree().process_frame
	bus.back()
	await get_tree().process_frame
	check(main.current_screen_key() == "mini_tree", "после награды — назад в дерево")
	bus.go("test", {"mode": "node", "node_id": cp.get_flat_nodes("python_developer")[2].id})
	await get_tree().process_frame
	ts = main._stack[-1]
	for i in ts.questions.size():
		ts._on_answer((ts.questions[ts.index].correct + 1) % ts.questions[ts.index].options.size())
		ts._on_next()
		await get_tree().process_frame
	check(not ts.result.passed, "тест узла с неверными ответами не сдан")
	bus.back()
	gm.player_data.lootboxes = 1
	bus.go("lootbox", {"overlay": true})
	await get_tree().process_frame
	main._stack[-1]._open()
	for i in 5:
		await get_tree().process_frame
	check(gm.lootbox_count() == 0, "сундук открыт через UI")
	bus.back()
	bus.go("character", {"tab": 2})
	await get_tree().process_frame
	check(main._stack[-1].cards_grid.get_child_count() > 0, "коллекция карт отображается")
	main._stack[-1]._show_card_detail(gm.card_collection.keys()[0])
	bus.navigate_home.emit()
	await get_tree().process_frame

	print("== Итерация 3: карточный бой и колода")
	gm.reset_all()
	check(gm.grant_starter_pack() and not gm.grant_starter_pack(), "стартовый набор выдаётся один раз")
	check(gm.combat_deck.size() == gm.STARTER_PACK.size() and gm.deck_ready(), "стартовая колода готова (%d карт)" % gm.combat_deck.size())
	check(gm.deck_add_block_reason("sql_query") != "", "нельзя добавить больше копий, чем есть")
	gm.add_card_to_collection("python_zen")
	gm.add_card_to_collection("python_zen")
	check(gm.add_to_deck("python_zen") and not gm.add_to_deck("python_zen"), "легендарная — максимум 1 копия")
	gm.auto_build_deck()
	check(gm.combat_deck.size() >= 10, "автосборка: %d карт" % gm.combat_deck.size())
	var all_ids: Array = CardDatabase.all_cards().map(func(c): return c.id)
	var fights := 0
	var wins := 0
	var max_turns := 0
	for enemy in CardDatabase.all_enemies():
		for rep in 3:
			var cs := CombatState.new()
			var deck: Array = all_ids.duplicate()
			deck.shuffle()
			cs.start(enemy, deck.slice(0, 20), {"max_hp": 30, "hp": 30, "attributes": gm.player_data.attributes, "weapons": ["sword"]})
			var guard := 0
			while not cs.over and guard < 60:
				guard += 1
				_auto_play_turn(cs)
				if not cs.over:
					cs.end_turn()
			cs.take_events()
			fights += 1
			if cs.over and cs.winner == "player":
				wins += 1
			max_turns = maxi(max_turns, cs.turn)
			if not cs.over:
				print("    бой не завершился: ", enemy.id)
	check(fights == CardDatabase.all_enemies().size() * 3, "автобои: %d боёв, побед автоигрока %d, макс. ходов %d" % [fights, wins, max_turns])
	var cs2 := CombatState.new()
	cs2.start(CardDatabase.all_enemies()[0], ["sql_query", "sql_query", "sql_query", "git_commit", "try_except"], {"max_hp": 20, "hp": 20, "attributes": {"strength": 1, "agility": 1, "max_mana": 10, "max_stamina": 10}, "weapons": ["sword"]})
	var hp_before: int = cs2.enemy.hp
	check(cs2.weapon_attack("sword", {"side": "enemy", "kind": "hero", "uid": -1}) and cs2.enemy.hp == hp_before - 4, "меч: 2 + 2×Сила = 4 урона")
	check(cs2.use_rune("shield") and cs2.player.shield == 4 and cs2.player.mana == 7, "руна щита: +4 щита, −3 маны")
	check(not cs2.weapon_attack("axe", {"side": "enemy", "kind": "hero", "uid": -1}), "топора нет в экипировке — атака им недоступна")
	var cs3 := CombatState.new()
	cs3.start(CardDatabase.all_enemies()[0], [], {"max_hp": 20, "hp": 20, "attributes": {"strength": 2, "agility": 1, "max_mana": 10, "max_stamina": 10}, "weapons": ["hammer"], "armor": 3, "damage_bonus": 1})
	check(cs3.player.shield == 3 and cs3.weapon_damage("hammer") == 2 + 2 + 1, "броня = щит в начале боя, урон молота 2 + Сила + бонус оружия")
	check(cs3.player.hand.is_empty() and not cs3.over, "бой с пустой колодой возможен (минимума колоды нет)")
	var res: Dictionary = gm.apply_combat_result(CardDatabase.all_enemies()[0], true, "expedition", 12)
	check(res.xp > 0 and res.gold > 0 and gm.player_data.hp == 12, "награды за бой и HP после боя")

	print("== Итерация 4: мир, диалоги, загадки, сейфы")
	var bad_gen := 0
	var no_gate := 0
	for f in [1, 2, 3]:
		for sd in 10:
			var dg := DungeonGenerator.generate(f, 1000 + sd * 31 + f, {})
			if not DungeonGenerator.all_reachable(dg) or dg.npcs.size() < 2 or dg.enemies.is_empty():
				bad_gen += 1
			if dg.gates.is_empty():
				no_gate += 1
			if f == 3 and dg.boss.get("id", "") != "corrupted_compiler":
				bad_gen += 1
	check(bad_gen == 0 and no_gate == 0, "генератор: 30 этажей связны, есть NPC/враги/решётки/босс")
	gm.reset_all()
	check(not Requirements.knowledge_met({"spec": "python_developer", "topic": "GIL"}), "знание GIL не изучено — реплика заблокирована")
	gm.learn_node(Requirements.find_topic_node("python_developer", "GIL"))
	check(Requirements.knowledge_met({"spec": "python_developer", "topic": "GIL"}), "знание GIL изучено — реплика доступна")
	var chance := Requirements.check_chance({"attr": "strength", "dc": 12})
	check(chance > 0 and chance < 100, "шанс проверки СИЛА СЛ 12: %d%%" % chance)
	var npcs := DialogueRunner.all_npcs()
	check(npcs.size() == 6, "диалогов NPC: %d" % npcs.size())
	var dr := DialogueRunner.new()
	dr.start("warden")
	var gil_choice := dr.visible_choices().filter(func(c): return "GIL" in c.tag)
	check(not gil_choice.is_empty() and gil_choice[0].available and gil_choice[0].tag_kind == "knowledge", "у Стража доступна реплика [ЗНАНИЕ · GIL]")
	dr.choose(gil_choice[0].index)
	check(dr.pending_world.any(func(a): return a.get("world") == "open_gate"), "реплика знания открывает проход")
	var dr2 := DialogueRunner.new()
	dr2.start("rzhavchik")
	var locked := dr2.visible_choices().filter(func(c): return not c.available)
	check(not locked.is_empty() and locked[0].reason != "", "торговец: без золота покупка заблокирована («%s»)" % locked[0].reason)
	var dr3 := DialogueRunner.new()
	dr3.start("greta")
	var check_choice := dr3.visible_choices().filter(func(c): return c.tag_kind == "check")
	var r3: Dictionary = dr3.choose(check_choice[0].index)
	check(not r3.roll.is_empty() and r3.roll.total == r3.roll.roll + r3.roll.attr_bonus + r3.roll.know_bonus, "бросок d20: %d + %d = %d против СЛ %d" % [r3.roll.roll, r3.roll.attr_bonus, r3.roll.total, r3.roll.dc])
	var safe_info: Dictionary = load("res://scenes/dungeon/SafeScreen.gd").get_safe("gear_counter")
	if PythonRunner.available():
		var bad: Dictionary = await PythonRunner.check(self, safe_info.code, safe_info)
		var good: Dictionary = await PythonRunner.check(self, safe_info.solution, safe_info)
		var loop: Dictionary = await PythonRunner.check(self, "def total_teeth(n):
    while True:
        pass
", safe_info)
		check(not bad.ok and good.ok and not loop.ok, "Python-сейф: баг не проходит, исправление проходит, вечный цикл прерван (%s)" % loop.error)
	else:
		print("    Python не найден — проверяется только запасной режим")
	var pat_bad: Dictionary = PythonRunner._pattern_check(safe_info.code, safe_info)
	var pat_good: Dictionary = PythonRunner._pattern_check(safe_info.solution, safe_info)
	check(not pat_bad.ok and pat_good.ok, "запасная проверка сейфа по шаблону")
	print("== Итерация 5: профили, снаряжение, мир")
	var p_before: int = ss.list_profiles().size()
	gm.create_hero("Тест", {"gender": "female", "race": "elf", "skin": 2, "hair": "Hair_Buns", "hair_color": 3})
	var pid: String = ss.create_profile("Тест")
	check(ss.list_profiles().size() == p_before + 1 and ss.get_profile(pid).name == "Тест", "профиль создан")
	check(gm.player_data.attributes.agility == XPCalculator.ATTRIBUTES.agility.start + 1, "расовый бонус эльфа: +1 ловкость")
	check(gm.equipped("weapon") == "sword_rusty" and gm.equipped("chest") == "shirt_linen", "стартовое снаряжение надето")
	gm.player_data.gold = 500
	check(gm.buy_item("shield_round") and gm.player_data.gold == 440 and "shield_round" in gm.player_data.inventory, "покупка щита за 60")
	check(gm.equip("shield_round") and gm.equipped("offhand") == "shield_round", "щит надет")
	check(gm.combat_stats().armor == 2, "броня щита идёт в бой")
	check(gm.buy_item("bow_hunter") and gm.equip("bow_hunter"), "лук куплен и надет вместо меча")
	check(gm.combat_weapons() == ["bow"] and "sword_rusty" in gm.player_data.inventory, "атака в бою — лук, меч вернулся в инвентарь")
	check(gm.buy_item("dagger_simple") and gm.equip("dagger_simple", "offhand") and gm.combat_weapons() == ["bow", "dagger"], "кинжал во второй руке даёт вторую атаку")
	var gold_before: int = gm.player_data.gold
	check(gm.sell_item("shield_round") == 30 and gm.player_data.gold == gold_before + 30, "продажа за половину цены")
	gm.player_data.gold = 0
	check(gm.buy_block_reason("claymore") != "", "без золота купить нельзя")
	var outfit := gm.hero_outfit()
	check(outfit.outfit.body == "peasant" and outfit.weapon == "Bow_Wooden", "вид экипировки для модели героя")
	ss.save_all()
	gm.reset_all()
	check(ss.select_profile(pid) and gm.player_data.name == "Тест" and gm.equipped("weapon") == "bow_hunter", "профиль загружен со снаряжением")
	ss.delete_profile(pid)
	check(ss.get_profile(pid).is_empty() and not ss.has_active_profile(), "профиль удалён")
	ss.use_dir("user://test_saves/")
	gm.reset_all()
	gm.give_starter_kit()

	var locs := WorldData.map_locations()
	var playable := locs.filter(func(l): return WorldData.is_playable(l.id))
	check(locs.size() == 100 and playable.size() == 2, "карта мира: 100 локаций, 2 доступны")
	var wg := WorldData.location("whisper_grove")
	var graph_ok := true
	for id in wg.order:
		for link in wg.nodes[id].links:
			if not id in wg.nodes[link].links:
				graph_ok = false
	check(graph_ok and WorldData.start_node("whisper_grove") == "edge", "граф Шепчущей рощи двусторонний, старт — Опушка")
	check(WorldData.node_status("whisper_grove", "edge") == "open" and WorldData.node_status("whisper_grove", "brook") == "hidden", "в начале открыта только стартовая подлокация")
	WorldData.visit_node("whisper_grove", "edge", 2, 3)
	check(WorldData.node_status("whisper_grove", "brook") == "known", "после посещения соседи видны, но закрыты")
	WorldData.mark_exit("whisper_grove", "edge", "brook")
	check(WorldData.is_open("whisper_grove", "brook") and WorldData.node_status("whisper_grove", "brook") == "open", "найденный проход открывает подлокацию")
	check(WorldData.location_progress("whisper_grove") > 0.0, "процент исследования растёт (%d%%)" % roundi(WorldData.location_progress("whisper_grove") * 100))

	var gen_bad := 0
	for loc_id in ["whisper_grove", "ferrograd_ruins"]:
		var loc := WorldData.location(loc_id)
		for id in loc.order:
			var nd: Dictionary = loc.nodes[id]
			if WorldData.is_underground(nd):
				continue
			var nbs: Array = []
			for l in nd.links:
				nbs.append({"id": l, "name": loc.nodes[l].name, "kind": loc.nodes[l].kind})
			for sd in 3:
				var od := OutdoorGenerator.generate(nd, nbs, 500 + sd, "", {})
				if od.exits.size() != nbs.size() or od.chests.size() != int(nd.features.get("chests", 2)):
					gen_bad += 1
				if nd.features.get("platforms", false) and od.platforms.is_empty():
					gen_bad += 1
				if od.grid[od.start.y * od.w + od.start.x] == OutdoorGenerator.BLOCK:
					gen_bad += 1
	check(gen_bad == 0, "генератор поверхности: выходы, сундуки, платформы и старт корректны")

	print("== Вылазка")
	gm.grant_starter_pack()
	gm.player_data.energy = 50
	bus.go("sortie", {"location_id": "ferrograd_ruins", "node_id": "rusty_galleries", "seed": 4242})
	for i in 4:
		await get_tree().process_frame
	var sw = main._stack[-1]
	check(main.current_screen_key() == "sortie" and sw._world != null and sw._enemies.size() > 0 and not main.get_node("HUD").visible, "вылазка: подземелье построено, врагов %d, HUD скрыт" % sw._enemies.size())
	check(gm.player_data.energy == 50 - XPCalculator.SORTIE_ENERGY_COST, "вылазка стоит %d энергии" % XPCalculator.SORTIE_ENERGY_COST)
	check(sw.data.exits.size() == 2 and WorldData.node_state("ferrograd_ruins", "rusty_galleries").visited, "у подлокации 2 перехода, посещение записано")
	bus.go("dialogue", {"npc_id": sw.data.npcs[0].id, "overlay": true})
	await get_tree().process_frame
	check(main.current_screen_key() == "dialogue" and sw._covered, "диалог открыт поверх мира, мир на паузе")
	main._stack[-1]._finish()
	await get_tree().process_frame
	bus.go("riddle", {"riddle_id": sw.data.riddle_id, "overlay": true})
	await get_tree().process_frame
	check(main.current_screen_key() == "riddle", "экран загадки")
	EventBus.riddle_finished.emit(sw.data.riddle_id, true)
	bus.back()
	await get_tree().process_frame
	check(sw._gates.is_empty(), "загадка решена — решётки подняты")
	if not sw.data.safe.is_empty():
		bus.go("safe", {"safe_id": sw.data.safe.id, "overlay": true})
		await get_tree().process_frame
		check(main.current_screen_key() == "safe", "экран сейфа с редактором кода")
		bus.back()
		await get_tree().process_frame
	var enemy = sw._enemies[0]
	var enemy_index: int = enemy.index
	sw._on_enemy_contact(enemy)
	await get_tree().process_frame
	check(main.current_screen_key() == "combat", "касание врага → карточный бой")
	var cscreen = main._stack[-1]
	cscreen.state.enemy.hp = 0
	cscreen.state._check_over()
	cscreen._check_end()
	EventBus.combat_finished.emit({"won": true, "enemy_id": enemy.enemy_data.id, "context": "expedition", "gold": 5, "hp_left": 10})
	bus.back()
	await get_tree().process_frame
	check(main.current_screen_key() == "sortie" and sw.run.fights == 1 and enemy_index in WorldData.node_state("ferrograd_ruins", "rusty_galleries").kills, "победа: враг повержен и не вернётся")
	# Переход в соседнюю подлокацию
	var exit_it: Dictionary = sw._interactables.filter(func(it): return it.kind == "exit")[0]
	var to_id: String = exit_it.exit.to
	sw._player.global_position = exit_it.pos + Vector3(1.5, 0.2, 0)
	sw._discover_exits()
	check(WorldData.is_open("ferrograd_ruins", to_id), "подход к переходу открывает «%s» на карте" % to_id)
	sw._use_exit(exit_it)
	await get_tree().create_timer(1.0).timeout
	check(sw.node_id == to_id and WorldData.node_state("ferrograd_ruins", to_id).visited, "переход в соседнюю подлокацию без новой траты энергии")
	# Пауза (Space) и меню (Esc)
	sw._toggle_pause()
	check(sw._paused and sw._world.process_mode == Node.PROCESS_MODE_DISABLED and sw._menu == null, "Space — пауза без меню")
	sw._toggle_pause()
	sw._toggle_menu()
	check(sw._menu != null, "Esc — меню вылазки")
	sw._toggle_menu()
	# Падение — гибель, потеря всей энергии
	gm.player_data.energy = 30
	sw._player.global_position = Vector3(5, -30, 5)
	await get_tree().create_timer(1.3).timeout
	check(sw._ended and gm.player_data.energy == 0, "падение в пропасть: гибель, энергия потеряна")
	sw._return_to_camp()
	await get_tree().process_frame
	check(main.current_screen_key() != "sortie", "возврат из вылазки")

	print("== Локализация")
	Loc.setup("en")
	check(Loc.t("Назад") == "Back" and Loc.t("Уровень %d") % 3 == "Level 3", "английский интерфейс")
	check(CardDatabase.get_card("fstring").description == "Deal 2 damage." and CardDatabase.get_card("sql_query").description.begins_with("Deals 3 damage"), "описания карт на английском")
	check(ItemDatabase.get_item("sword_iron").name == "Iron Sword" and WorldData.location_info("whisper_grove").name == "Whispering Grove", "предметы и локации на английском")
	var en: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://locale/en.json"))
	check(en.size() > 900 and en.values().all(func(v): return String(v) != ""), "словарь en.json: %d строк, все переведены" % en.size())
	Loc.setup("ru")
	check(Loc.t("Назад") == "Назад" and TranslationServer.translate("Назад") == "Назад", "русский снова без примеси английского")
	check(CardDatabase.get_card("fstring").description == "Наносит 2 урона.", "описания карт снова на русском")

	print("== Звук и настройки")
	check(AudioServer.get_bus_index("Music") >= 0 and AudioServer.get_bus_index("SFX") >= 0, "шины Music и SFX созданы")
	Audio.play("click")
	Audio.play_jingle("levelup")
	check(Audio.SFX.size() >= 10 and Audio.MUSIC.size() == 3, "звуки и музыка загружены")
	check(not Settings.available_resolutions().is_empty(), "список разрешений не пуст")
	check(Settings.auto_resolution().x >= 960, "авто-разрешение %s" % Settings.auto_resolution())
	for i in 3:
		await get_tree().process_frame

	ss.wipe()
	await get_tree().process_frame   # дождаться отложенных автосохранений
	for f in DirAccess.get_files_at("user://"):
		if f.begins_with("test_profiles"):
			DirAccess.remove_absolute("user://" + f)
	DirAccess.remove_absolute("user://test_profiles")
	for f in DirAccess.get_files_at(ss.save_dir):
		DirAccess.remove_absolute(ss.save_dir + f)
	DirAccess.remove_absolute(ss.save_dir)
	DirAccess.remove_absolute(path)
	print("\n%d/%d checks passed" % [_checks - _failures, _checks])
	get_tree().quit(1 if _failures > 0 else 0)
