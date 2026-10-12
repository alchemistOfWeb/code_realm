class_name XPCalculator
extends RefCounted
## Формулы прогрессии и баланс наград. Все числа баланса — здесь.

const START_ENERGY := 50
const MAX_ENERGY := 50
const LEARN_ENERGY_REWARD := 5
const TREE_TEST_ENERGY_REWARD := 20
## Энергия даётся только на базе: за изучение тем и тесты. Повторный зачёт — меньше и не чаще перезарядки.
const NODE_TEST_ENERGY := 4
const NODE_RETEST_ENERGY := 1
## Свободные очки атрибутов при создании героя (+ расовый бонус).
const CREATION_POINTS := 2
## Вылазка в локацию (раньше экспедиция стоила 30).
const SORTIE_ENERGY_COST := 10
## Колода может быть любого размера (ограничения снизу нет).
const MIN_DECK_SIZE := 0
const MAX_DECK_SIZE := 30
## Вылазки: выносливость бега (в секундах бега) и её восстановление.
const RUN_STAMINA := 6.0
const RUN_STAMINA_REGEN := 1.6
## Переносимый вес (кг): база + за каждое очко выносливости. Перегруз — медленный шаг без бега.
const CARRY_BASE := 10.0
const CARRY_PER_STAMINA := 2.0
const OVERLOAD_SPEED := 0.55

# Карточный бой
const START_HAND := 4
const HAND_TARGET := 5          # добор до 5 карт в начале хода
const HAND_MAX := 7
const BOARD_MAX := 5
const MAX_CRYSTALS := 10
const STAMINA_REGEN := 3
const MAX_COPIES := 3           # копий одной карты в колоде
const MAX_LEGENDARY_COPIES := 1
## Оружие: урон = base + per × атрибут (+ урон снаряжения), стоимость в выносливости.
## Доступные в бою атаки зависят от экипированного оружия (без оружия — кулаки).
const WEAPONS := {
	"fists": {"name": "Кулаки", "icon": "fist", "attr": "strength", "base": 1, "per": 1, "cost": 2,
		"desc": "Без оружия: урон 1 + Сила."},
	"sword": {"name": "Меч", "icon": "ancient-sword", "attr": "strength", "base": 2, "per": 1, "cost": 4,
		"desc": "Урон 2 + Сила. Цель — враг или его существо."},
	"dagger": {"name": "Кинжал", "icon": "broad-dagger", "attr": "agility", "base": 1, "per": 1, "cost": 2,
		"desc": "Урон 1 + Ловкость. Дешёвый быстрый удар."},
	"bow": {"name": "Лук", "icon": "bow-arrow", "attr": "agility", "base": 1, "per": 1, "cost": 3,
		"desc": "Урон 1 + Ловкость. Стреляет через Taunt прямо во врага."},
	"axe": {"name": "Топор", "icon": "battle-axe", "attr": "strength", "base": 3, "per": 1, "cost": 5,
		"desc": "Урон 3 + Сила. Тяжёлый удар."},
	"hammer": {"name": "Молот", "icon": "flat-hammer", "attr": "strength", "base": 2, "per": 1, "cost": 4,
		"desc": "Урон 2 + Сила. Сначала сбивает щит и божественный щит цели."},
	"spear": {"name": "Копьё", "icon": "barbed-spear", "attr": "agility", "base": 2, "per": 1, "cost": 3,
		"desc": "Урон 2 + Ловкость. Удар по существу задевает и героя за ним (1 урон)."},
}
## Руны: тратят ману (мана не восстанавливается в бою).
const RUNES := {
	"fire": {"name": "Руна огня", "icon": "fire-ray", "cost": 4, "damage": 4, "desc": "4 урона любой вражеской цели."},
	"shield": {"name": "Руна щита", "icon": "magic-shield", "cost": 3, "shield": 4, "desc": "+4 щита (поглощает урон)."},
	"heal": {"name": "Руна жизни", "icon": "healing", "cost": 5, "heal": 5, "desc": "Восстанавливает 5 HP."},
}

# Тесты
const TREE_TEST_PASS_RATIO := 0.7       # общий тест дерева: 70% верных
const NODE_TEST_PASS_RATIO := 0.6       # тест узла: 60% верных
const TREE_RETEST_COOLDOWN_HOURS := 20  # повторная награда за дерево — не чаще
const TREE_RETEST_ENERGY := 8
const TREE_RETEST_XP_RATIO := 0.25

# Карты: базовые шансы редкостей (difficulty — средняя сложность 1..3)
const LEGENDARY_BASE := 0.02
const LEGENDARY_PER_DIFF := 0.01
const RARE_BASE := 0.08
const RARE_PER_DIFF := 0.05
const UNCOMMON_CHANCE := 0.20

## Атрибуты персонажа: стартовое значение, прирост за очко, описание эффекта.
const ATTRIBUTES := {
	"max_mana": {"name": "Макс. мана", "start": 1, "per_point": 1, "icon": "sparkles",
		"desc": "Мана для активации рун в бою"},
	"strength": {"name": "Сила", "start": 1, "per_point": 1, "icon": "sword",
		"desc": "+1 урон мечом, топором, молотом и кулаками за очко"},
	"agility": {"name": "Ловкость", "start": 1, "per_point": 1, "icon": "zap",
		"desc": "+1 урон кинжалом, луком и копьём, +0.5% уклонения за очко"},
	"max_stamina": {"name": "Макс. выносливость", "start": 10, "per_point": 1, "icon": "flame",
		"desc": "Выносливость для атак оружием, бега в вылазках и переносимого веса"},
}


static func carry_capacity(max_stamina: int) -> float:
	return CARRY_BASE + CARRY_PER_STAMINA * max_stamina


## Сила врагов вылазки: растёт с глубиной подлокации (шагов от стартовой по графу локации)
## и уровнем локации. Первые враги уже чуть сильнее каталога (×1.1).
const ENEMY_POWER_BASE := 1.1
const ENEMY_POWER_PER_DEPTH := 0.25
const ENEMY_POWER_PER_LEVEL := 0.08


static func enemy_power(depth: int, location_level: int) -> float:
	return ENEMY_POWER_BASE + ENEMY_POWER_PER_DEPTH * depth + ENEMY_POWER_PER_LEVEL * maxi(location_level - 1, 0)


## Копия врага из каталога с усилением: HP и награды × power, атака растёт вдвое медленнее.
static func scaled_enemy(info: Dictionary, power: float) -> Dictionary:
	if info.is_empty() or is_equal_approx(power, 1.0):
		return info
	var e := info.duplicate(true)
	e.hp = roundi(float(info.get("hp", 15)) * power)
	e.attack = maxi(int(info.get("attack", 3)), roundi(float(info.get("attack", 3)) * (1.0 + (power - 1.0) * 0.5)))
	e.xp_reward = roundi(float(info.get("xp_reward", 10)) * power)
	e.gold_reward = roundi(float(info.get("gold_reward", 5)) * power)
	e.power = power
	return e


## XP для перехода с уровня level на level+1: x₁ = 20, xₙ = xₙ₋₁ + 10·n (20, 40, 70, 110, 160…).
static func xp_to_next(level: int) -> int:
	return 10 + 5 * level * (level + 1)


## Расход выносливости атакой оружием: базовый для вида оружия + у тяжёлых (от 6 кг) +1.
static func weapon_item_cost(item: Dictionary) -> int:
	var w: Dictionary = WEAPONS.get(item.get("weapon_type", ""), WEAPONS.fists)
	return int(item.get("stamina_cost", int(w.cost) + (1 if float(item.get("weight", 1.0)) >= 6.0 else 0)))


## HP персонажа: 15 + 3 за уровень (бой и экспедиции).
static func max_hp_for_level(level: int) -> int:
	return 15 + level * 3


## Награда за изучение узла: главный — difficulty*10, подузел — difficulty*5.
static func node_xp(difficulty: int, is_main: bool) -> int:
	return difficulty * (10 if is_main else 5)


## Бонус за первый успешный тест узла.
static func node_test_bonus(difficulty: int) -> int:
	return difficulty * 3


## Число карт за дерево: 1–3 по средней сложности.
static func tree_card_count(avg_difficulty: float) -> int:
	return clampi(roundi(avg_difficulty), 1, 3)


## Сундуков за достижение уровня: 1, на каждом 5-м уровне — 2.
static func lootboxes_for_level(level: int) -> int:
	return 2 if level % 5 == 0 else 1


## Уклонение в процентах от ловкости (+ бонус снаряжения), не больше 60%.
static func dodge_chance(agility: int, bonus: int = 0) -> float:
	return minf(agility * 0.5 + bonus, 60.0)


static func format_percent(v: float) -> String:
	return ("%.1f" % v).trim_suffix(".0") + "%"


static func stars(difficulty: int) -> String:
	difficulty = clampi(difficulty, 0, 3)
	return "★".repeat(difficulty) + "☆".repeat(3 - difficulty)
