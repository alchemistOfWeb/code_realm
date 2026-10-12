class_name CombatState
extends RefCounted
## Логика карточного боя (без UI). Упрощённый Magic с UX Hearthstone.
##
## Ресурсы: кристаллы (макс. +1 каждый ход до 10) — карты; мана — руны (не восполняется);
## выносливость — оружие (+2 за ход). Существа атакуют со следующего хода (кроме тех, кого
## «разбудил» эффект), Taunt обязывает атаковать его первым.
##
## UI вызывает действия (play_card, weapon_attack, use_rune, creature_attack, end_turn) и
## читает очередь событий `events` (log/damage/heal/summon/death/play/turn/...) для анимаций.
##
## Цель (target) — словарь {"side": "player"|"enemy", "kind": "hero"|"creature", "uid": int}.

const TOKEN_CARD := {"id": "_gear_minion", "name": "Шестерёнка-прислужник", "type": "creature", "attack": 1, "defense": 2,
	"icon": "cog", "art_color": "#B87333", "rarity": "common", "crystal_cost": 0, "effect": {}}

class Fighter:
	var is_player := true
	var name := ""
	var hp := 20
	var max_hp := 20
	var attack := 0                # атака «героя» (для врага)
	var shield := 0
	var crystals := 0
	var max_crystals := 0
	var crystal_bonus := 0         # max_crystal_bonus (навсегда в этом бою)
	var mana := 0
	var max_mana := 0
	var stamina := 0
	var max_stamina := 0
	var deck: Array = []           # card dicts
	var hand: Array = []
	var discard: Array = []
	var board: Array = []          # creature dicts
	var artifacts: Array = []      # card dicts
	var flags := {}                # временные эффекты


var player := Fighter.new()
var enemy := Fighter.new()
var enemy_data: Dictionary = {}
var attributes: Dictionary = {}
## Атаки оружием, доступные герою (по экипировке): ["sword"], ["bow", "dagger"], ["fists"]...
var weapons: Array = ["fists"]
var damage_bonus := 0
## Расход выносливости надетого оружия (вид → очки), иначе базовый из XPCalculator.WEAPONS.
var weapon_costs: Dictionary = {}
var dodge_bonus := 0
var turn := 0
var over := false
var winner := ""                   # "player" | "enemy"
var events: Array = []             # очередь событий для UI
var pending_discover: Array = []   # карты на выбор (эффект discover)
var _uid := 0


# ---------------------------------------------------------------- Старт

func start(enemy_info: Dictionary, deck_ids: Array, player_stats: Dictionary) -> void:
	enemy_data = enemy_info
	attributes = player_stats.get("attributes", {})
	player.is_player = true
	player.name = Loc.t("Ты")
	player.max_hp = player_stats.get("max_hp", 20)
	player.hp = clampi(player_stats.get("hp", player.max_hp), 1, player.max_hp)
	player.max_mana = attributes.get("max_mana", 1)
	player.mana = player.max_mana
	player.max_stamina = attributes.get("max_stamina", 10)
	player.stamina = player.max_stamina
	weapons = player_stats.get("weapons", ["fists"]).duplicate()
	if weapons.is_empty():
		weapons = ["fists"]
	weapon_costs = player_stats.get("weapon_costs", {})
	damage_bonus = int(player_stats.get("damage_bonus", 0))
	dodge_bonus = int(player_stats.get("dodge_bonus", 0))
	player.shield = int(player_stats.get("armor", 0))
	for id in deck_ids:
		var c := CardDatabase.get_card(id)
		if not c.is_empty():
			player.deck.append(c.duplicate(true))
	player.deck.shuffle()

	enemy.is_player = false
	enemy.name = enemy_info.get("name", Loc.t("Враг"))
	enemy.max_hp = enemy_info.get("hp", 15)
	enemy.hp = enemy.max_hp
	enemy.attack = enemy_info.get("attack", 3)
	for i in 3:
		for id in enemy_info.get("cards", []):
			var c := CardDatabase.get_card(id)
			if not c.is_empty():
				enemy.deck.append(c.duplicate(true))
	enemy.deck.shuffle()

	_draw(player, XPCalculator.START_HAND)
	_draw(enemy, 2)
	_log(Loc.t("Бой начался: %s (%d HP, атака %d)") % [enemy.name, enemy.hp, enemy.attack])
	_start_turn(player)


# ---------------------------------------------------------------- Запросы для UI

func card_cost(side: Fighter, card: Dictionary) -> int:
	var cost: int = card.get("crystal_cost", 0)
	if side.flags.get("next_free", false):
		return 0
	cost -= side.flags.get("turn_discount", 0)
	if card.get("type") == "spell":
		cost -= side.flags.get("next_spell_discount", 0)
		for a in side.artifacts:
			cost -= a.effect.get("spell_discount", 0)
	if side.flags.get("cards_played", 0) == 0:
		for a in side.artifacts:
			cost -= a.effect.get("first_card_discount", 0)
	return maxi(0, cost)


## Тип цели карты: "" | "enemy_any" | "enemy_creature" | "friendly_creature"
static func target_type(card: Dictionary) -> String:
	if card.get("type") != "spell":
		return ""
	var e: Dictionary = card.get("effect", {})
	if e.has("damage") or e.has("execute_below") or e.has("damage_random") or e.has("damage_per_creature"):
		return "enemy_any"
	if e.has("freeze_enemy_creature") or e.has("control_enemy_creature"):
		return "enemy_creature"
	if e.has("buff_attack"):
		return "friendly_creature"
	return ""


func can_play(index: int) -> Dictionary:
	if over or index < 0 or index >= player.hand.size():
		return {"ok": false, "reason": ""}
	var card: Dictionary = player.hand[index]
	if card_cost(player, card) > player.crystals:
		return {"ok": false, "reason": Loc.t("Недостаточно кристаллов")}
	if card.get("type") == "creature" and player.board.size() >= XPCalculator.BOARD_MAX:
		return {"ok": false, "reason": Loc.t("На поле нет места")}
	var tt := target_type(card)
	if tt == "friendly_creature" and player.board.is_empty():
		return {"ok": false, "reason": Loc.t("Нужно своё существо на поле")}
	if tt == "enemy_creature" and enemy.board.is_empty():
		return {"ok": false, "reason": Loc.t("У врага нет существ")}
	var ctrl = card.get("effect", {}).get("control_enemy_creature")
	if ctrl is Dictionary and enemy.board.filter(func(c): return c.attack <= ctrl.get("max_attack", 99)).is_empty():
		return {"ok": false, "reason": Loc.t("Нет подходящего существа врага")}
	return {"ok": true, "reason": ""}


func weapon_damage(weapon_id: String) -> int:
	var w: Dictionary = XPCalculator.WEAPONS[weapon_id]
	return w.base + w.per * int(attributes.get(w.attr, 1)) + damage_bonus


func weapon_cost(weapon_id: String) -> int:
	if player.flags.get("free_weapon", 0) > 0:
		return 0
	return int(weapon_costs.get(weapon_id, XPCalculator.WEAPONS[weapon_id].cost))


func can_attack_with(c: Dictionary) -> bool:
	return not over and c.get("can_attack", false) and c.get("frozen", 0) <= 0 and c.attack > 0


## Допустимые цели для атаки по стороне-жертве (учитывает Taunt).
func valid_attack_targets(victim: Fighter, ignore_taunt: bool = false) -> Array:
	var taunts := victim.board.filter(func(c): return c.get("taunt", false))
	var targets: Array = []
	if not taunts.is_empty() and not ignore_taunt:
		for c in taunts:
			targets.append(_ref(victim, c))
		return targets
	targets.append(_hero_ref(victim))
	for c in victim.board:
		targets.append(_ref(victim, c))
	return targets


func is_valid_target(target: Dictionary, type: String) -> bool:
	match type:
		"enemy_any":
			return target.get("side") == "enemy"
		"enemy_creature":
			return target.get("side") == "enemy" and target.get("kind") == "creature"
		"friendly_creature":
			return target.get("side") == "player" and target.get("kind") == "creature"
	return false


func enemy_intent() -> String:
	if enemy.flags.get("stunned", 0) > 0:
		return Loc.t("Оглушён — пропустит атаку")
	var times := 2 if enemy_data.get("special", "") == "double_attack" else 1
	var text := Loc.t("Атакует: %d урона%s") % [enemy.attack, " ×2" if times == 2 else ""]
	if _has_effect(player, "reveal_enemy_hand") and not enemy.hand.is_empty():
		var affordable := enemy.hand.filter(func(c): return card_cost(enemy, c) <= mini(enemy.max_crystals + 1, XPCalculator.MAX_CRYSTALS))
		if not affordable.is_empty():
			text += Loc.t(" · готовит «%s»") % affordable[0].name
	return text


# ---------------------------------------------------------------- Действия игрока

func play_card(index: int, target: Dictionary = {}) -> bool:
	var check := can_play(index)
	if not check.ok:
		_log(check.reason)
		return false
	var card: Dictionary = player.hand[index]
	var tt := target_type(card)
	if tt != "" and not is_valid_target(target, tt):
		_log(Loc.t("Нужно выбрать цель"))
		return false
	return _play(player, enemy, index, target)


func weapon_attack(weapon_id: String, target: Dictionary) -> bool:
	if over or not XPCalculator.WEAPONS.has(weapon_id) or not weapon_id in weapons:
		return false
	var cost := weapon_cost(weapon_id)
	if player.stamina < cost:
		_log(Loc.t("Недостаточно выносливости"))
		return false
	var allowed := valid_attack_targets(enemy, weapon_id == "bow")
	if not _ref_in(target, allowed):
		_log(Loc.t("Сначала нужно победить существо с Taunt"))
		return false
	player.stamina -= cost
	if player.flags.get("free_weapon", 0) > 0:
		player.flags.free_weapon -= 1
	var dmg := weapon_damage(weapon_id)
	_push("weapon", {"weapon": weapon_id, "target": target})
	_log(Loc.t("%s: %d урона") % [Loc.t(XPCalculator.WEAPONS[weapon_id].name), dmg])
	if weapon_id == "hammer":
		_break_shields(target)
	_damage_target(player, target, dmg)
	if weapon_id == "spear" and target.get("kind") == "creature" and not over:
		_log(Loc.t("Копьё задевает героя: 1 урон"))
		_damage_hero(enemy, 1, false)
	_check_over()
	return true


## Молот: сбить щит героя или божественный щит существа перед ударом.
func _break_shields(target: Dictionary) -> void:
	var victim := player if target.get("side") == "player" else enemy
	if target.get("kind") == "hero":
		if victim.shield > 0:
			_log(Loc.t("Молот сбивает щит (%d)") % victim.shield)
			victim.shield = 0
			_push("block", {"target": target, "amount": 0})
	else:
		var c := _find_creature(victim, target.get("uid", -1))
		if not c.is_empty() and c.get("divine_shield", false):
			c.divine_shield = false
			_log(Loc.t("Молот разбивает божественный щит"))


func use_rune(rune_id: String, target: Dictionary = {}) -> bool:
	if over or not XPCalculator.RUNES.has(rune_id):
		return false
	var rune: Dictionary = XPCalculator.RUNES[rune_id]
	if player.mana < rune.cost:
		_log(Loc.t("Недостаточно маны"))
		return false
	if rune.has("damage") and target.get("side") != "enemy":
		_log(Loc.t("Выбери вражескую цель"))
		return false
	player.mana -= rune.cost
	_push("rune", {"rune": rune_id, "target": target})
	_log(rune.name)
	if rune.has("damage"):
		_damage_target(player, target, rune.damage)
	if rune.has("shield"):
		player.shield += rune.shield
		_push("shield", {"target": _hero_ref(player), "amount": rune.shield})
	if rune.has("heal"):
		_heal(player, rune.heal)
	_check_over()
	return true


func creature_attack(uid: int, target: Dictionary) -> bool:
	var c := _find_creature(player, uid)
	if c.is_empty() or not can_attack_with(c):
		return false
	if not _ref_in(target, valid_attack_targets(enemy)):
		_log(Loc.t("Сначала нужно атаковать существо с Taunt"))
		return false
	_creature_strike(player, enemy, c, target)
	c.can_attack = false
	_check_over()
	return true


func choose_discover(i: int) -> void:
	if i < 0 or i >= pending_discover.size():
		return
	var card: Dictionary = pending_discover[i]
	pending_discover.remove_at(i)
	_add_to_hand(player, card)
	for rest in pending_discover:
		player.deck.push_front(rest)
	pending_discover.clear()


func end_turn() -> void:
	if over:
		return
	_end_turn(player, enemy)
	if over:
		return
	_enemy_turn()
	if over:
		return
	_start_turn(player)


# ---------------------------------------------------------------- Ход

func _start_turn(side: Fighter) -> void:
	turn += 1 if side.is_player else 0
	side.flags.erase("turn_discount")
	side.flags.erase("next_spell_discount")
	side.flags.erase("next_free")
	side.flags["cards_played"] = 0
	side.max_crystals = mini(side.max_crystals + 1, XPCalculator.MAX_CRYSTALS)
	side.crystals = mini(side.max_crystals + side.crystal_bonus, XPCalculator.MAX_CRYSTALS + side.crystal_bonus)
	for a in side.artifacts:
		var e: Dictionary = a.effect
		side.crystals += e.get("passive_crystal_regen", 0)
		if e.has("passive_stamina"):
			side.stamina = mini(side.stamina + e.passive_stamina, side.max_stamina)
		if e.has("passive_draw"):
			var every: int = e.get("every", 1)
			if turn % every == 0:
				_draw(side, e.passive_draw)
		if e.has("passive_heal"):
			_heal(side, e.passive_heal)
		if e.has("passive_shield"):
			side.shield += e.passive_shield
			_push("shield", {"target": _hero_ref(side), "amount": e.passive_shield})
		if e.has("passive_damage"):
			var other := enemy if side.is_player else player
			_log(Loc.t("%s: %d урона") % [a.get("name", ""), e.passive_damage])
			_damage_hero(other, e.passive_damage, false)
	if side.is_player:
		side.stamina = mini(side.stamina + XPCalculator.STAMINA_REGEN, side.max_stamina)
		var need: int = XPCalculator.HAND_TARGET - side.hand.size()
		if need > 0:
			_draw(side, need)
		_push("turn", {"side": "player", "turn": turn})
		_log(Loc.t("— Твой ход %d —") % turn)
	else:
		_draw(side, 1)
	for c in side.board:
		c.can_attack = c.get("frozen", 0) <= 0
		c.temp_attack = 0
		c.attack = _creature_attack_value(side, c)


func _end_turn(side: Fighter, other: Fighter) -> void:
	# Эффекты конца хода
	for c in side.board.duplicate():
		var n: int = c.get("extra_attack_end", 0)
		for i in n:
			var targets := valid_attack_targets(other)
			if targets.is_empty() or c.attack <= 0:
				break
			_log(Loc.t("%s атакует в конце хода") % c.name)
			_creature_strike(side, other, c, targets.pick_random())
			if _check_over():
				return
	for c in side.board:
		if c.get("frozen", 0) > 0:
			c.frozen -= 1
		c.temp_attack = 0
		c.attack = _creature_attack_value(side, c)
	# Возврат взятых под контроль существ
	for c in side.board.duplicate():
		if c.get("controlled", 0) > 0:
			c.controlled -= 1
			if c.controlled <= 0:
				side.board.erase(c)
				c.erase("controlled")
				c.can_attack = false
				other.board.append(c)
				_log(Loc.t("%s возвращается к врагу") % c.name)


func _enemy_turn() -> void:
	_push("turn", {"side": "enemy"})
	_log(Loc.t("— Ход врага —"))
	var special: String = enemy_data.get("special", "")
	_start_turn(enemy)
	# Особенности врага
	match special:
		"steal_card":
			if not player.hand.is_empty():
				var stolen: Dictionary = player.hand.pick_random()
				player.hand.erase(stolen)
				player.discard.append(stolen)
				_log(Loc.t("%s крадёт карту «%s»") % [enemy.name, stolen.name])
				_push("steal", {"card": stolen.name})
		"grow":
			enemy.attack += 1
			_log(Loc.t("%s разрастается: атака %d") % [enemy.name, enemy.attack])
		"regen":
			_heal(enemy, 2)
		"summon":
			if turn % 2 == 0 and enemy.board.size() < XPCalculator.BOARD_MAX:
				_summon(enemy, TOKEN_CARD.duplicate(true))
	# Карты врага: самые дорогие из доступных
	var safety := 10
	while safety > 0:
		safety -= 1
		var best := -1
		var best_cost := -1
		for i in enemy.hand.size():
			var c: Dictionary = enemy.hand[i]
			var cost := card_cost(enemy, c)
			if cost <= enemy.crystals and cost > best_cost:
				if c.type == "creature" and enemy.board.size() >= XPCalculator.BOARD_MAX:
					continue
				best = i
				best_cost = cost
		if best < 0:
			break
		_play(enemy, player, best, _ai_target(enemy.hand[best]))
		if _check_over():
			return
	# Атаки существ врага
	var attacks_left: int = player.flags.get("limit_enemy_attacks", 99)
	for c in enemy.board.duplicate():
		if attacks_left <= 0 or not can_attack_with(c) or not enemy.board.has(c):
			continue
		var target := _ai_attack_target(c.attack, c.defense)
		_creature_strike(enemy, player, c, target)
		c.can_attack = false
		attacks_left -= 1
		if _check_over():
			return
	# Атака «героя» врага
	var times := 2 if special == "double_attack" else 1
	for i in times:
		if attacks_left <= 0:
			break
		if enemy.flags.get("stunned", 0) > 0:
			enemy.flags.stunned -= 1
			_log(Loc.t("%s оглушён и пропускает атаку") % enemy.name)
			break
		if enemy.flags.get("isolated", 0) > 0:
			_log(Loc.t("%s изолирован и не может атаковать") % enemy.name)
			break
		var target := _ai_attack_target(enemy.attack, 999)
		_push("enemy_attack", {"target": target})
		_damage_target(enemy, target, enemy.attack)
		attacks_left -= 1
		if _check_over():
			return
	if enemy.flags.get("isolated", 0) > 0:
		enemy.flags.isolated -= 1
	player.flags.erase("limit_enemy_attacks")
	if player.flags.get("checkpoint", 0) > 0:
		player.flags.checkpoint -= 1
	_end_turn(enemy, player)


## Цель для атаки ИИ: Taunt → выгодный размен → игрок.
func _ai_attack_target(atk: int, own_def: int) -> Dictionary:
	var taunts := player.board.filter(func(c): return c.get("taunt", false))
	if not taunts.is_empty():
		taunts.sort_custom(func(a, b): return a.defense < b.defense)
		return _ref(player, taunts[0])
	var killable := player.board.filter(func(c): return c.defense <= atk and c.attack < own_def and c.attack >= 2)
	if not killable.is_empty():
		killable.sort_custom(func(a, b): return a.attack > b.attack)
		return _ref(player, killable[0])
	return _hero_ref(player)


func _ai_target(card: Dictionary) -> Dictionary:
	match target_type(card):
		"enemy_any":
			return _hero_ref(player)
		"enemy_creature":
			if player.board.is_empty():
				return {}
			var sorted := player.board.duplicate()
			sorted.sort_custom(func(a, b): return a.attack > b.attack)
			return _ref(player, sorted[0])
		"friendly_creature":
			return {} if enemy.board.is_empty() else _ref(enemy, enemy.board[0])
	return {}


# ---------------------------------------------------------------- Розыгрыш и эффекты

func _play(side: Fighter, other: Fighter, index: int, target: Dictionary) -> bool:
	var card: Dictionary = side.hand[index]
	var cost := card_cost(side, card)
	if card.type == "creature" and side.board.size() >= XPCalculator.BOARD_MAX:
		return false
	if target_type(card) == "friendly_creature" and side.board.is_empty():
		side.hand.remove_at(index)
		side.discard.append(card)
		return false
	side.crystals -= cost
	side.hand.remove_at(index)
	side.flags["cards_played"] = side.flags.get("cards_played", 0) + 1
	if side.flags.get("next_free", false):
		side.flags.erase("next_free")
	if card.type == "spell":
		side.flags.erase("next_spell_discount")
	_push("play", {"side": "player" if side.is_player else "enemy", "card": card.id, "name": card.name})
	_log("%s: «%s»" % [side.name, card.name])
	match card.type:
		"creature":
			_summon(side, card)
		"artifact":
			side.artifacts.append(card)
			_push("artifact", {"side": "player" if side.is_player else "enemy", "card": card.id})
			_apply_effect(side, other, card, target)
		_:
			_apply_effect(side, other, card, target)
			side.discard.append(card)
			var spells: Array = side.flags.get("spells_played", [])
			spells.append(card)
			side.flags["spells_played"] = spells
	_check_over()
	return true


func _apply_effect(side: Fighter, other: Fighter, card: Dictionary, target: Dictionary) -> void:
	var e: Dictionary = card.get("effect", {})
	var bonus := _boss_bonus(side, target)
	if e.has("damage"):
		_damage_target(side, target, e.damage + bonus)
	if e.has("damage_random"):
		var r: Array = e.damage_random
		var dmg := randi_range(r[0], r[1])
		_damage_target(side, target, dmg + bonus)
	if e.has("damage_per_creature"):
		_damage_target(side, target, e.damage_per_creature * side.board.size() + bonus)
	if e.has("execute_below"):
		var t := _resolve(target)
		if not t.is_empty() and t.hp < e.execute_below:
			_log(Loc.t("Добивание!"))
			_damage_target(side, target, 999)
	if e.has("damage_all"):
		_damage_target(side, _hero_ref(other), e.damage_all)
		for c in other.board.duplicate():
			_damage_target(side, _ref(other, c), e.damage_all)
	if e.has("damage_split"):
		var targets: Array = [_hero_ref(other)]
		for c in other.board:
			targets.append(_ref(other, c))
		var per: int = e.damage_split / targets.size()
		var rest: int = e.damage_split % targets.size()
		for i in targets.size():
			var amount := per + (rest if i == 0 else 0)
			if amount > 0:
				_damage_target(side, targets[i], amount)
	if e.has("draw"):
		_draw(side, e.draw)
	if e.has("discover") and side.is_player:
		var n: int = mini(e.discover, side.deck.size())
		pending_discover = side.deck.slice(0, n)
		for i in n:
			side.deck.pop_front()
		if pending_discover.is_empty():
			_reshuffle(side)
	if e.has("next_spell_discount"):
		side.flags["next_spell_discount"] = side.flags.get("next_spell_discount", 0) + e.next_spell_discount
	if e.has("turn_discount"):
		side.flags["turn_discount"] = side.flags.get("turn_discount", 0) + e.turn_discount
	if e.get("next_free", false) or e.has("extra_play"):
		side.flags["next_free"] = true
	if e.has("shield"):
		side.shield += e.shield
		_push("shield", {"target": _hero_ref(side), "amount": e.shield})
	if e.has("heal"):
		_heal(side, e.heal)
	if e.has("self_damage"):
		_damage_hero(side, e.self_damage, true)
	if e.has("buff_attack"):
		var c := _creature_from_ref(target)
		if not c.is_empty():
			c.temp_attack = c.get("temp_attack", 0) + e.buff_attack
			c.attack = _creature_attack_value(side, c)
			_log(Loc.t("%s: атака %d") % [c.name, c.attack])
	if e.has("set_all_attack"):
		for s in [side, other]:
			for c in s.board:
				c.base_attack = e.set_all_attack
				c.temp_attack = 0
				c.attack = _creature_attack_value(s, c)
	if e.has("stun_enemy"):
		other.flags["stunned"] = other.flags.get("stunned", 0) + e.stun_enemy
		_log(Loc.t("%s оглушён") % other.name)
	if e.has("freeze_enemy_creature"):
		var c := _creature_from_ref(target)
		if not c.is_empty():
			c.frozen = e.freeze_enemy_creature
			c.can_attack = false
			_log(Loc.t("%s заморожен на %d хода") % [c.name, c.frozen])
	if e.has("limit_enemy_attacks"):
		side.flags["limit_enemy_attacks"] = e.limit_enemy_attacks
	if e.has("control_enemy_creature"):
		var c := _creature_from_ref(target)
		var spec: Dictionary = e.control_enemy_creature
		if not c.is_empty() and c.attack <= spec.get("max_attack", 99) and side.board.size() < XPCalculator.BOARD_MAX:
			other.board.erase(c)
			c.controlled = spec.get("duration", 1)
			c.can_attack = true
			side.board.append(c)
			_log(Loc.t("%s переходит под твой контроль") % c.name)
			_push("control", {"uid": c.uid})
	if e.get("checkpoint", false):
		side.flags["checkpoint"] = 1
		_log(Loc.t("Чекпоинт сохранён"))
	if e.has("free_weapon_attack"):
		side.flags["free_weapon"] = side.flags.get("free_weapon", 0) + e.free_weapon_attack
	if e.has("return_spells"):
		var spells: Array = side.flags.get("spells_played", []).filter(func(s): return s.id != card.id)
		var n: int = mini(e.return_spells, spells.size())
		for i in n:
			var s: Dictionary = spells[spells.size() - 1 - i]
			side.discard.erase(s)
			_add_to_hand(side, s)
		_log(Loc.t("Возвращено заклинаний: %d") % n)
	if e.has("max_crystal_bonus"):
		side.crystal_bonus += e.max_crystal_bonus
	if e.has("isolate_enemy"):
		if other.board.is_empty():
			other.flags["isolated"] = other.flags.get("isolated", 0) + e.isolate_enemy
			_log(Loc.t("%s изолирован") % other.name)
		else:
			var strongest: Dictionary = other.board[0]
			for c in other.board:
				if c.attack > strongest.attack:
					strongest = c
			strongest.frozen = e.isolate_enemy
			strongest.can_attack = false
			_log(Loc.t("%s изолирован") % strongest.name)
	if e.has("aura_attack") or e.has("hand_size"):
		for c in side.board:
			c.attack = _creature_attack_value(side, c)


func _summon(side: Fighter, card: Dictionary, as_token: bool = false) -> Dictionary:
	if side.board.size() >= XPCalculator.BOARD_MAX:
		return {}
	_uid += 1
	var e: Dictionary = card.get("effect", {})
	var c := {
		"uid": _uid, "card_id": card.get("id", ""), "name": card.get("name", "?"), "icon": card.get("icon", "cog"),
		"art_color": card.get("art_color", "#7B68EE"), "rarity": card.get("rarity", "common"),
		"base_attack": card.get("attack", 1), "attack": card.get("attack", 1),
		"defense": card.get("defense", 1), "max_defense": card.get("defense", 1),
		"taunt": e.get("taunt", false), "divine_shield": e.get("divine_shield", false),
		"resurrect": e.get("on_death_resurrect", 0), "multi_attack": e.get("multi_attack", 1),
		"extra_attack_end": e.get("extra_attack_end_turn", 0), "can_attack": false, "frozen": 0, "temp_attack": 0,
		"card": card,
	}
	if e.get("copy_enemy_attack", false):
		var other := enemy if side.is_player else player
		var best := 0
		for oc in other.board:
			best = maxi(best, oc.attack)
		if best > 0:
			c.base_attack = best
	side.board.append(c)
	c.attack = _creature_attack_value(side, c)
	_push("summon", {"side": "player" if side.is_player else "enemy", "uid": c.uid})
	if not as_token:
		var other := enemy if side.is_player else player
		# Эффекты существ «при розыгрыше»
		var on_play := {}
		for key in ["isolate_enemy", "heal", "max_crystal_bonus", "draw", "shield", "damage_all", "damage_split",
				"stun_enemy", "free_weapon_attack", "self_damage", "next_spell_discount"]:
			if e.has(key):
				on_play[key] = e[key]
		if not on_play.is_empty():
			_apply_effect(side, other, {"id": card.get("id", ""), "effect": on_play}, {})
		if e.has("summon_copies"):
			var sc: Dictionary = e.summon_copies
			for i in sc.get("count", 0):
				var token := card.duplicate(true)
				token.attack = sc.get("attack", 1)
				token.defense = sc.get("defense", 1)
				token.effect = {}
				_summon(side, token, true)
	return c


func _creature_attack_value(side: Fighter, c: Dictionary) -> int:
	var aura := 0
	for a in side.artifacts:
		aura += a.effect.get("aura_attack", 0)
	return maxi(0, c.base_attack + c.get("temp_attack", 0) + aura)


func _creature_strike(side: Fighter, other: Fighter, c: Dictionary, target: Dictionary) -> void:
	var targets: Array = [target]
	var extra: int = c.get("multi_attack", 1) - 1
	if extra > 0:
		var pool := valid_attack_targets(other).filter(func(t): return not _same_ref(t, target))
		pool.shuffle()
		targets.append_array(pool.slice(0, extra))
	for t in targets:
		_push("strike", {"side": "player" if side.is_player else "enemy", "uid": c.uid, "target": t})
		var victim := _creature_from_ref(t)
		_damage_target(side, t, c.attack)
		# Ответный удар существа
		if not victim.is_empty() and victim.attack > 0 and side.board.has(c):
			_damage_target(other, _ref(side, c), victim.attack)


func _damage_target(source: Fighter, target: Dictionary, amount: int) -> void:
	if target.is_empty() or amount <= 0:
		return
	var victim := player if target.side == "player" else enemy
	if target.kind == "hero":
		_damage_hero(victim, amount, false)
	else:
		var c := _find_creature(victim, target.get("uid", -1))
		if c.is_empty():
			return
		if c.get("divine_shield", false):
			c.divine_shield = false
			_log(Loc.t("%s: божественный щит поглотил удар") % c.name)
			_push("block", {"target": target})
			return
		c.defense -= amount
		_push("damage", {"target": target, "amount": amount})
		if c.defense <= 0:
			_creature_death(victim, c)


func _damage_hero(side: Fighter, amount: int, self_inflicted: bool) -> void:
	var ref := _hero_ref(side)
	if not side.is_player and enemy_data.get("special", "") == "armor":
		amount = maxi(0, amount - 1)
	if side.is_player and not self_inflicted:
		var dodge := XPCalculator.dodge_chance(attributes.get("agility", 0), dodge_bonus)
		if randf() * 100.0 < dodge:
			_log(Loc.t("Уклонение!"))
			_push("dodge", {"target": ref})
			return
	if side.shield > 0:
		var absorbed := mini(side.shield, amount)
		side.shield -= absorbed
		amount -= absorbed
		_push("block", {"target": ref, "amount": absorbed})
	if amount <= 0:
		return
	side.hp -= amount
	if side.is_player and side.flags.get("checkpoint", 0) > 0 and side.hp < 1:
		side.hp = 1
		_log(Loc.t("Чекпоинт удержал тебя на 1 HP"))
	_push("damage", {"target": ref, "amount": amount})


func _heal(side: Fighter, amount: int) -> void:
	var before := side.hp
	side.hp = mini(side.max_hp, side.hp + amount)
	if side.hp > before:
		_push("heal", {"target": _hero_ref(side), "amount": side.hp - before})
		_log("%s: +%d HP" % [side.name, side.hp - before])


func _creature_death(side: Fighter, c: Dictionary) -> void:
	if c.get("resurrect", 0) > 0:
		c.resurrect -= 1
		c.defense = 1
		_log(Loc.t("%s возрождается с 1 HP") % c.name)
		_push("resurrect", {"uid": c.uid})
		return
	side.board.erase(c)
	if c.get("card") is Dictionary and not c.card.get("id", "").begins_with("_"):
		var owner := side
		if c.has("controlled"):
			owner = enemy if side.is_player else player
		owner.discard.append(c.card)
	_push("death", {"side": "player" if side.is_player else "enemy", "uid": c.uid, "name": c.name})
	_log(Loc.t("%s уничтожен") % c.name)


# ---------------------------------------------------------------- Колода

func _draw(side: Fighter, n: int) -> void:
	for i in n:
		if side.deck.is_empty():
			_reshuffle(side)
			if side.deck.is_empty():
				return
		var card: Dictionary = side.deck.pop_front()
		_add_to_hand(side, card)


func _add_to_hand(side: Fighter, card: Dictionary) -> void:
	var limit := XPCalculator.HAND_MAX
	for a in side.artifacts:
		limit += a.effect.get("hand_size", 0)
	if side.hand.size() >= limit:
		side.discard.append(card)
		if side.is_player:
			_log(Loc.t("Рука полна: «%s» сгорает") % card.name)
		return
	side.hand.append(card)
	if side.is_player:
		_push("draw", {"card": card.id})


func _reshuffle(side: Fighter) -> void:
	if side.discard.is_empty():
		return
	side.deck = side.discard.duplicate()
	side.discard.clear()
	side.deck.shuffle()
	if side.is_player:
		_log(Loc.t("Колода перемешана"))


# ---------------------------------------------------------------- Конец боя

func _check_over() -> bool:
	if over:
		return true
	if enemy.hp <= 0:
		over = true
		winner = "player"
		_log(Loc.t("Победа!"))
		_push("over", {"winner": "player"})
	elif player.hp <= 0:
		over = true
		winner = "enemy"
		player.hp = 0
		_log(Loc.t("Поражение…"))
		_push("over", {"winner": "enemy"})
	return over


# ---------------------------------------------------------------- Ссылки и утилиты

func _hero_ref(side: Fighter) -> Dictionary:
	return {"side": "player" if side.is_player else "enemy", "kind": "hero", "uid": -1}


func _ref(side: Fighter, c: Dictionary) -> Dictionary:
	return {"side": "player" if side.is_player else "enemy", "kind": "creature", "uid": c.uid}


static func _same_ref(a: Dictionary, b: Dictionary) -> bool:
	return a.get("side") == b.get("side") and a.get("kind") == b.get("kind") and a.get("uid", -1) == b.get("uid", -1)


func _ref_in(ref: Dictionary, list: Array) -> bool:
	for r in list:
		if _same_ref(r, ref):
			return true
	return false


func _find_creature(side: Fighter, uid: int) -> Dictionary:
	for c in side.board:
		if c.uid == uid:
			return c
	return {}


func _creature_from_ref(ref: Dictionary) -> Dictionary:
	if ref.get("kind") != "creature":
		return {}
	return _find_creature(player if ref.side == "player" else enemy, ref.get("uid", -1))


## HP цели (для execute_below).
func _resolve(ref: Dictionary) -> Dictionary:
	if ref.is_empty():
		return {}
	var side := player if ref.side == "player" else enemy
	if ref.kind == "hero":
		return {"hp": side.hp}
	var c := _find_creature(side, ref.get("uid", -1))
	return {} if c.is_empty() else {"hp": c.defense}


func _boss_bonus(side: Fighter, target: Dictionary) -> int:
	if not side.is_player or target.get("side") != "enemy" or target.get("kind") != "hero":
		return 0
	if not (enemy_data.get("is_miniboss", false) or enemy_data.get("is_boss", false)):
		return 0
	var bonus := 0
	for a in side.artifacts:
		bonus += a.effect.get("boss_damage_bonus", 0)
	return bonus


func _has_effect(side: Fighter, key: String) -> bool:
	for c in side.board:
		if c.card.get("effect", {}).get(key, 0):
			return true
	for a in side.artifacts:
		if a.effect.get(key, 0):
			return true
	return false


func _push(kind: String, data: Dictionary) -> void:
	data["kind"] = kind
	events.append(data)


func _log(text: String) -> void:
	_push("log", {"text": text})


## Забрать накопленные события (UI вызывает после каждого действия).
func take_events() -> Array:
	var e := events
	events = []
	return e
