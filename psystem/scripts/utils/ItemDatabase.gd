class_name ItemDatabase
extends RefCounted
## Каталог снаряжения (data/items.json): оружие, щиты, броня, украшения. Карты здесь не продаются.

const PATH := "res://data/items.json"
const RENDER_DIR := "res://assets/items/"

## Слоты экипировки: порядок — как на кукле персонажа.
const SLOTS := {
	"head": {"name": "Голова", "icon": "hood"},
	"shoulders": {"name": "Плечи", "icon": "pauldrons"},
	"chest": {"name": "Торс", "icon": "leather-vest"},
	"hands": {"name": "Руки", "icon": "gauntlet"},
	"legs": {"name": "Ноги", "icon": "trousers"},
	"feet": {"name": "Обувь", "icon": "leather-boot"},
	"weapon": {"name": "Оружие", "icon": "broadsword"},
	"offhand": {"name": "Вторая рука", "icon": "roman-shield"},
	"ring": {"name": "Кольцо", "icon": "ring"},
	"amulet": {"name": "Амулет", "icon": "gem-pendant"},
}
const CATEGORIES := {
	"weapons": {"name": "Оружие", "slots": ["weapon"]},
	"shields": {"name": "Щиты", "slots": ["offhand"]},
	"armor": {"name": "Броня", "slots": ["head", "shoulders", "chest", "hands", "legs", "feet"]},
	"trinkets": {"name": "Украшения", "slots": ["ring", "amulet"]},
}
const STAT_NAMES := {
	"damage": "Урон оружия", "armor": "Броня", "hp": "Здоровье", "max_mana": "Мана",
	"max_stamina": "Выносливость", "strength": "Сила", "agility": "Ловкость", "dodge": "Уклонение, %",
}
## Стартовый комплект нового героя.
const STARTER := {"weapon": "sword_rusty", "chest": "shirt_linen", "legs": "pants_canvas", "feet": "wraps", "hands": "sleeves_cloth"}
const SELL_RATIO := 0.5

static var _items: Dictionary = {}
static var _order: Array = []
static var _lang := ""


static func _ensure() -> void:
	if not _items.is_empty() and _lang == Loc.lang():
		return
	_lang = Loc.lang()
	_items.clear()
	_order.clear()
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	for raw in data.get("items", []):
		var item: Dictionary = Loc.localized(raw, ["name", "desc"])
		_items[item.id] = item
		_order.append(item.id)


static func get_item(id: String) -> Dictionary:
	_ensure()
	return _items.get(id, {})


static func all_items() -> Array:
	_ensure()
	var list: Array = []
	for id in _order:
		list.append(_items[id])
	return list


static func shop_items(category: String) -> Array:
	var slots: Array = CATEGORIES[category].slots
	var list := all_items().filter(func(it): return it.get("price", 0) > 0 and it.slot in slots)
	list.sort_custom(func(a, b): return a.price < b.price)
	return list


## Вес предмета в кг (поле weight; по умолчанию 1).
static func weight(item: Dictionary) -> float:
	return float(item.get("weight", 1.0))


static func format_weight(kg: float) -> String:
	return ("%.1f" % kg).trim_suffix(".0")


static func sell_price(item: Dictionary) -> int:
	return maxi(1, int(item.get("price", 0) * SELL_RATIO)) if item.get("price", 0) > 0 else 1


## Двуручное оружие (луки, клеймор, двойной топор, боевой молот, копьё, коса) занимает обе руки.
static func is_two_handed(item: Dictionary) -> bool:
	return item.get("two_handed", false)


## Может ли предмет занять слот (кинжал можно взять во вторую руку).
static func fits(item: Dictionary, slot: String) -> bool:
	if item.get("slot") == slot:
		return true
	return slot == "offhand" and item.get("offhand_ok", false)


## Иконка: отрендеренная 3D-модель (assets/items/<id>.png), иначе иконка game-icons.
static func icon(item: Dictionary) -> Texture2D:
	var render := RENDER_DIR + String(item.get("id", "")) + ".png"
	if ResourceLoader.exists(render):
		return load(render)
	var name: String = item.get("icon", "")
	if name == "":
		name = {"weapon": "broadsword", "offhand": "roman-shield"}.get(item.get("slot"), SLOTS.get(item.get("slot"), {}).get("icon", "chest"))
		match item.get("weapon_type", ""):
			"dagger": name = "broad-dagger"
			"bow": name = "bow-arrow"
			"axe": name = "battle-axe"
			"hammer": name = "flat-hammer"
			"spear": name = "barbed-spear"
	return Palette.game_icon(name)


## Цвет рамки по уровню предмета (обычный → редкий → эпический).
static func tier_color(item: Dictionary) -> Color:
	var lvl: int = item.get("level", 1)
	if lvl >= 8:
		return Color("#B565F0")
	if lvl >= 5:
		return Color("#4DA3FF")
	if lvl >= 2:
		return Color("#3DDC97")
	return Color("#A0A6B8")


## Строки характеристик: ["+2 Броня", ...].
static func stat_lines(item: Dictionary) -> PackedStringArray:
	var lines: PackedStringArray = []
	var stats: Dictionary = item.get("stats", {})
	for key in STAT_NAMES:
		if stats.has(key) and int(stats[key]) != 0:
			lines.append("%+d %s" % [int(stats[key]), Loc.t(STAT_NAMES[key])])
	if item.has("weapon_type"):
		var w: Dictionary = XPCalculator.WEAPONS.get(item.weapon_type, {})
		if not w.is_empty():
			lines.insert(0, Loc.t("Атака: %s") % Loc.t(w.name))
			lines.insert(1, Loc.t("Расход выносливости: %d") % XPCalculator.weapon_item_cost(item))
			if is_two_handed(item):
				lines.insert(2, Loc.t("Двуручное: занимает обе руки"))
	return lines
