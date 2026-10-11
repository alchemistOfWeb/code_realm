extends Node
## Сохранение/загрузка состояния в user://saves/*.json.
## Запись атомарная (через .tmp), числа после JSON приводятся обратно к int.

signal saved()
signal loaded()

const SAVE_DIR := "user://saves/"
## Текущая папка сохранений (тесты подменяют её, чтобы не трогать реальный прогресс).
var save_dir: String = SAVE_DIR
const SAVE_VERSION := 2
const PLAYER_FILE := "player_save.json"
const KNOWLEDGE_FILE := "knowledge_progress.json"
const CARDS_FILE := "card_collection.json"
const WORLD_FILE := "world_state.json"

var _save_queued := false


func _ready() -> void:
	load_all()
	# Автосохранение при любом изменении состояния
	GameManager.player_changed.connect(request_save)
	GameManager.knowledge_unlocked.connect(func(_id): request_save())
	GameManager.knowledge_reset.connect(func(_id): request_save())
	GameManager.deck_changed.connect(request_save)
	GameManager.world_changed.connect(request_save)


## Отложенное сохранение: несколько вызовов за кадр → одна запись.
func request_save() -> void:
	if _save_queued:
		return
	_save_queued = true
	_flush_save.call_deferred()


func _flush_save() -> void:
	_save_queued = false
	save_all()


func save_all() -> void:
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
		"deck": GameManager.combat_deck,
	})
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
	GameManager.combat_deck = cards.get("deck", [])

	var world: Dictionary = _load_json(WORLD_FILE)
	world.erase("save_version")
	_merge_defaults(world, GameManager.default_world())
	GameManager.world = world
	loaded.emit()


## Удалить все сохранения и начать заново.
func wipe() -> void:
	for file_name in [PLAYER_FILE, KNOWLEDGE_FILE, CARDS_FILE, WORLD_FILE]:
		if FileAccess.file_exists(save_dir + file_name):
			DirAccess.remove_absolute(save_dir + file_name)
	GameManager.reset_all()
	save_all()


func get_save_dir_absolute() -> String:
	return ProjectSettings.globalize_path(save_dir)


func _save_json(file_name: String, data: Dictionary) -> void:
	var path := save_dir + file_name
	var tmp := path + ".tmp"
	var file := FileAccess.open(tmp, FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: не удалось открыть %s (%s)" % [tmp, error_string(FileAccess.get_open_error())])
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	DirAccess.rename_absolute(tmp, path)


func _load_json(file_name: String) -> Dictionary:
	var path := save_dir + file_name
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		push_warning("SaveSystem: повреждён файл " + path)
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
