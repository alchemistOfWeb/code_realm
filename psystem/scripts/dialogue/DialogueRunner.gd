class_name DialogueRunner
extends RefCounted
## Движок диалогов (без UI). Данные — data/dialogues.json.
##
## Узел: {text, effects[], choices[]}. Реплика (choice):
##   text, if (видимость), require (доступность, иначе замок с причиной), check (бросок d20),
##   success/failure (узлы по результату броска), goto, effects[], end, once (скрыть после выбора).
## Эффекты мира (open_gate, reveal_map, combat, riddle, npc_leave) копятся в pending_world и
## отдаются миру после закрытия диалога.

const DATA_FILE := "res://data/dialogues.json"

static var _data: Dictionary = {}

var npc_id := ""
var npc: Dictionary = {}
var node_id := ""
var node: Dictionary = {}
var pending_world: Array = []
var finished := false


static func all_npcs() -> Dictionary:
	if _data.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_FILE))
		_data = parsed if parsed is Dictionary else {"npcs": {}}
	return _data.get("npcs", {})


static func get_npc(id: String) -> Dictionary:
	return all_npcs().get(id, {})


## Начать диалог. Возвращает сообщения эффектов первого узла.
func start(id: String) -> Array:
	npc_id = id
	npc = get_npc(id)
	for rule in npc.get("start", []):
		if Requirements.condition_met(rule.get("if", {})):
			return enter(rule.goto)
	return enter(npc.get("nodes", {}).keys()[0])


func enter(id: String) -> Array:
	node_id = id
	node = npc.get("nodes", {}).get(id, {})
	if node.is_empty():
		finished = true
		return []
	return apply_effects(node.get("effects", []))


## Реплики для показа: [{index, text, tag, tag_kind, available, reason, chance}]
## tag_kind: "knowledge" | "check" | "trade" | "end" | ""
func visible_choices() -> Array:
	var result: Array = []
	var choices: Array = node.get("choices", [])
	for i in choices.size():
		var c: Dictionary = choices[i]
		if c.has("if") and not Requirements.condition_met(c["if"]):
			continue
		if c.get("once", false) and GameManager.has_flag(_once_flag(i)):
			continue
		var text: String = Loc.t(c.text)
		var tag := ""
		if text.begins_with("[") and "]" in text:
			tag = text.substr(1, text.find("]") - 1)
			text = text.substr(text.find("]") + 1).strip_edges().trim_prefix("—").strip_edges()
		var entry := {"index": i, "text": text, "tag": tag, "tag_kind": "", "available": true, "reason": "", "chance": -1, "spec": ""}
		var req: Dictionary = c.get("require", {})
		if req.has("knowledge"):
			entry.tag_kind = "knowledge"
			entry.tag = Loc.t("ЗНАНИЕ · ") + Requirements.knowledge_label(req.knowledge)
			entry.spec = Requirements.knowledge_spec(req.knowledge)
		elif req.has("gold") or req.has("item"):
			entry.tag_kind = "trade"
		if c.has("check"):
			entry.tag_kind = "check"
			var check: Dictionary = c.check
			entry.tag = Loc.t("%s · СЛ %d") % [Loc.t(Requirements.ATTR_NAMES.get(check.attr, check.attr)), check.dc]
			entry.chance = Requirements.check_chance(check)
		if c.get("end", false) and entry.tag_kind == "":
			entry.tag_kind = "end"
		if not req.is_empty() and not Requirements.condition_met(req):
			entry.available = false
			entry.reason = Requirements.lock_reason(req)
		result.append(entry)
	return result


## Выбор реплики. Возвращает {messages, roll (если была проверка), ended}
func choose(index: int) -> Dictionary:
	var choices: Array = node.get("choices", [])
	var out := {"messages": [], "roll": {}, "ended": false}
	if index < 0 or index >= choices.size():
		return out
	var c: Dictionary = choices[index]
	if c.has("require") and not Requirements.condition_met(c.require):
		return out
	if c.get("once", false):
		GameManager.set_flag(_once_flag(index))
	out.messages.append_array(apply_effects(c.get("effects", [])))
	var next := ""
	if c.has("check"):
		out.roll = Requirements.roll_check(c.check)
		next = c.success if out.roll.success else c.failure
	elif c.has("goto"):
		next = c.goto
	if c.get("end", false) or next == "":
		finished = true
		out.ended = true
		return out
	out.messages.append_array(enter(next))
	return out


func _once_flag(i: int) -> String:
	return "dlg:%s:%s:%d" % [npc_id, node_id, i]


## Применить эффекты. Возвращает тексты для показа («+15 золота», «Получена карта …»).
func apply_effects(effects: Array) -> Array:
	var msgs: Array = []
	for e in effects:
		if e.has("gold"):
			GameManager.add_gold(int(e.gold))
			msgs.append(Loc.t("+%d золота") % e.gold)
		if e.has("take_gold"):
			GameManager.add_gold(-int(e.take_gold))
			msgs.append(Loc.t("−%d золота") % e.take_gold)
		if e.has("xp"):
			GameManager.gain_xp(int(e.xp))
			msgs.append("+%d XP" % e.xp)
		if e.has("energy"):
			GameManager.gain_energy(int(e.energy))
			msgs.append(Loc.t("+%d энергии") % e.energy)
		if e.has("heal"):
			var healed := GameManager.heal_player(int(e.heal))
			if healed > 0:
				msgs.append("+%d HP" % healed)
		if e.has("damage"):
			GameManager.damage_player(int(e.damage))
			if GameManager.player_data.hp <= 0:
				GameManager.player_data.hp = 1
			msgs.append("−%d HP" % e.damage)
		if e.has("card"):
			GameManager.add_card_to_collection(e.card)
			msgs.append(Loc.t("Получена карта «%s»") % CardDatabase.get_card(e.card).get("name", e.card))
		if e.has("random_card"):
			var rc: Dictionary = e.random_card
			var pool := CardDatabase.cards_for_spec(rc.get("spec", "")) if rc.has("spec") else CardDatabase.all_cards()
			var card := CardDatabase.roll_card(pool, float(rc.get("difficulty", 1.5)))
			if not card.is_empty():
				GameManager.add_card_to_collection(card.id)
				msgs.append(Loc.t("Получена карта «%s» (%s)") % [card.name, Loc.t(CardDatabase.RARITY_NAMES.get(card.rarity, card.rarity))])
		if e.has("item"):
			GameManager.add_item(e.item)
			msgs.append(Loc.t("Получен предмет: %s") % Loc.t(Requirements.ITEM_NAMES.get(e.item, e.item)))
		if e.has("take_item"):
			GameManager.take_item(e.take_item)
		if e.has("flag"):
			GameManager.set_flag(e.flag, e.get("value", true))
		if e.has("quest"):
			var q: Dictionary = e.quest
			GameManager.set_quest(q.id, q.title, q.desc)
			msgs.append(Loc.t("Новый квест: %s") % Loc.t(q.title))
		if e.has("quest_done"):
			GameManager.complete_quest(e.quest_done)
			msgs.append(Loc.t("Квест выполнен!"))
		if e.has("lootbox"):
			GameManager.player_data.lootboxes = GameManager.lootbox_count() + int(e.lootbox)
			GameManager.player_changed.emit()
			msgs.append(Loc.t("Получен сундук с картой"))
		if e.has("world"):
			pending_world.append(e.duplicate())
	return msgs
