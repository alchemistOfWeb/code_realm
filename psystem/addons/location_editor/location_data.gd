@tool
class_name LocationDataFile
extends RefCounted
## Запись данных локаций из редактора: data/locations.json (граф районов и их особенности) и
## data/world_map.json (статус локации на карте мира). Новая локация создаётся по шаблону.

const LOC_PATH := "res://data/locations.json"
const MAP_PATH := "res://data/world_map.json"


static func read(path: String) -> Dictionary:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}


## JSON без пересортировки ключей; целые числа без «.0» (парсер Godot читает их как float).
static func to_text(data: Variant, indent: String = "\t") -> String:
	var text := JSON.stringify(data, indent, false)
	var re := RegEx.create_from_string("(?<=[\\[\\s:,])(-?\\d+)\\.0(?=[,\\]\\s}])")
	return re.sub(text, "$1", true)


static func write(path: String, data: Dictionary) -> bool:
	var text := to_text(data)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(text + "\n")
	f.close()
	WorldData.reload()
	return true


## Обновить поля района (name, kind, links, features…). Возвращает true, если что-то изменилось.
static func update_node(loc_id: String, node_id: String, fields: Dictionary) -> bool:
	var raw := read(LOC_PATH)
	var loc: Dictionary = raw.get("locations", {}).get(loc_id, {})
	for n in loc.get("nodes", []):
		if n.id != node_id:
			continue
		var before := to_text(n, " ")
		for k in fields:
			if k == "features":
				var f: Dictionary = n.get("features", {})
				for fk in fields.features:
					var v = fields.features[fk]
					if v == null or (v is bool and not v) or (v is String and v == "") or (v is Array and v.is_empty() and fk != "pool"):
						f.erase(fk)
					else:
						f[fk] = v
				n["features"] = f
			else:
				n[k] = fields[k]
		if to_text(n, " ") == before:
			return false
		return write(LOC_PATH, raw)
	return false


## Локации карты мира, которые ещё «в разработке» (их можно создать по шаблону).
static func wip_locations() -> Array:
	var out: Array = []
	for l in read(MAP_PATH).get("locations", []):
		if l.get("status", "") != "open":
			out.append(l)
	return out


## Новая локация по шаблону: 4 района (ворота, чаща с островом, руины с сейфом, сердце с боссом) и пещера.
## Враги и босс — из реализованной локации ближайшего уровня. Возвращает "" или текст ошибки.
static func create_from_template(loc_id: String) -> String:
	var map := read(MAP_PATH)
	var entry: Dictionary = {}
	for l in map.get("locations", []):
		if l.id == loc_id:
			entry = l
	if entry.is_empty():
		return "Локации %s нет на карте мира" % loc_id
	var raw := read(LOC_PATH)
	if raw.locations.has(loc_id):
		return "Локация %s уже создана" % loc_id
	var level := int(entry.get("level", 1))
	# Источник врагов — реализованная локация ближайшего уровня
	var src_id := ""
	var best := 999
	for l in map.locations:
		if raw.locations.has(l.id) and absi(int(l.get("level", 1)) - level) < best:
			best = absi(int(l.get("level", 1)) - level)
			src_id = l.id
	var surface_pools: Array = []
	var cave_pool: Array = ["memory_leak", "segfault"]
	var boss := ""
	for n in raw.locations[src_id].nodes:
		var f: Dictionary = n.get("features", {})
		if f.has("boss") and boss == "":
			boss = f.boss
		if n.kind in ["cave", "tomb", "dungeon"]:
			cave_pool = f.get("pool", cave_pool)
		elif f.has("pool"):
			surface_pools.append(f.pool)
	if surface_pools.is_empty():
		surface_pools = [["syntax_error"]]
	var biome: String = entry.get("biome", "forest")
	var wild: String = "forest" if biome in ["forest", "swamp", "dark"] else ("riverside" if biome == "coast" else "meadow")
	var ids := {"gate": loc_id + "_gate", "wild": loc_id + "_wild", "ruins": loc_id + "_ruins", "heart": loc_id + "_heart", "cave": loc_id + "_cave"}
	var pool := func(i: int) -> Array: return surface_pools[i % surface_pools.size()]
	var nodes := [
		{"id": ids.gate, "name": "Ворота", "name_en": "Gate", "kind": "meadow", "pos": [0.1, 0.5], "links": [ids.wild, ids.ruins],
			"start": true, "desc": "Вход в локацию.", "desc_en": "The entrance.", "features": {"enemies": 3, "pool": pool.call(0), "chests": 2}},
		{"id": ids.wild, "name": "Чаща", "name_en": "Thicket", "kind": wild, "pos": [0.4, 0.26], "links": [ids.gate, ids.heart, ids.cave],
			"desc": "Остров посреди провала — к нему ведёт разрушенный мост.", "desc_en": "An island in a chasm.",
			"features": {"enemies": 4, "pool": pool.call(1), "chests": 2, "platforms": true}},
		{"id": ids.ruins, "name": "Руины", "name_en": "Ruins", "kind": "ruins", "pos": [0.42, 0.78], "links": [ids.gate, ids.heart],
			"desc": "Старые стены и тайник.", "desc_en": "Old walls and a cache.", "features": {"enemies": 4, "pool": pool.call(2), "chests": 2, "safe": true}},
		{"id": ids.heart, "name": "Сердце", "name_en": "Heart", "kind": wild, "pos": [0.82, 0.5], "links": [ids.wild, ids.ruins],
			"desc": "Логово хозяина этих мест.", "desc_en": "The lair of the local master.",
			"features": {"enemies": 4, "pool": pool.call(1), "chests": 2, "boss": boss}},
		{"id": ids.cave, "name": "Пещера", "name_en": "Cave", "kind": "cave", "pos": [0.62, 0.1], "links": [ids.wild], "floor": 1,
			"desc": "Тёмная пещера.", "desc_en": "A dark cave.", "features": {"enemies": 4, "pool": cave_pool, "chests": 3, "safe": true}},
	]
	if boss == "":
		nodes[3].features.erase("boss")
	raw.locations[loc_id] = {"biome": biome, "sky": "day", "music": 0, "desc": entry.get("name", loc_id), "desc_en": entry.get("name_en", loc_id), "nodes": nodes}
	if not write(LOC_PATH, raw):
		return "Не удалось записать " + LOC_PATH
	entry["status"] = "open"
	if not write(MAP_PATH, map):
		return "Не удалось записать " + MAP_PATH
	return ""
