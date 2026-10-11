class_name Appearance
extends RefCounted
## Внешность героя и NPC: расы, причёски, цвета кожи и волос. Данные для HeroRig и экрана создания героя.
##
## Цвета кожи и волос — целевые sRGB-цвета; HeroRig пересчитывает их в множитель текстуры.

const GENDERS := {"male": "Мужчина", "female": "Женщина"}

## scale — масштаб скелета (x, y, z); head — компенсация масштаба головы (чтобы голова не сплющивалась).
## bonus — стартовые прибавки к атрибутам при создании героя.
const RACES := {
	"human": {"name": "Человек", "desc": "Упорные и разносторонние. Быстро учатся всему понемногу.",
		"bonus_text": "+1 очко атрибутов", "bonus": {"attribute_points": 1},
		"scale": Vector3(1, 1, 1), "head": Vector3(1, 1, 1), "parts": [],
		"skins": ["#E4BFA6", "#CFA083", "#B07D5C", "#86593D", "#553826"]},
	"elf": {"name": "Эльф", "desc": "Изящные долгожители лесов. Ловкие и чуткие к магии.",
		"bonus_text": "+1 Ловкость, +1 мана", "bonus": {"agility": 1, "max_mana": 1},
		"scale": Vector3(0.95, 1.04, 0.95), "head": Vector3(1.0, 0.98, 1.0), "parts": ["Race_ElfEar"],
		"skins": ["#E8CDB9", "#D4AE8C", "#B9A890", "#8E82A6", "#5A536E"]},
	"dwarf": {"name": "Дворф", "desc": "Коренастые мастера гор и кузниц. Выносливы как скала.",
		"bonus_text": "+2 выносливости", "bonus": {"max_stamina": 2},
		"scale": Vector3(1.13, 0.84, 1.13), "head": Vector3(0.92, 1.14, 0.92), "parts": [],
		"skins": ["#E2B699", "#C9946F", "#A87150", "#7E5034", "#5C3B28"]},
	"orc": {"name": "Орк", "desc": "Сильные и гордые воины степей. Клыки — предмет гордости.",
		"bonus_text": "+1 Сила", "bonus": {"strength": 1},
		"scale": Vector3(1.1, 1.06, 1.1), "head": Vector3(0.96, 0.96, 0.96), "parts": ["Race_OrcTusk"],
		"skins": ["#8FB060", "#76984C", "#5F8246", "#557259", "#7E8C52"]},
	"halfling": {"name": "Полурослик", "desc": "Невысокие, но взрослые и хитрые путешественники.",
		"bonus_text": "+1 Ловкость, +1 выносливость", "bonus": {"agility": 1, "max_stamina": 1},
		"scale": Vector3(0.74, 0.72, 0.74), "head": Vector3(1.08, 1.08, 1.08), "parts": [],
		"skins": ["#E6C3A9", "#D2A585", "#B98764", "#946345", "#62412D"]},
	"tiefling": {"name": "Тифлинг", "desc": "Потомки древнего пакта. Рога и врождённый дар к магии.",
		"bonus_text": "+3 маны", "bonus": {"max_mana": 3},
		"scale": Vector3(1, 1.02, 1), "head": Vector3(1, 1, 1), "parts": ["Race_Horn"],
		"skins": ["#B9524A", "#983C44", "#80457E", "#62438E", "#C47E64"]},
}

const HAIRSTYLES := {
	"male": ["Hair_Buzzed", "Hair_SimpleParted", "Hair_Long", ""],
	"female": ["Hair_Long", "Hair_Buns", "Hair_SimpleParted", "Hair_BuzzedFemale", ""],
}
const HAIR_NAMES := {
	"Hair_Buzzed": "Ёжик", "Hair_SimpleParted": "Пробор", "Hair_Long": "Длинные", "Hair_Buns": "Пучки",
	"Hair_BuzzedFemale": "Короткая", "": "Без волос",
}
const HAIR_COLORS := ["#1E1A18", "#4A2F22", "#8A5A35", "#C79A5B", "#E8D6A8", "#A8402A",
	"#9A9A9A", "#F0F0F0", "#3D5FA8", "#6E3C8E", "#2F7A4D"]
## Цвета одежды: 0 — базовая расцветка текстуры, 1 — альтернативная.
const OUTFIT_VARIANTS := 2

## Средний цвет базовых текстур (sRGB): кожа и седые волосы.
const SKIN_BASE := Color(0.80, 0.57, 0.43)
const HAIR_BASE := Color(0.56, 0.56, 0.55)


static func default_look(gender: String = "male") -> Dictionary:
	return {"gender": gender, "race": "human", "skin": 1, "hair": HAIRSTYLES[gender][0],
		"hair_color": 2, "beard": false, "outfit_variant": 0}


static func race(race_id: String) -> Dictionary:
	return RACES.get(race_id, RACES.human)


static func skin_color(look: Dictionary) -> Color:
	var skins: Array = race(look.get("race", "human")).skins
	return Color(skins[clampi(int(look.get("skin", 0)), 0, skins.size() - 1)])


static func hair_color(look: Dictionary) -> Color:
	return Color(HAIR_COLORS[clampi(int(look.get("hair_color", 0)), 0, HAIR_COLORS.size() - 1)])


## Множитель для albedo_color, чтобы текстура со средним цветом base выглядела как target.
static func tint_for(target: Color, base: Color) -> Color:
	var t := target.srgb_to_linear()
	var b := base.srgb_to_linear()
	return Color(t.r / maxf(b.r, 0.01), t.g / maxf(b.g, 0.01), t.b / maxf(b.b, 0.01)).linear_to_srgb()


## Случайная внешность для NPC (детерминированно по seed).
static func random_look(seed_value: int, race_id: String = "") -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var gender: String = "male" if rng.randf() < 0.5 else "female"
	if race_id == "":
		race_id = RACES.keys()[rng.randi() % RACES.size()]
	var styles: Array = HAIRSTYLES[gender]
	return {"gender": gender, "race": race_id, "skin": rng.randi() % 5, "hair": styles[rng.randi() % styles.size()],
		"hair_color": rng.randi() % HAIR_COLORS.size(), "beard": gender == "male" and rng.randf() < 0.45,
		"outfit_variant": rng.randi() % OUTFIT_VARIANTS}
