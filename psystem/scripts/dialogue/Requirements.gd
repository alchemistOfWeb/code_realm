class_name Requirements
extends RefCounted
## Проверки условий мира: знания из дерева, флаги, предметы, золото и броски d20.
##
## Знание (knowledge):
##   {"spec": "python_backend", "topic": "Очереди"} — узел специализации, в названии которого есть topic,
##       изучен (для раздела достаточно половины подтем);
##   {"spec": "ai_developer", "min": 5}            — изучено не меньше 5 тем специализации;
##   {"tree_test": "python_developer"}             — общий тест дерева пройден.
## Условие (if/require): {"flag"}, {"not_flag"}, {"item"}, {"gold"}, {"knowledge"}.
## Проверка (check): {"attr": "strength"|"agility", "dc": 12, "bonus_spec": "..."} — d20 + атрибут + бонус знаний.

const ATTR_NAMES := {"strength": "СИЛА", "agility": "ЛОВКОСТЬ"}
const ITEM_NAMES := {"valve": "Латунный клапан"}


## Узел специализации по подстроке названия (без учёта регистра). Пустой — не найден.
static func find_topic_node(spec_id: String, topic: String) -> Dictionary:
	var t := topic.to_lower()
	for node in ContentParser.get_flat_nodes(spec_id):
		if t in String(node.title).to_lower():
			return node
	return {}


static func knowledge_met(req: Dictionary) -> bool:
	if req.has("tree_test"):
		return GameManager.test_record("tree:" + req.tree_test).get("passes", 0) > 0
	var spec: String = req.get("spec", "")
	if req.has("min"):
		return GameManager.count_learned(spec) >= int(req.min)
	if req.has("topic"):
		var node := find_topic_node(spec, req.topic)
		if node.is_empty():
			return false
		if GameManager.is_learned(node.id):
			return true
		if node.get("is_main", false) and not node.get("subnodes", []).is_empty():
			var prog: Array = GameManager.subnode_progress(node)
			return prog[0] * 2 >= prog[1]
	return false


## Подпись требования знания: «Python Backend · Очереди и фоновые задачи».
static func knowledge_label(req: Dictionary) -> String:
	if req.has("tree_test"):
		return "%s · общий тест" % ContentParser.get_spec_name(req.tree_test)
	var spec: String = req.get("spec", "")
	var name := ContentParser.get_spec_name(spec)
	if req.has("min"):
		return "%s · %d+ тем" % [name, req.min]
	var node := find_topic_node(spec, req.get("topic", ""))
	return "%s · %s" % [name, node.get("title", req.get("topic", ""))]


static func knowledge_spec(req: Dictionary) -> String:
	return req.get("spec", req.get("tree_test", ""))


## Выполнено ли условие видимости/доступности.
static func condition_met(cond: Dictionary) -> bool:
	if cond.has("flag") and not GameManager.has_flag(cond.flag):
		return false
	if cond.has("not_flag") and GameManager.has_flag(cond.not_flag):
		return false
	if cond.has("item") and GameManager.item_count(cond.item) <= 0:
		return false
	if cond.has("gold") and int(GameManager.player_data.gold) < int(cond.gold):
		return false
	if cond.has("knowledge") and not knowledge_met(cond.knowledge):
		return false
	return true


## Почему условие не выполнено (для подсказки на заблокированной реплике).
static func lock_reason(cond: Dictionary) -> String:
	if cond.has("knowledge") and not knowledge_met(cond.knowledge):
		var k: Dictionary = cond.knowledge
		if k.has("min"):
			return "Изучи ещё темы в дереве «%s» (нужно %d, изучено %d)" % [ContentParser.get_spec_name(k.spec), k.min, GameManager.count_learned(k.spec)]
		if k.has("tree_test"):
			return "Пройди общий тест дерева «%s»" % ContentParser.get_spec_name(k.tree_test)
		return "Нужно знание: изучи тему «%s» в дереве «%s»" % [find_topic_node(k.spec, k.topic).get("title", k.topic), ContentParser.get_spec_name(k.spec)]
	if cond.has("gold") and int(GameManager.player_data.gold) < int(cond.gold):
		return "Нужно %d золота (у тебя %d)" % [cond.gold, GameManager.player_data.gold]
	if cond.has("item") and GameManager.item_count(cond.item) <= 0:
		return "Нужен предмет: %s" % ITEM_NAMES.get(cond.item, cond.item)
	return "Недоступно"


## Бонус к броску от знаний специализации: +1 за каждые 8 изученных тем, максимум +4.
static func knowledge_bonus(spec_id: String) -> int:
	if spec_id == "":
		return 0
	return mini(4, GameManager.count_learned(spec_id) / 8)


static func attr_bonus(attr: String) -> int:
	return int(GameManager.player_data.attributes.get(attr, 0))


## Шанс успеха проверки в процентах (для подсказки).
static func check_chance(check: Dictionary) -> int:
	var need: int = int(check.get("dc", 10)) - attr_bonus(check.get("attr", "")) - knowledge_bonus(check.get("bonus_spec", ""))
	var success_faces := clampi(21 - need, 1, 19)   # 1 — всегда провал, 20 — всегда успех
	return success_faces * 5


## Бросок d20: {roll, attr_bonus, know_bonus, total, dc, success, natural}
static func roll_check(check: Dictionary) -> Dictionary:
	var roll := randi_range(1, 20)
	var ab := attr_bonus(check.get("attr", ""))
	var kb := knowledge_bonus(check.get("bonus_spec", ""))
	var total := roll + ab + kb
	var dc: int = int(check.get("dc", 10))
	var success := total >= dc
	var natural := ""
	if roll == 20:
		success = true
		natural = "КРИТИЧЕСКИЙ УСПЕХ"
	elif roll == 1:
		success = false
		natural = "КРИТИЧЕСКИЙ ПРОВАЛ"
	return {"roll": roll, "attr_bonus": ab, "know_bonus": kb, "total": total, "dc": dc, "success": success,
		"natural": natural, "attr": check.get("attr", "")}
