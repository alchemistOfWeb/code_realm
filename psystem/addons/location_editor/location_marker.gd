@tool
class_name LocationMarker
extends Node3D
## Объект локации в сцене редактирования (сундук, враг, башня, указатель, дерево…). Двигается гизмо Godot;
## высота берётся с рельефа при сохранении. key — ключ в файле правок (пустой — новый объект),
## kind — тип, enemy_id — какой враг (для врагов; меняется в доке «Локации»).

@export var key := ""
@export var kind := "chest"
@export var label_text := ""
@export var enemy_id := ""

@export_group("Район (только для центра района)")
## Название района (в игре и на карте).
@export var region_name := ""
## Тип: meadow — луг/хутор, forest — лес/лагерь, ruins — руины/храм, riverside — берег (остров в озере).
@export_enum("meadow", "forest", "ruins", "riverside") var region_kind := "meadow"
## Связи с соседними районами и пещерами (id) — по ним идут дороги и входы.
@export var links: PackedStringArray = []
@export var chests := 2
## Сколько врагов у центра района (бродячие враги добавляются по всей долине сами).
@export var enemies := 3
## Типы врагов района (id из data/enemies_catalog.json).
@export var enemy_pool: PackedStringArray = []
## Жители (id диалогов).
@export var npcs: PackedStringArray = []
@export var has_safe := false
## Остров в провале/озере с разрушенным мостом.
@export var island := false
## Вход в пещеру района запечатан загадкой.
@export var riddle_gate := false
## Босс района (id врага) — пусто, если нет.
@export var boss := ""


func _ready() -> void:
	if not Engine.is_editor_hint():
		return
	# Копия через Ctrl+D может прийти без визуала — дорисовать
	for c in get_children():
		if c.owner == null:
			return
	_decorate.call_deferred()


func _decorate() -> void:
	var root := edit_root()
	if root != null and not root.data.is_empty():
		root.decorate(self)


func edit_root() -> LocationEditRoot:
	var n := get_parent()
	while n != null:
		if n is LocationEditRoot:
			return n
		n = n.get_parent()
	return null
