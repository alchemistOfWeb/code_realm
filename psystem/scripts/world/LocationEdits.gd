class_name LocationEdits
extends RefCounted
## Ручные правки поверхности локации поверх процедурной генерации (редактор локаций — scenes/editor).
## Файл: res://data/location_edits/<loc_id>.json. Генератор (OutdoorGenerator) применяет правки при построении.
##
## Формат:
##   objects: {ключ: {"pos": [x, z], "removed": bool}} — положение (и удаление) сгенерированных объектов.
##            Ключи: region:<район>, island:<район>, cave:<район>:<пещера>, tower:<район>, building:<район>,
##            columns:<район>, sign:<район>, chest:<район>:<n>, enemy:<район>:<n>, boss:<район>,
##            npc:<район>:<id>, safe:<район>, add:<n> (добавленные вручную).
##   added:   [{"key": "add:<n>", "type": chest|enemy|tree|pine|dead_tree|rock|bush, "pos": [x, z], "enemy": id}]
##   terrain: {"x,z": dh} — сдвиг высоты вершины рельефа (кисти «поднять/опустить/выровнять/сгладить»)
##   clear:   {"x,z": true} — клетки без растительности (кисть «убрать растительность»)
##   pinned:  true — при первом сохранении редактор закрепляет положения всех объектов, чтобы правка одного
##            не сдвигала остальные.

## Папка правок (тесты подменяют на user://)
static var dir := "res://data/location_edits/"

static var _cache: Dictionary = {}


static func path(loc_id: String) -> String:
	return dir + loc_id + ".json"


static func empty() -> Dictionary:
	return {"version": 1, "objects": {}, "added": [], "terrain": {}, "clear": {}, "pinned": false}


static func load_edits(loc_id: String) -> Dictionary:
	if _cache.has(loc_id):
		return _cache[loc_id]
	var e := empty()
	if FileAccess.file_exists(path(loc_id)):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path(loc_id)))
		if parsed is Dictionary:
			for k in parsed:
				e[k] = parsed[k]
	_cache[loc_id] = e
	return e


static func save_edits(loc_id: String, edits: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
	var f := FileAccess.open(path(loc_id), FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(edits, "\t"))
	f.close()
	_cache[loc_id] = edits
	invalidate(loc_id)
	return true


## Сбросить кэши, построенные по старым правкам (поверхность, картинка карты локации).
static func invalidate(loc_id: String) -> void:
	OutdoorGenerator.invalidate(loc_id)
	load("res://scenes/world/LocationMap.gd").clear_cache(loc_id)


static func has_edits(edits: Dictionary) -> bool:
	return not (edits.objects.is_empty() and edits.added.is_empty() and edits.terrain.is_empty() and edits.clear.is_empty())


## Положение объекта с учётом правки (или исходное).
static func pos_of(edits: Dictionary, key: String, default: Vector2) -> Vector2:
	var o: Dictionary = edits.get("objects", {}).get(key, {})
	if o.has("pos"):
		return Vector2(float(o.pos[0]), float(o.pos[1]))
	return default


static func is_removed(edits: Dictionary, key: String) -> bool:
	return bool(edits.get("objects", {}).get(key, {}).get("removed", false))


static func set_pos(edits: Dictionary, key: String, p: Vector2) -> void:
	var o: Dictionary = edits.objects.get(key, {})
	o["pos"] = [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]
	edits.objects[key] = o


static func set_removed(edits: Dictionary, key: String, removed: bool) -> void:
	var o: Dictionary = edits.objects.get(key, {})
	o["removed"] = removed
	edits.objects[key] = o


static func terrain_delta(edits: Dictionary, x: int, z: int) -> float:
	return float(edits.get("terrain", {}).get("%d,%d" % [x, z], 0.0))
