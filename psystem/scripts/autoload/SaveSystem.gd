extends Node
## Профили и сохранения. Каждый профиль — папка user://profiles/<id>/ с четырьмя JSON-файлами,
## список профилей — user://profiles.json. Запись атомарная (через .tmp), числа после JSON приводятся к int.
##
## Пока профиль не выбран (главное меню), автосохранение выключено.

signal saved()
signal loaded()
signal profiles_changed()

const LEGACY_DIR := "user://saves/"
## Пути профилей (тесты подменяют их, чтобы не трогать настоящие профили).
var profiles_file := "user://profiles.json"
var profiles_dir := "user://profiles/"
const SAVE_VERSION := 3
const PLAYER_FILE := "player_save.json"
const KNOWLEDGE_FILE := "knowledge_progress.json"
const CARDS_FILE := "card_collection.json"
const WORLD_FILE := "world_state.json"
const FILES := [PLAYER_FILE, KNOWLEDGE_FILE, CARDS_FILE, WORLD_FILE]

## Текущая папка сохранений (тесты и dev-режим подменяют её через use_dir()).
var save_dir: String = ""
## id выбранного профиля ("" — временная папка dev/тестов или профиль не выбран).
var profile_id := ""
## [{id, name, created, last_played, level, look}]
var profiles: Array = []

var _active := false
var _save_queued := false


func _ready() -> void:
	_load_profiles()
	_migrate_legacy()


## Перечитать список профилей (после смены profiles_file в тестах).
func reload_profiles() -> void:
	_load_profiles()
	# Автосохранение при любом изменении состояния
	GameManager.player_changed.connect(request_save)
	GameManager.knowledge_unlocked.connect(func(_id): request_save())
	GameManager.knowledge_reset.connect(func(_id): request_save())
	GameManager.deck_changed.connect(request_save)
	GameManager.world_changed.connect(request_save)


func has_active_profile() -> bool:
	return _active


# ---------------------------------------------------------------- Профили

func list_profiles() -> Array:
	var list := profiles.duplicate()
	list.sort_custom(func(a, b): return String(a.get("last_played", "")) > String(b.get("last_played", "")))
	return list


func get_profile(id: String) -> Dictionary:
	for p in profiles:
		if p.id == id:
			return p
	return {}


func last_profile_id() -> String:
	var list := list_profiles()
	return list[0].id if not list.is_empty() else ""


## Создать профиль: состояние GameManager уже подготовлено экраном создания героя.
func create_profile(hero_name: String) -> String:
	var id := "p%d%03d" % [int(Time.get_unix_time_from_system()), randi() % 1000]
	profiles.append({"id": id, "name": hero_name, "created": Time.get_datetime_string_from_system(),
		"last_played": Time.get_datetime_string_from_system(), "level": 1, "look": GameManager.player_data.get("look", {}),
		"outfit": GameManager.hero_outfit()})
	profile_id = id
	save_dir = profiles_dir + id + "/"
	_active = true
	save_all()
	_save_profiles()
	return id


func select_profile(id: String) -> bool:
	if get_profile(id).is_empty():
		return false
	profile_id = id
	save_dir = profiles_dir + id + "/"
	_active = true
	load_all()
	_touch_profile()
	return true


## Выйти в главное меню: сохранить и сбросить состояние в памяти.
func close_profile() -> void:
	if _active:
		save_all()
	_active = false
	profile_id = ""
	GameManager.reset_all()


func delete_profile(id: String) -> void:
	if id == profile_id:
		_active = false
		profile_id = ""
		GameManager.reset_all()
	var dir := profiles_dir + id + "/"
	if DirAccess.dir_exists_absolute(dir):
		for f in DirAccess.get_files_at(dir):
			DirAccess.remove_absolute(dir + f)
		DirAccess.remove_absolute(dir)
	profiles = profiles.filter(func(p): return p.id != id)
	_save_profiles()


func rename_profile(id: String, new_name: String) -> void:
	var p := get_profile(id)
	if not p.is_empty():
		p.name = new_name
		_save_profiles()


## Временная папка без профиля (dev-скриншоты, демо, тесты).
func use_dir(dir: String, load_now: bool = false) -> void:
	save_dir = dir
	profile_id = ""
	_active = true
	if load_now:
		load_all()


func _touch_profile() -> void:
	var p := get_profile(profile_id)
	if p.is_empty():
		return
	p.last_played = Time.get_datetime_string_from_system()
	p.level = int(GameManager.player_data.get("level", 1))
	p.name = String(GameManager.player_data.get("name", p.name))
	p.look = GameManager.player_data.get("look", {})
	p.outfit = GameManager.hero_outfit()
	_save_profiles()


func _load_profiles() -> void:
	profiles = []
	if not FileAccess.file_exists(profiles_file):
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(profiles_file))
	if parsed is Dictionary:
		profiles = _coerce_ints(parsed.get("profiles", []))


func _save_profiles() -> void:
	var f := FileAccess.open(profiles_file, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({"profiles": profiles}, "\t"))
	profiles_changed.emit()


## Сохранения до появления профилей (user://saves/) переносятся в профиль «Странник».
func _migrate_legacy() -> void:
	if FileAccess.file_exists(profiles_file) or not FileAccess.file_exists(LEGACY_DIR + PLAYER_FILE):
		return
	var id := "p_legacy"
	var dir := profiles_dir + id + "/"
	DirAccess.make_dir_recursive_absolute(dir)
	for f in FILES:
		if FileAccess.file_exists(LEGACY_DIR + f):
			DirAccess.copy_absolute(LEGACY_DIR + f, dir + f)
	var player: Dictionary = _load_json_at(dir + PLAYER_FILE)
	profiles.append({"id": id, "name": Loc.t("Странник"), "created": player.get("created_at", ""),
		"last_played": Time.get_datetime_string_from_system(), "level": int(player.get("level", 1)), "look": {}})
	_save_profiles()


# ---------------------------------------------------------------- Сохранение

## Отложенное сохранение: несколько вызовов за кадр → одна запись.
func request_save() -> void:
	if _save_queued or not _active:
		return
	_save_queued = true
	_flush_save.call_deferred()


func _flush_save() -> void:
	_save_queued = false
	save_all()


func save_all() -> void:
	if not _active or save_dir == "":
		return
	DirAccess.make_dir_recursive_absolute(save_dir)
	var player := GameManager.player_data.duplicate(true)
	player["save_version"] = SAVE_VERSION
	_save_json(PLAYER_FILE, player)
	_save_json(KNOWLEDGE_FILE, {
		"save_version": SAVE_VERSION,
		"progress": GameManager.knowledge_progress,
		"rewarded": GameManager.rewarded_nodes,
		"notes": GameManager.claude_notes,
		"tests": GameManager.test_records,
	})
	var world := GameManager.world.duplicate(true)
	world["save_version"] = SAVE_VERSION
	_save_json(WORLD_FILE, world)
	_save_json(CARDS_FILE, {
		"save_version": SAVE_VERSION,
		"collection": GameManager.card_collection,
		"levels": GameManager.card_levels,
		"deck": GameManager.combat_deck,
	})
	if profile_id != "":
		var p := get_profile(profile_id)
		if not p.is_empty() and (p.level != GameManager.player_data.level or p.name != GameManager.player_data.get("name", p.name)):
			_touch_profile()
	saved.emit()


func load_all() -> void:
	var defaults := GameManager.default_player_data()
	var player: Dictionary = _load_json(PLAYER_FILE)
	var version: int = player.get("save_version", SAVE_VERSION)
	player.erase("save_version")
	_merge_defaults(player, defaults)
	# HP всегда считается по формуле уровня; v1 хранил HP = уровень → лечим полностью
	player.max_hp = XPCalculator.max_hp_for_level(player.level)
	player.hp = player.max_hp if version < 2 else clampi(player.hp, 1, player.max_hp)
	GameManager.player_data = player

	var knowledge: Dictionary = _load_json(KNOWLEDGE_FILE)
	GameManager.knowledge_progress = knowledge.get("progress", {})
	GameManager.rewarded_nodes = knowledge.get("rewarded", {})
	GameManager.claude_notes = knowledge.get("notes", {})
	GameManager.test_records = knowledge.get("tests", {})

	var cards: Dictionary = _load_json(CARDS_FILE)
	GameManager.card_collection = cards.get("collection", {})
	GameManager.card_levels = cards.get("levels", {})
	GameManager.combat_deck = cards.get("deck", [])

	var world: Dictionary = _load_json(WORLD_FILE)
	world.erase("save_version")
	_merge_defaults(world, GameManager.default_world())
	GameManager.world = world
	GameManager.after_load()
	loaded.emit()
	GameManager.player_changed.emit()


## Удалить сохранения текущего профиля и начать заново (имя и внешность героя сохраняются).
func wipe() -> void:
	var hero_name: String = GameManager.player_data.get("name", Loc.t("Странник"))
	var look: Dictionary = GameManager.player_data.get("look", {})
	for file_name in FILES:
		if FileAccess.file_exists(save_dir + file_name):
			DirAccess.remove_absolute(save_dir + file_name)
	GameManager.reset_all()
	GameManager.player_data.name = hero_name
	GameManager.player_data.look = look
	save_all()


func get_save_dir_absolute() -> String:
	return ProjectSettings.globalize_path(save_dir if save_dir != "" else profiles_dir)


func _save_json(file_name: String, data: Dictionary) -> void:
	var path := save_dir + file_name
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error(Loc.t("SaveSystem: не удалось открыть %s (%s)") % [tmp, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path)


func _load_json(file_name: String) -> Dictionary:
	return _load_json_at(save_dir + file_name)


func _load_json_at(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning(Loc.t("SaveSystem: повреждён файл ") + path)
		return {}
	return _coerce_ints(parsed)


## JSON хранит все числа как float — возвращаем целые обратно в int.
func _coerce_ints(value: Variant) -> Variant:
	if value is float and value == floorf(value) and absf(value) < 1e15:
		return int(value)
	if value is Dictionary:
		for key in value.keys():
			value[key] = _coerce_ints(value[key])
	elif value is Array:
		for i in value.size():
			value[i] = _coerce_ints(value[i])
	return value


## Добавляет недостающие ключи (новые поля после обновлений игры).
func _merge_defaults(target: Dictionary, defaults: Dictionary) -> void:
	for key in defaults:
		if not target.has(key):
			target[key] = defaults[key]
		elif defaults[key] is Dictionary and target[key] is Dictionary:
			_merge_defaults(target[key], defaults[key])
