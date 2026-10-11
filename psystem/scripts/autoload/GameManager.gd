extends Node
## Глобальное состояние игры: персонаж, прогресс знаний, заметки, карты.
## Сохранением занимается SaveSystem; здесь — только данные и правила.

signal xp_gained(amount: int)
signal level_up(new_level: int)
signal energy_changed(current: int, maximum: int)
signal gold_changed(current: int)
signal knowledge_unlocked(node_id: String)
signal knowledge_reset(spec_id: String)
## Любое изменение player_data (для общего обновления HUD).
signal player_changed()
signal deck_changed()
signal world_changed()
signal equipment_changed()

## Стартовый набор «Странника» (выдаётся один раз при первом открытии колоды)
const STARTER_PACK := ["sql_query", "git_commit", "try_except", "list_comprehension", "async_coroutine",
	"blockout", "embedding", "playtest", "leading_lines", "redis_cache"]

const STATUS_LEARNED := "learned"
const STATUS_IN_PROGRESS := "in_progress"

var player_data: Dictionary = default_player_data()
## Коллекция карт: card_id -> количество
var card_collection: Dictionary = {}
## Прогресс знаний: node_id -> "learned" | "in_progress"
var knowledge_progress: Dictionary = {}
## Узлы, за которые XP уже выдан (защита от повторного фарма после сброса): node_id -> true
var rewarded_nodes: Dictionary = {}
## Заметки для Claude: node_id -> текст
var claude_notes: Dictionary = {}
## Колода для боя (список card_id)
var combat_deck: Array = []
## Результаты тестов: "tree:<spec_id>" / "node:<node_id>" -> {attempts, passes, best, total, last_pass}
var test_records: Dictionary = {}
## Мир экспедиций: флаги диалогов, ключевые предметы, квесты, статистика
var world: Dictionary = default_world()


static func default_player_data() -> Dictionary:
	var attributes := {}
	for key in XPCalculator.ATTRIBUTES:
		attributes[key] = XPCalculator.ATTRIBUTES[key].start
	return {
		"level": 1,
		"xp": 0,
		"xp_to_next": XPCalculator.xp_to_next(1),
		"total_xp": 0,
		"hp": XPCalculator.max_hp_for_level(1),
		"max_hp": XPCalculator.max_hp_for_level(1),
		"energy": XPCalculator.START_ENERGY,
		"max_energy": XPCalculator.MAX_ENERGY,
		"attributes": attributes,
		"attribute_points": 0,
		"gold": 0,
		"dungeon_runs": 0,
		"lootboxes": 0,
		"created_at": Time.get_datetime_string_from_system(),
		"name": Loc.t("Странник"),
		"look": Appearance.default_look(),
		"inventory": [],        # id предметов (повторы — несколько экземпляров)
		"equipment": {},        # слот → id предмета
	}


static func default_world() -> Dictionary:
	return {"flags": {}, "items": {}, "quests": {}, "locations": {},
		"stats": {"fights_won": 0, "riddles": 0, "safes": 0, "expeditions": 0, "deepest_floor": 0, "falls": 0}}


## Вызывается SaveSystem после загрузки: миграции и пересчёт производных значений.
func after_load() -> void:
	if player_data.equipment.is_empty() and not world.flags.get("starter_kit", false):
		give_starter_kit()
	recalc_max_hp()


## Новый герой: имя, внешность, расовый бонус, стартовое снаряжение.
func create_hero(hero_name: String, look: Dictionary) -> void:
	reset_all()
	player_data.name = hero_name
	player_data.look = look.duplicate()
	var bonus: Dictionary = Appearance.race(look.get("race", "human")).get("bonus", {})
	for key in bonus:
		if key == "attribute_points":
			player_data.attribute_points += int(bonus[key])
		elif player_data.attributes.has(key):
			player_data.attributes[key] += int(bonus[key])
	give_starter_kit()
	recalc_max_hp()
	player_data.hp = player_data.max_hp


func give_starter_kit() -> void:
	world.flags["starter_kit"] = true
	for slot in ItemDatabase.STARTER:
		player_data.equipment[slot] = ItemDatabase.STARTER[slot]
	equipment_changed.emit()


func reset_all() -> void:
	player_data = default_player_data()
	card_collection = {}
	knowledge_progress = {}
	rewarded_nodes = {}
	claude_notes = {}
	combat_deck = []
	test_records = {}
	world = default_world()
	player_changed.emit()


# ---------------------------------------------------------------- XP / уровни

func gain_xp(amount: int) -> void:
	if amount <= 0:
		return
	player_data.xp += amount
	player_data.total_xp += amount
	xp_gained.emit(amount)
	while player_data.xp >= player_data.xp_to_next:
		player_data.xp -= player_data.xp_to_next
		_level_up()
	player_changed.emit()


func _level_up() -> void:
	player_data.level += 1
	recalc_max_hp()
	player_data.hp = player_data.max_hp
	player_data.xp_to_next = XPCalculator.xp_to_next(player_data.level)
	player_data.attribute_points += 1
	player_data.lootboxes = player_data.get("lootboxes", 0) + XPCalculator.lootboxes_for_level(player_data.level)
	level_up.emit(player_data.level)


func get_xp_to_next_level(level: int) -> int:
	return XPCalculator.xp_to_next(level)


# ---------------------------------------------------------------- Энергия / золото

func gain_energy(amount: int) -> void:
	player_data.energy = mini(player_data.energy + amount, player_data.max_energy)
	energy_changed.emit(player_data.energy, player_data.max_energy)
	player_changed.emit()


func spend_energy(amount: int) -> bool:
	if player_data.energy < amount:
		return false
	player_data.energy -= amount
	energy_changed.emit(player_data.energy, player_data.max_energy)
	player_changed.emit()
	return true


func add_gold(amount: int) -> void:
	player_data.gold = maxi(0, player_data.gold + amount)
	gold_changed.emit(player_data.gold)
	player_changed.emit()


# ---------------------------------------------------------------- Атрибуты

func increase_attribute(attr_name: String) -> bool:
	if player_data.attribute_points <= 0 or not player_data.attributes.has(attr_name):
		return false
	player_data.attribute_points -= 1
	player_data.attributes[attr_name] += XPCalculator.ATTRIBUTES[attr_name].per_point
	player_changed.emit()
	return true


# ---------------------------------------------------------------- Знания

func get_node_status(node_id: String) -> String:
	return knowledge_progress.get(node_id, "")


func is_learned(node_id: String) -> bool:
	return knowledge_progress.get(node_id, "") == STATUS_LEARNED


## Отмечает узел «в процессе» (при открытии урока), если он ещё не изучен.
func mark_in_progress(node_id: String) -> void:
	if not knowledge_progress.has(node_id):
		knowledge_progress[node_id] = STATUS_IN_PROGRESS


## Изучить узел. Возвращает полученный XP (0 — если уже изучен или XP за него уже выдавался).
func learn_node(node: Dictionary) -> int:
	var node_id: String = node.get("id", "")
	if node_id == "" or is_learned(node_id):
		return 0
	knowledge_progress[node_id] = STATUS_LEARNED
	var xp := 0
	if not rewarded_nodes.has(node_id):
		rewarded_nodes[node_id] = true
		xp = int(node.get("xp_reward", 5))
		gain_xp(xp)
		gain_energy(XPCalculator.LEARN_ENERGY_REWARD)
	knowledge_unlocked.emit(node_id)
	EventBus.progress_changed.emit(node.get("spec_id", ""))
	return xp


## Снять отметку «изучено» с одного узла (XP не отнимается).
func unlearn_node(node_id: String) -> void:
	knowledge_progress[node_id] = STATUS_IN_PROGRESS
	EventBus.progress_changed.emit(ContentParser.get_node_data(node_id).get("spec_id", ""))


## Сбросить прогресс специализации. XP повторно за эти узлы не выдаётся.
func reset_spec(spec_id: String) -> void:
	for node in ContentParser.get_flat_nodes(spec_id):
		knowledge_progress.erase(node.id)
	knowledge_reset.emit(spec_id)
	EventBus.progress_changed.emit(spec_id)


func count_learned(spec_id: String) -> int:
	var n := 0
	for node in ContentParser.get_flat_nodes(spec_id):
		if is_learned(node.id):
			n += 1
	return n


func total_learned() -> int:
	var n := 0
	for spec_id in ContentParser.get_all_spec_ids():
		n += count_learned(spec_id)
	return n


## Сколько подузлов главного узла изучено: [изучено, всего]
func subnode_progress(node: Dictionary) -> Array:
	var learned := 0
	var subs: Array = node.get("subnodes", [])
	for sub in subs:
		if is_learned(sub.id):
			learned += 1
	return [learned, subs.size()]


# ---------------------------------------------------------------- Заметки для Claude

func get_note(node_id: String) -> String:
	return claude_notes.get(node_id, "")


func set_note(node_id: String, text: String) -> void:
	if text.strip_edges() == "":
		claude_notes.erase(node_id)
	else:
		claude_notes[node_id] = text


# ---------------------------------------------------------------- Тесты

func test_record(key: String) -> Dictionary:
	return test_records.get(key, {})


func _record_test(key: String, correct: int, total: int, passed: bool) -> Dictionary:
	var before: Dictionary = test_records.get(key, {}).duplicate()
	var rec: Dictionary = test_records.get(key, {"attempts": 0, "passes": 0, "best": 0, "total": total, "last_pass": 0})
	rec.attempts += 1
	rec.best = maxi(rec.best, correct)
	rec.total = total
	if passed:
		rec.passes += 1
		rec.last_pass = int(Time.get_unix_time_from_system())
	test_records[key] = rec
	return before


## Секунд до следующей награды за повтор общего теста (0 — награда доступна).
func tree_test_cooldown_left(spec_id: String) -> int:
	var rec := test_record("tree:" + spec_id)
	if rec.get("passes", 0) == 0:
		return 0
	var ready_at: int = rec.get("last_pass", 0) + XPCalculator.TREE_RETEST_COOLDOWN_HOURS * 3600
	return maxi(0, ready_at - int(Time.get_unix_time_from_system()))


## XP-бонус за дерево = сумма xp_reward главных узлов.
func tree_xp_bonus(spec_id: String) -> int:
	var total := 0
	for node in ContentParser.get_specialization(spec_id).get("nodes", []):
		total += int(node.get("xp_reward", 10))
	return total


## Итог общего теста дерева. Награды применяются сразу (не теряются при выходе).
## Возвращает {passed, first, correct, total, xp, energy, cards, nodes_marked, cooldown_left, spec_id}
func complete_tree_test(spec_id: String, correct: int, total: int) -> Dictionary:
	var passed := total > 0 and correct >= QuizGenerator.pass_threshold(total, XPCalculator.TREE_TEST_PASS_RATIO)
	var cooldown_before := tree_test_cooldown_left(spec_id)
	var before := _record_test("tree:" + spec_id, correct, total, passed)
	var result := {"passed": passed, "first": false, "correct": correct, "total": total,
		"xp": 0, "energy": 0, "cards": [], "nodes_marked": 0, "cooldown_left": 0, "spec_id": spec_id}
	if not passed:
		player_changed.emit()
		return result
	# Все обязательные узлы — изучены (XP за них отдельно не выдаётся: награда — бонус дерева)
	for node in ContentParser.get_flat_nodes(spec_id):
		if not node.get("is_purple", false) and not is_learned(node.id):
			knowledge_progress[node.id] = STATUS_LEARNED
			rewarded_nodes[node.id] = true
			result.nodes_marked += 1
	result.first = before.get("passes", 0) == 0
	if result.first:
		result.xp = tree_xp_bonus(spec_id)
		result.energy = XPCalculator.TREE_TEST_ENERGY_REWARD
		result.cards = CardDatabase.roll_tree_cards(spec_id)
	elif cooldown_before == 0:
		result.xp = roundi(tree_xp_bonus(spec_id) * XPCalculator.TREE_RETEST_XP_RATIO)
		result.energy = XPCalculator.TREE_RETEST_ENERGY
		result.cards = CardDatabase.roll_tree_cards(spec_id, 1)
	else:
		result.cooldown_left = cooldown_before
	for card_id in result.cards:
		add_card_to_collection(card_id)
	if result.energy > 0:
		gain_energy(result.energy)
	if result.xp > 0:
		gain_xp(result.xp)
	knowledge_unlocked.emit("")
	EventBus.progress_changed.emit(spec_id)
	player_changed.emit()
	return result


## Итог теста узла: при зачёте узел изучается (+XP узла) и один раз даётся бонус.
## Возвращает {passed, first, correct, total, xp, learned_now}
func complete_node_test(node: Dictionary, correct: int, total: int) -> Dictionary:
	var passed := total > 0 and correct >= QuizGenerator.pass_threshold(total, XPCalculator.NODE_TEST_PASS_RATIO)
	var before := _record_test("node:" + node.id, correct, total, passed)
	var result := {"passed": passed, "first": false, "correct": correct, "total": total, "xp": 0, "learned_now": false}
	if not passed:
		player_changed.emit()
		return result
	if not is_learned(node.id):
		result.learned_now = true
		result.xp += learn_node(node)
	result.first = before.get("passes", 0) == 0
	if result.first:
		var bonus := XPCalculator.node_test_bonus(node.get("difficulty", 1))
		result.xp += bonus
		gain_xp(bonus)
	player_changed.emit()
	return result


# ---------------------------------------------------------------- Сундуки

func lootbox_count() -> int:
	return player_data.get("lootboxes", 0)


## Открыть сундук: 1 карта из всего каталога, шансы редкости растут с уровнем.
func open_lootbox() -> Array:
	if lootbox_count() <= 0:
		return []
	player_data.lootboxes -= 1
	var difficulty := clampf(1.0 + player_data.level / 10.0, 1.0, 3.0)
	var card := CardDatabase.roll_card(CardDatabase.all_cards(), difficulty)
	var ids: Array = []
	if not card.is_empty():
		add_card_to_collection(card.id)
		ids.append(card.id)
	player_changed.emit()
	return ids


# ---------------------------------------------------------------- Колода

func deck_count(card_id: String) -> int:
	return combat_deck.count(card_id)


## Можно ли добавить карту в колоду. "" — можно, иначе причина.
func deck_add_block_reason(card_id: String) -> String:
	if combat_deck.size() >= XPCalculator.MAX_DECK_SIZE:
		return Loc.t("В колоде максимум %d карт") % XPCalculator.MAX_DECK_SIZE
	var owned := int(card_collection.get(card_id, 0))
	var in_deck := deck_count(card_id)
	if in_deck >= owned:
		return Loc.t("Все копии уже в колоде")
	var limit := XPCalculator.MAX_LEGENDARY_COPIES if CardDatabase.get_card(card_id).get("rarity") == "legendary" else XPCalculator.MAX_COPIES
	if in_deck >= limit:
		return Loc.t("Не больше %d копий") % limit
	return ""


func add_to_deck(card_id: String) -> bool:
	if deck_add_block_reason(card_id) != "":
		return false
	combat_deck.append(card_id)
	deck_changed.emit()
	player_changed.emit()
	return true


func remove_from_deck(card_id: String) -> bool:
	var i := combat_deck.find(card_id)
	if i < 0:
		return false
	combat_deck.remove_at(i)
	deck_changed.emit()
	player_changed.emit()
	return true


func clear_deck() -> void:
	combat_deck.clear()
	deck_changed.emit()
	player_changed.emit()


## Автосборка: сначала редкие и дешёвые карты, кривая стоимости, до MAX_DECK_SIZE.
func auto_build_deck() -> void:
	combat_deck.clear()
	var ids := CardDatabase.sort_by_rarity(card_collection.keys())
	var progress := true
	while progress and combat_deck.size() < XPCalculator.MAX_DECK_SIZE:
		progress = false
		for id in ids:
			if combat_deck.size() >= XPCalculator.MAX_DECK_SIZE:
				break
			if deck_add_block_reason(id) == "" and CardDatabase.get_card(id).get("crystal_cost", 0) <= 6:
				combat_deck.append(id)
				progress = true
	for id in ids:
		while deck_add_block_reason(id) == "":
			combat_deck.append(id)
	deck_changed.emit()
	player_changed.emit()


## Ограничения на минимальный размер колоды нет: в вылазку можно идти с любой колодой.
func deck_ready() -> bool:
	return combat_deck.size() >= XPCalculator.MIN_DECK_SIZE


## Стартовый набор: один раз. Возвращает true, если выдан сейчас.
func grant_starter_pack() -> bool:
	if world.flags.get("starter_pack", false):
		return false
	world.flags["starter_pack"] = true
	for id in STARTER_PACK:
		add_card_to_collection(id)
	if combat_deck.is_empty():
		combat_deck = STARTER_PACK.duplicate()
	deck_changed.emit()
	player_changed.emit()
	return true


# ---------------------------------------------------------------- Бой

## Награды за бой. context: "training" | "expedition".
## Возвращает {won, xp, gold, energy, cards}
func apply_combat_result(enemy: Dictionary, won: bool, context: String, hp_left: int) -> Dictionary:
	var result := {"won": won, "xp": 0, "gold": 0, "energy": 0, "cards": []}
	if context != "training":
		player_data.hp = clampi(hp_left, 0, player_data.max_hp)
	if not won or context == "training":
		player_changed.emit()
		return result
	world.stats.fights_won = world.stats.get("fights_won", 0) + 1
	result.xp = int(enemy.get("xp_reward", 10))
	result.gold = int(enemy.get("gold_reward", 5))
	result.energy = XPCalculator.COMBAT_WIN_ENERGY
	if enemy.get("is_boss", false) or enemy.get("is_miniboss", false) or randf() < 0.15:
		var card := CardDatabase.roll_card(CardDatabase.all_cards(), 2.5 if enemy.get("is_boss", false) else 1.5)
		if not card.is_empty():
			result.cards.append(card.id)
			add_card_to_collection(card.id)
	add_gold(result.gold)
	gain_energy(result.energy)
	gain_xp(result.xp)
	player_changed.emit()
	return result


func heal_player(amount: int) -> int:
	var before: int = player_data.hp
	player_data.hp = mini(player_data.max_hp, player_data.hp + amount)
	player_changed.emit()
	return player_data.hp - before


func damage_player(amount: int) -> void:
	player_data.hp = maxi(0, player_data.hp - amount)
	player_changed.emit()


# ---------------------------------------------------------------- Мир: флаги, предметы, квесты

func has_flag(flag: String) -> bool:
	return world.flags.get(flag, false)


func set_flag(flag: String, value: bool = true) -> void:
	world.flags[flag] = value
	world_changed.emit()


func item_count(item_id: String) -> int:
	return int(world.items.get(item_id, 0))


func add_item(item_id: String, n: int = 1) -> void:
	world.items[item_id] = item_count(item_id) + n
	world_changed.emit()


func take_item(item_id: String, n: int = 1) -> bool:
	if item_count(item_id) < n:
		return false
	world.items[item_id] = item_count(item_id) - n
	if world.items[item_id] <= 0:
		world.items.erase(item_id)
	world_changed.emit()
	return true


## Квест: {title, desc, state: "active"|"done"}
func set_quest(quest_id: String, title: String, desc: String) -> void:
	world.quests[quest_id] = {"title": title, "desc": desc, "state": "active"}
	world_changed.emit()


func complete_quest(quest_id: String) -> void:
	if world.quests.has(quest_id):
		world.quests[quest_id].state = "done"
		world_changed.emit()


func active_quests() -> Array:
	var result: Array = []
	for id in world.quests:
		if world.quests[id].get("state") == "active":
			result.append(world.quests[id])
	return result


func add_stat(key: String, n: int = 1) -> void:
	world.stats[key] = world.stats.get(key, 0) + n


# ---------------------------------------------------------------- Снаряжение и инвентарь

func equipped(slot: String) -> String:
	return String(player_data.equipment.get(slot, ""))


func owns_item(item_id: String) -> bool:
	return item_id in player_data.inventory or item_id in player_data.equipment.values()


## Причина, по которой нельзя купить ("" — можно).
func buy_block_reason(item_id: String) -> String:
	var item := ItemDatabase.get_item(item_id)
	if item.is_empty() or item.get("price", 0) <= 0:
		return Loc.t("Не продаётся")
	if player_data.gold < item.price:
		return Loc.t("Не хватает золота")
	return ""


func buy_item(item_id: String) -> bool:
	if buy_block_reason(item_id) != "":
		return false
	add_gold(-int(ItemDatabase.get_item(item_id).price))
	player_data.inventory.append(item_id)
	equipment_changed.emit()
	player_changed.emit()
	return true


## Продать предмет из инвентаря (не надетый). Возвращает полученное золото.
func sell_item(item_id: String) -> int:
	var i: int = player_data.inventory.find(item_id)
	if i < 0:
		return 0
	player_data.inventory.remove_at(i)
	var gold := ItemDatabase.sell_price(ItemDatabase.get_item(item_id))
	add_gold(gold)
	equipment_changed.emit()
	return gold


## Надеть предмет из инвентаря (slot "" — родной слот предмета). Старый предмет возвращается в инвентарь.
func equip(item_id: String, slot: String = "") -> bool:
	var item := ItemDatabase.get_item(item_id)
	if item.is_empty():
		return false
	if slot == "":
		slot = item.slot
	if not ItemDatabase.fits(item, slot):
		return false
	var i: int = player_data.inventory.find(item_id)
	if i < 0:
		return false
	player_data.inventory.remove_at(i)
	var old := equipped(slot)
	if old != "":
		player_data.inventory.append(old)
	player_data.equipment[slot] = item_id
	_after_equipment_change()
	return true


func unequip(slot: String) -> void:
	var old := equipped(slot)
	if old == "":
		return
	player_data.equipment.erase(slot)
	player_data.inventory.append(old)
	_after_equipment_change()


func _after_equipment_change() -> void:
	var before: int = player_data.max_hp
	recalc_max_hp()
	if player_data.max_hp > before:
		player_data.hp += player_data.max_hp - before
	player_data.hp = clampi(player_data.hp, 1, player_data.max_hp)
	equipment_changed.emit()
	player_changed.emit()


## Сумма характеристик надетых предметов.
func equipment_stats() -> Dictionary:
	var total := {}
	for slot in player_data.equipment:
		var item := ItemDatabase.get_item(player_data.equipment[slot])
		var stats: Dictionary = item.get("stats", {})
		for key in stats:
			total[key] = int(total.get(key, 0)) + int(stats[key])
	return total


## Атрибуты с учётом снаряжения.
func effective_attributes() -> Dictionary:
	var attrs: Dictionary = player_data.attributes.duplicate()
	var eq := equipment_stats()
	for key in attrs:
		attrs[key] = maxi(0, int(attrs[key]) + int(eq.get(key, 0)))
	return attrs


func recalc_max_hp() -> void:
	player_data.max_hp = XPCalculator.max_hp_for_level(player_data.level) + int(equipment_stats().get("hp", 0))
	player_data.hp = clampi(int(player_data.get("hp", player_data.max_hp)), 0, player_data.max_hp)


## Атаки оружием в бою по экипировке (без оружия — кулаки).
func combat_weapons() -> Array:
	var list: Array = []
	for slot in ["weapon", "offhand"]:
		var item := ItemDatabase.get_item(equipped(slot))
		var wt: String = item.get("weapon_type", "")
		if wt != "" and not wt in list:
			list.append(wt)
	if list.is_empty():
		list.append("fists")
	return list


## Параметры героя для CombatState.start().
func combat_stats() -> Dictionary:
	var eq := equipment_stats()
	return {"max_hp": player_data.max_hp, "hp": player_data.hp, "attributes": effective_attributes(),
		"weapons": combat_weapons(), "damage_bonus": int(eq.get("damage", 0)), "armor": int(eq.get("armor", 0)),
		"dodge_bonus": int(eq.get("dodge", 0))}


## Как экипировка выглядит на модели героя (для HeroRig.apply_equipment).
func hero_outfit() -> Dictionary:
	var outfit := HeroRig.DEFAULT_OUTFIT.duplicate()
	var variants := {}
	for slot in ["chest", "hands", "legs", "feet", "head", "shoulders"]:
		var item := ItemDatabase.get_item(equipped(slot))
		var visual: Dictionary = item.get("visual", {})
		for part in visual:
			outfit[part] = visual[part]
			var set_name: String = visual[part]
			if slot == "chest" or not variants.has(set_name):
				variants[set_name] = int(item.get("variant", 0))
	if equipped("head") == "":
		outfit.head = ""
	if equipped("shoulders") == "":
		outfit.shoulders = ""
	var weapon := ItemDatabase.get_item(equipped("weapon"))
	var offhand := ItemDatabase.get_item(equipped("offhand"))
	return {"outfit": outfit, "variants": variants, "weapon": weapon.get("model", ""), "offhand": offhand.get("model", "")}


# ---------------------------------------------------------------- Карты

func add_card_to_collection(card_id: String) -> void:
	card_collection[card_id] = card_collection.get(card_id, 0) + 1


func collection_size() -> int:
	var n := 0
	for card_id in card_collection:
		n += int(card_collection[card_id])
	return n
