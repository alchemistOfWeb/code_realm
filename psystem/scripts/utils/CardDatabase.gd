class_name CardDatabase
extends RefCounted
## Доступ к каталогам data/cards_catalog.json и data/enemies_catalog.json (ленивая загрузка).

const CARDS_FILE := "res://data/cards_catalog.json"
const ENEMIES_FILE := "res://data/enemies_catalog.json"
const RARITY_ORDER := {"legendary": 0, "rare": 1, "uncommon": 2, "common": 3}
const RARITY_NAMES := {"common": "Обычная", "uncommon": "Необычная", "rare": "Редкая", "legendary": "Легендарная"}
const TYPE_NAMES := {"spell": "Заклинание", "creature": "Существо", "artifact": "Артефакт", "rune": "Руна"}

static var _cards: Array = []
static var _cards_by_id: Dictionary = {}
static var _enemies: Array = []
static var _lang := ""


## Смена языка — перечитать каталоги с полями *_en.
static func _check_lang() -> void:
	if _lang != Loc.lang():
		_lang = Loc.lang()
		_cards.clear()
		_cards_by_id.clear()
		_enemies.clear()


static func all_cards() -> Array:
	_check_lang()
	if _cards.is_empty():
		_cards = _load_list(CARDS_FILE, "cards").map(func(c): return Loc.localized(c, ["name", "description", "flavor_text"]))
		for card in _cards:
			_cards_by_id[card.id] = card
	return _cards


static func get_card(card_id: String) -> Dictionary:
	all_cards()
	return _cards_by_id.get(card_id, {})


static func cards_for_spec(spec_id: String) -> Array:
	return all_cards().filter(func(c): return c.get("from_specialization", "") == spec_id)


## Средняя сложность главных узлов дерева (1..3).
static func avg_tree_difficulty(spec_id: String) -> float:
	var nodes: Array = ContentParser.get_specialization(spec_id).get("nodes", [])
	if nodes.is_empty():
		return 1.0
	var total := 0.0
	for n in nodes:
		total += n.get("difficulty", 1)
	return total / nodes.size()


## Бросок редкости: legendary 2%+1%·d, rare 8%+5%·d, uncommon 20%, иначе common.
static func roll_rarity(difficulty: float) -> String:
	var legendary := XPCalculator.LEGENDARY_BASE + difficulty * XPCalculator.LEGENDARY_PER_DIFF
	var rare := XPCalculator.RARE_BASE + difficulty * XPCalculator.RARE_PER_DIFF
	var roll := randf()
	if roll < legendary:
		return "legendary"
	if roll < legendary + rare:
		return "rare"
	if roll < legendary + rare + XPCalculator.UNCOMMON_CHANCE:
		return "uncommon"
	return "common"


static func roll_card(pool: Array, difficulty: float) -> Dictionary:
	if pool.is_empty():
		pool = all_cards()
	if pool.is_empty():
		return {}
	var rarity := roll_rarity(difficulty)
	var filtered := pool.filter(func(c): return c.get("rarity", "common") == rarity)
	if filtered.is_empty():
		filtered = pool
	return filtered.pick_random()


## Карты за общий тест дерева (пул специализации, при пустом — все карты).
static func roll_tree_cards(spec_id: String, count: int = -1) -> Array:
	var difficulty := avg_tree_difficulty(spec_id)
	if count < 0:
		count = XPCalculator.tree_card_count(difficulty)
	var pool := cards_for_spec(spec_id)
	var ids: Array = []
	for i in count:
		var card := roll_card(pool, difficulty)
		if not card.is_empty():
			ids.append(card.id)
	return ids


static func all_enemies() -> Array:
	_check_lang()
	if _enemies.is_empty():
		_enemies = _load_list(ENEMIES_FILE, "enemies").map(func(e): return Loc.localized(e, ["name", "title", "description"]))
	return _enemies


## Сортировка id карт: сначала легендарные, затем по имени.
static func sort_by_rarity(card_ids: Array) -> Array:
	var ids := card_ids.duplicate()
	ids.sort_custom(func(a, b):
		var ca := get_card(a)
		var cb := get_card(b)
		var ra: int = RARITY_ORDER.get(ca.get("rarity", "common"), 9)
		var rb: int = RARITY_ORDER.get(cb.get("rarity", "common"), 9)
		if ra != rb:
			return ra < rb
		return String(ca.get("name", a)) < String(cb.get("name", b)))
	return ids


static func _load_list(path: String, key: String) -> Array:
	if not FileAccess.file_exists(path):
		push_warning("CardDatabase: нет файла " + path)
		return []
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		var list: Array = parsed.get(key, [])
		for item in list:
			_ints(item)
		return list
	return []


## JSON отдаёт числа как float — целые значения возвращаем в int (стоимость, атака, HP...).
static func _ints(d: Dictionary) -> void:
	for k in d:
		if d[k] is float and d[k] == floorf(d[k]):
			d[k] = int(d[k])
		elif d[k] is Dictionary:
			_ints(d[k])
