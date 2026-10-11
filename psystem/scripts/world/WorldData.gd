class_name WorldData
extends RefCounted
## Данные мира: глобальная карта (data/world_map.json, 100 локаций) и графы реализованных локаций
## (data/locations.json). Прогресс исследования хранится в GameManager.world.locations.
##
## Состояния подлокации: hidden (не видна) → known (соседняя исследована, проход не найден) →
## open (найден проход — можно отправиться сразу сюда) → visited → cleared (исследована полностью).

const MAP_PATH := "res://data/world_map.json"
const LOC_PATH := "res://data/locations.json"

const BIOMES := {
	"forest": {"name": "Лес", "icon": "forest", "color": "#4F9A36", "desc": "Густые чащи, звериные тропы и древние деревья."},
	"meadow": {"name": "Луга", "icon": "windmill", "color": "#8CC152", "desc": "Холмистые луга, хутора и мельницы."},
	"ruins": {"name": "Руины", "icon": "ancient-ruins", "color": "#B8A27A", "desc": "Остатки городов эпохи Великого Механизма."},
	"swamp": {"name": "Болота", "icon": "swamp", "color": "#5F7A3E", "desc": "Топи, туман и огоньки, уводящие с тропы."},
	"mountains": {"name": "Горы", "icon": "mountains", "color": "#9A8E7E", "desc": "Перевалы, шахты и гномьи кузницы."},
	"snow": {"name": "Северные льды", "icon": "snowflake-1", "color": "#DCEBF5", "desc": "Вечная зима, ледники и курганы."},
	"desert": {"name": "Пустыня", "icon": "desert", "color": "#E3C27A", "desc": "Барханы, оазисы и гробницы фараонов."},
	"coast": {"name": "Побережье", "icon": "lighthouse", "color": "#6FB7C9", "desc": "Бухты, маяки и затонувшие корабли."},
	"volcano": {"name": "Вулканы", "icon": "volcano", "color": "#C2502F", "desc": "Лава, пепел и драконьи логова."},
	"dark": {"name": "Проклятые земли", "icon": "evil-tower", "color": "#6B4C8A", "desc": "Земли нежити, теней и безумных магов."},
	"caves": {"name": "Пещеры", "icon": "cave-entrance", "color": "#7A6A8E", "desc": "Подземные озёра, кристаллы и гоблинские норы."},
}
## Типы подлокаций: иконка, название, подземная ли.
const NODE_KINDS := {
	"meadow": {"name": "Поляна", "icon": "grass", "underground": false},
	"forest": {"name": "Лес", "icon": "pine-tree", "underground": false},
	"riverside": {"name": "Берег реки", "icon": "waterfall", "underground": false},
	"ruins": {"name": "Руины", "icon": "ancient-ruins", "underground": false},
	"cave": {"name": "Пещера", "icon": "cave-entrance", "underground": true},
	"tomb": {"name": "Гробница", "icon": "crypt-entrance", "underground": true},
	"dungeon": {"name": "Подземелье", "icon": "dungeon-gate", "underground": true},
}

static var _map: Dictionary = {}
static var _locs: Dictionary = {}
static var _lang := ""


static func _ensure() -> void:
	if not _map.is_empty() and _lang == Loc.lang():
		return
	_lang = Loc.lang()
	_map = JSON.parse_string(FileAccess.get_file_as_string(MAP_PATH))
	var by_id := {}
	for l in _map.locations:
		var loc: Dictionary = Loc.localized(l, ["name"])
		by_id[loc.id] = loc
	_map["by_id"] = by_id
	_map.camp = Loc.localized(_map.camp, ["name"])
	var raw: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(LOC_PATH)).locations
	_locs = {}
	for id in raw:
		var loc: Dictionary = Loc.localized(raw[id], ["desc"])
		var nodes := {}
		var order: Array = []
		for n in raw[id].nodes:
			var node: Dictionary = Loc.localized(n, ["name", "desc"])
			nodes[node.id] = node
			order.append(node.id)
		loc.nodes = nodes
		loc.order = order
		loc.id = id
		_locs[id] = loc


# ---------------------------------------------------------------- Глобальная карта

static func map_locations() -> Array:
	_ensure()
	return _map.locations.map(func(l): return _map.by_id[l.id])


static func roads() -> Array:
	_ensure()
	return _map.roads


static func camp() -> Dictionary:
	_ensure()
	return _map.camp


static func location_info(loc_id: String) -> Dictionary:
	_ensure()
	return _map.by_id.get(loc_id, {})


static func is_playable(loc_id: String) -> bool:
	_ensure()
	return _locs.has(loc_id)


static func biome(biome_id: String) -> Dictionary:
	return BIOMES.get(biome_id, BIOMES.forest)


# ---------------------------------------------------------------- Граф локации

static func location(loc_id: String) -> Dictionary:
	_ensure()
	return _locs.get(loc_id, {})


static func node(loc_id: String, node_id: String) -> Dictionary:
	return location(loc_id).get("nodes", {}).get(node_id, {})


static func start_node(loc_id: String) -> String:
	var loc := location(loc_id)
	for id in loc.get("order", []):
		if loc.nodes[id].get("start", false):
			return id
	return loc.get("order", [""])[0]


static func is_underground(node_data: Dictionary) -> bool:
	return NODE_KINDS.get(node_data.get("kind", ""), {}).get("underground", false)


# ---------------------------------------------------------------- Прогресс

static func loc_state(loc_id: String) -> Dictionary:
	var all: Dictionary = GameManager.world.get("locations", {})
	if not GameManager.world.has("locations"):
		GameManager.world["locations"] = all
	if not all.has(loc_id):
		all[loc_id] = {"nodes": {}}
	return all[loc_id]


static func node_state(loc_id: String, node_id: String) -> Dictionary:
	var nodes: Dictionary = loc_state(loc_id).nodes
	if not nodes.has(node_id):
		nodes[node_id] = {"visited": false, "exits": [], "chests": [], "kills": [], "total_chests": 0, "total_enemies": 0, "boss": false}
	return nodes[node_id]


## Открыт ли проход в подлокацию (можно начать вылазку прямо с неё).
static func is_open(loc_id: String, node_id: String) -> bool:
	if node_id == start_node(loc_id):
		return true
	for other in node(loc_id, node_id).get("links", []):
		if node_id in node_state(loc_id, other).get("exits", []):
			return true
	return false


static func node_status(loc_id: String, node_id: String) -> String:
	var st := node_state(loc_id, node_id)
	if st.visited:
		return "cleared" if node_progress(loc_id, node_id) >= 0.999 else "visited"
	if is_open(loc_id, node_id):
		return "open"
	for other in node(loc_id, node_id).get("links", []):
		if node_state(loc_id, other).visited:
			return "known"
	return "hidden"


## Доля исследования подлокации: посещение, найденные проходы, сундуки, побеждённые враги.
static func node_progress(loc_id: String, node_id: String) -> float:
	var st := node_state(loc_id, node_id)
	if not st.visited:
		return 0.0
	var links: Array = node(loc_id, node_id).get("links", [])
	var exits: float = float(st.exits.size()) / maxf(links.size(), 1)
	var chests: float = float(st.chests.size()) / st.total_chests if st.total_chests > 0 else 1.0
	var kills: float = float(st.kills.size()) / st.total_enemies if st.total_enemies > 0 else 1.0
	return clampf(0.3 + exits * 0.3 + chests * 0.2 + kills * 0.2, 0.0, 1.0)


static func location_progress(loc_id: String) -> float:
	var loc := location(loc_id)
	if loc.is_empty():
		return 0.0
	var total := 0.0
	for id in loc.order:
		total += node_progress(loc_id, id)
	return total / maxf(loc.order.size(), 1)


static func visit_node(loc_id: String, node_id: String, total_chests: int, total_enemies: int) -> void:
	var st := node_state(loc_id, node_id)
	st.visited = true
	st.total_chests = total_chests
	st.total_enemies = total_enemies
	GameManager.world_changed.emit()


static func mark_exit(loc_id: String, node_id: String, to_id: String) -> bool:
	var st := node_state(loc_id, node_id)
	if to_id in st.exits:
		return false
	st.exits.append(to_id)
	GameManager.world_changed.emit()
	return true


static func mark_chest(loc_id: String, node_id: String, index: int) -> void:
	var st := node_state(loc_id, node_id)
	if not index in st.chests:
		st.chests.append(index)
		GameManager.world_changed.emit()


static func mark_kill(loc_id: String, node_id: String, index: int) -> void:
	var st := node_state(loc_id, node_id)
	if not index in st.kills:
		st.kills.append(index)
		GameManager.world_changed.emit()


## Детерминированный seed уровня подлокации (раскладка не меняется между вылазками).
static func node_seed(loc_id: String, node_id: String) -> int:
	return absi(hash(loc_id + "/" + node_id)) % 1000000
