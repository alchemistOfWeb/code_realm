# Добавляет в data/cards_catalog.json 100 новых карт (по 20 на специализацию).
# Описания на русском и английском собираются из эффектов — текст всегда совпадает с механикой.
# Запуск из папки psystem: python tools/gen_cards.py   (повторный запуск обновляет только эти карты)
import json, os

PATH = os.path.join(os.path.dirname(__file__), "..", "data", "cards_catalog.json")


def plural_ru(n, one, few, many):
    m10, m100 = n % 10, n % 100
    if m10 == 1 and m100 != 11:
        return one
    if 2 <= m10 <= 4 and not 12 <= m100 <= 14:
        return few
    return many


def s_en(n, word):
    return word if n == 1 else word + "s"


def describe(card):
    e = card.get("effect", {})
    ru, en = [], []
    creature = card["type"] == "creature"
    # Ключевые слова существ
    if e.get("taunt"):
        ru.append("Taunt."); en.append("Taunt.")
    if e.get("divine_shield"):
        ru.append("Божественный щит."); en.append("Divine Shield.")
    if "multi_attack" in e:
        n = e["multi_attack"]
        ru.append(f"Атакует {n} {plural_ru(n, 'раз', 'раза', 'раз')} за ход."); en.append(f"Attacks {n} times per turn.")
    if "extra_attack_end_turn" in e:
        ru.append("В конце твоего хода атакует ещё раз."); en.append("At the end of your turn, attacks again.")
    if "on_death_resurrect" in e:
        ru.append("При гибели возрождается."); en.append("Resurrects once on death.")
    if e.get("copy_enemy_attack"):
        ru.append("Копирует атаку сильнейшего существа врага."); en.append("Copies the attack of the enemy's strongest creature.")
    if "summon_copies" in e:
        sc = e["summon_copies"]
        ru.append(f"Призывает {sc['count']} {plural_ru(sc['count'], 'копию', 'копии', 'копий')} {sc['attack']}/{sc['defense']}.")
        en.append(f"Summons {sc['count']} {'copy' if sc['count'] == 1 else 'copies'} {sc['attack']}/{sc['defense']}.")
    act_ru, act_en = [], []
    if "damage" in e:
        n = e["damage"]; act_ru.append(f"наносит {n} урона"); act_en.append(f"deal {n} damage")
    if "damage_random" in e:
        a, b = e["damage_random"]; act_ru.append(f"наносит от {a} до {b} урона"); act_en.append(f"deal {a}–{b} damage")
    if "damage_per_creature" in e:
        n = e["damage_per_creature"]; act_ru.append(f"наносит {n} урона за каждое твоё существо"); act_en.append(f"deal {n} damage per friendly creature")
    if "execute_below" in e:
        n = e["execute_below"]; act_ru.append(f"добивает цель с HP меньше {n}"); act_en.append(f"destroy a target with less than {n} HP")
    if "damage_all" in e:
        n = e["damage_all"]; act_ru.append(f"наносит {n} урона врагу и всем его существам"); act_en.append(f"deal {n} damage to the enemy and all their creatures")
    if "damage_split" in e:
        n = e["damage_split"]; act_ru.append(f"распределяет {n} урона между врагом и его существами"); act_en.append(f"split {n} damage among the enemy and their creatures")
    if "draw" in e:
        n = e["draw"]; act_ru.append(f"даёт взять {n} {plural_ru(n, 'карту', 'карты', 'карт')}"); act_en.append(f"draw {n} {s_en(n, 'card')}")
    if "discover" in e:
        n = e["discover"]; act_ru.append(f"показывает {n} верхних карты колоды — выбери одну"); act_en.append(f"look at the top {n} cards of your deck and take one")
    if "shield" in e:
        n = e["shield"]; act_ru.append(f"даёт +{n} щита"); act_en.append(f"gain {n} shield")
    if "heal" in e:
        n = e["heal"]; act_ru.append(f"восстанавливает {n} HP"); act_en.append(f"restore {n} HP")
    if "buff_attack" in e:
        n = e["buff_attack"]; act_ru.append(f"даёт твоему существу +{n} к атаке на этот ход"); act_en.append(f"give a friendly creature +{n} attack this turn")
    if "set_all_attack" in e:
        n = e["set_all_attack"]; act_ru.append(f"делает атаку всех существ равной {n}"); act_en.append(f"set all creatures' attack to {n}")
    if "stun_enemy" in e:
        n = e["stun_enemy"]; act_ru.append(f"оглушает врага на {n} {plural_ru(n, 'ход', 'хода', 'ходов')}"); act_en.append(f"stun the enemy for {n} {s_en(n, 'turn')}")
    if "freeze_enemy_creature" in e:
        n = e["freeze_enemy_creature"]; act_ru.append(f"замораживает существо врага на {n} {plural_ru(n, 'ход', 'хода', 'ходов')}"); act_en.append(f"freeze an enemy creature for {n} {s_en(n, 'turn')}")
    if "limit_enemy_attacks" in e:
        n = e["limit_enemy_attacks"]; act_ru.append(f"ограничивает атаки врага в этот ход до {n}"); act_en.append(f"limit the enemy to {n} {s_en(n, 'attack')} this turn")
    if "control_enemy_creature" in e:
        c = e["control_enemy_creature"]; act_ru.append(f"забирает существо врага с атакой не больше {c['max_attack']} на {c['duration']} ход"); act_en.append(f"take control of an enemy creature with {c['max_attack']} or less attack for {c['duration']} turn")
    if e.get("checkpoint"):
        act_ru.append("сохраняет чекпоинт: до конца хода врага твоё HP не опустится ниже 1"); act_en.append("set a checkpoint: your HP can't drop below 1 until the enemy's turn ends")
    if "free_weapon_attack" in e:
        n = e["free_weapon_attack"]; act_ru.append(f"делает {n} {plural_ru(n, 'атаку', 'атаки', 'атак')} оружием бесплатными"); act_en.append(f"make your next {n} weapon {s_en(n, 'attack')} free")
    if "return_spells" in e:
        n = e["return_spells"]; act_ru.append(f"возвращает в руку до {n} сыгранных заклинаний"); act_en.append(f"return up to {n} played spells to your hand")
    if "max_crystal_bonus" in e:
        n = e["max_crystal_bonus"]; act_ru.append(f"даёт +{n} к максимуму кристаллов в этом бою"); act_en.append(f"gain +{n} max crystals this battle")
    if "isolate_enemy" in e:
        act_ru.append("изолирует сильнейшее существо врага"); act_en.append("isolate the enemy's strongest creature")
    if "next_spell_discount" in e:
        n = e["next_spell_discount"]; act_ru.append(f"удешевляет следующее заклинание на {n}"); act_en.append(f"make your next spell cost {n} less")
    if "turn_discount" in e:
        n = e["turn_discount"]; act_ru.append(f"удешевляет все карты в этот ход на {n}"); act_en.append(f"make your cards cost {n} less this turn")
    if e.get("next_free") or "extra_play" in e:
        act_ru.append("делает следующую карту бесплатной"); act_en.append("make your next card free")
    if "self_damage" in e:
        n = e["self_damage"]; act_ru.append(f"ранит тебя на {n}"); act_en.append(f"deal {n} damage to yourself")
    # Пассивные эффекты артефактов
    pas_ru, pas_en = [], []
    if "passive_crystal_regen" in e:
        n = e["passive_crystal_regen"]; pas_ru.append(f"+{n} кристалл в начале хода"); pas_en.append(f"+{n} crystal at the start of your turn")
    if "passive_stamina" in e:
        n = e["passive_stamina"]; pas_ru.append(f"+{n} выносливости в начале хода"); pas_en.append(f"+{n} stamina at the start of your turn")
    if "passive_draw" in e:
        n, k = e["passive_draw"], e.get("every", 1)
        pas_ru.append(f"каждый {k}-й ход берёшь {n} {plural_ru(n, 'карту', 'карты', 'карт')}" if k > 1 else f"каждый ход берёшь {n} доп. {plural_ru(n, 'карту', 'карты', 'карт')}")
        pas_en.append(f"every {k} turns draw {n} {s_en(n, 'card')}" if k > 1 else f"draw {n} extra {s_en(n, 'card')} each turn")
    if "passive_heal" in e:
        n = e["passive_heal"]; pas_ru.append(f"+{n} HP в начале хода"); pas_en.append(f"restore {n} HP at the start of your turn")
    if "passive_shield" in e:
        n = e["passive_shield"]; pas_ru.append(f"+{n} щита в начале хода"); pas_en.append(f"gain {n} shield at the start of your turn")
    if "passive_damage" in e:
        n = e["passive_damage"]; pas_ru.append(f"{n} урона врагу в начале хода"); pas_en.append(f"deal {n} damage to the enemy at the start of your turn")
    if "spell_discount" in e:
        n = e["spell_discount"]; pas_ru.append(f"заклинания дешевле на {n}"); pas_en.append(f"your spells cost {n} less")
    if "first_card_discount" in e:
        n = e["first_card_discount"]; pas_ru.append(f"первая карта хода дешевле на {n}"); pas_en.append(f"your first card each turn costs {n} less")
    if "boss_damage_bonus" in e:
        n = e["boss_damage_bonus"]; pas_ru.append(f"+{n} урона по боссам"); pas_en.append(f"+{n} damage to bosses")
    if "aura_attack" in e:
        n = e["aura_attack"]; pas_ru.append(f"твои существа получают +{n} к атаке"); pas_en.append(f"your creatures have +{n} attack")
    if "hand_size" in e:
        n = e["hand_size"]; pas_ru.append(f"размер руки +{n}"); pas_en.append(f"+{n} max hand size")
    if e.get("reveal_enemy_hand"):
        pas_ru.append("ты видишь, какую карту готовит враг"); pas_en.append("you see the card the enemy is preparing")

    def cap(t):
        return t[0].upper() + t[1:] if t else t

    if act_ru:
        if creature:
            ru.append("При розыгрыше: " + ", ".join(act_ru) + ".")
            en.append("Battlecry: " + ", ".join(act_en) + ".")
        else:
            ru.append(cap(", ".join(act_ru)) + ".")
            en.append(cap(", ".join(act_en)) + ".")
    if pas_ru:
        ru.append(("Артефакт: " if card["type"] == "artifact" else "") + cap("; ".join(pas_ru)) + ".")
        en.append(("Artifact: " if card["type"] == "artifact" else "") + cap("; ".join(pas_en)) + ".")
    if not ru and creature:
        ru.append("Надёжный боец без особых свойств."); en.append("A reliable fighter with no special abilities.")
    return " ".join(ru), " ".join(en)


# (id, name, type, rarity, cost, effect, atk, def, icon, art, flavor_ru, flavor_en)
SPECS = {
    "python_developer": ("#3776AB", [
        ("fstring", "f-string", "spell", "common", 1, {"damage": 2}, 0, 0, "quill-ink", "#3E7BBF", "f\"{урон}\" — и враг подставлен", "f\"{damage}\" — and the enemy is interpolated"),
        ("lambda_fn", "Lambda", "spell", "common", 1, {"draw": 1, "next_spell_discount": 1}, 0, 0, "lambda", "#4A90D9", "Безымянная, но полезная", "Nameless, but useful"),
        ("virtualenv", "Virtualenv", "spell", "common", 2, {"shield": 5}, 0, 0, "bubble-field", "#5DADE2", "Твои зависимости — только твои", "Your dependencies are yours alone"),
        ("pip_install", "pip install", "spell", "common", 2, {"draw": 2, "self_damage": 1}, 0, 0, "cardboard-box", "#3776AB", "Collecting... Installing... Ouch", "Collecting... Installing... Ouch"),
        ("docstring", "Docstring", "spell", "common", 1, {"heal": 3}, 0, 0, "scroll-quill", "#6FA8DC", "\"\"\"Лечит. Возвращает надежду.\"\"\"", "\"\"\"Heals. Returns hope.\"\"\""),
        ("type_hint", "Type Hint", "spell", "common", 1, {"buff_attack": 2}, 0, 0, "pointing", "#2E86C1", "-> Победа", "-> Victory"),
        ("unit_test", "Unit Test", "creature", "common", 2, {"taunt": True}, 1, 4, "test-tubes", "#1F618D", "Ловит баги собой", "Catches bugs with its body"),
        ("assert_stmt", "assert", "spell", "common", 2, {"execute_below": 4}, 0, 0, "checked-shield", "#2874A6", "AssertionError: враг жив", "AssertionError: enemy alive"),
        ("pep8", "PEP 8", "artifact", "common", 2, {"first_card_discount": 1}, 0, 0, "pencil-ruler", "#5499C7", "79 символов — и ни одним больше", "79 characters and not one more"),
        ("pytest_fixture", "Pytest Fixture", "creature", "uncommon", 3, {"shield": 3}, 2, 3, "toolbox", "#21618C", "Готовит окружение до боя", "Sets up the environment before battle"),
        ("context_manager", "Context Manager", "spell", "uncommon", 3, {"shield": 4, "heal": 2}, 0, 0, "door-handle", "#2471A3", "with — и ресурсы закрыты", "with — and resources are closed"),
        ("iterator", "Iterator", "artifact", "uncommon", 2, {"passive_draw": 1, "every": 3}, 0, 0, "cycle", "#5DADE2", "next(), next(), next()…", "next(), next(), next()…"),
        ("closure", "Closure", "creature", "uncommon", 3, {"divine_shield": True}, 3, 2, "locked-box", "#2E86C1", "Помнит своё окружение", "Remembers its scope"),
        ("walrus", "Walrus Operator", "spell", "uncommon", 2, {"damage": 3, "draw": 1}, 0, 0, "walrus-head", "#3498DB", "Присваивает и бьёт одновременно", "Assigns and strikes at once"),
        ("dataclass", "Dataclass", "creature", "uncommon", 3, {"summon_copies": {"count": 1, "attack": 1, "defense": 2}}, 2, 2, "files", "#1A5276", "__init__ пишется сам", "__init__ writes itself"),
        ("metaclass", "Metaclass", "creature", "rare", 5, {"copy_enemy_attack": True, "taunt": True}, 3, 5, "abstract-024", "#154360", "Класс классов классов", "A class of classes of classes"),
        ("asyncio_gather", "asyncio.gather", "spell", "rare", 4, {"damage_split": 7}, 0, 0, "lightning-branches", "#1B4F72", "Все корутины разом", "All coroutines at once"),
        ("mypy", "Type Checker", "artifact", "rare", 3, {"passive_shield": 2}, 0, 0, "magnifying-glass", "#2874A6", "Success: no issues found", "Success: no issues found"),
        ("guido_blessing", "Guido's Blessing", "artifact", "legendary", 6, {"spell_discount": 1, "passive_heal": 2}, 0, 0, "laurel-crown", "#F4D03F", "Благосклонный пожизненный диктатор", "The benevolent dictator smiles"),
        ("zen_interpreter", "The Zen Interpreter", "creature", "legendary", 8, {"divine_shield": True, "draw": 2}, 6, 6, "meditation", "#F7DC6F", "Простое лучше, чем сложное", "Simple is better than complex"),
    ]),
    "ai_developer": ("#9B59B6", [
        ("token_unit", "Token", "spell", "common", 1, {"draw": 1}, 0, 0, "token", "#AF7AC5", "≈ ¾ слова", "≈ ¾ of a word"),
        ("temperature_zero", "Temperature 0", "spell", "common", 1, {"shield": 3}, 0, 0, "thermometer-cold", "#A569BD", "Никаких сюрпризов", "No surprises"),
        ("prompt_basic", "Prompt", "spell", "common", 1, {"damage": 2}, 0, 0, "talk", "#BB8FCE", "Будь краток и конкретен", "Be brief and specific"),
        ("tokenizer", "Tokenizer", "creature", "common", 1, {"draw": 1}, 1, 1, "scissors", "#8E44AD", "Режет текст на смыслы", "Cuts text into meaning"),
        ("few_shot", "Few-Shot", "spell", "common", 2, {"discover": 3}, 0, 0, "three-friends", "#9B59B6", "Пример, пример, вопрос", "Example, example, question"),
        ("loss_function", "Loss Function", "spell", "common", 2, {"damage_random": [1, 4]}, 0, 0, "chart", "#7D3C98", "Чем ниже, тем лучше", "The lower, the better"),
        ("overfitting", "Overfitting", "spell", "common", 2, {"buff_attack": 3, "self_damage": 1}, 0, 0, "muscle-up", "#A569BD", "Идеально на трейне", "Perfect on the training set"),
        ("chatbot", "Chatbot", "creature", "common", 2, {}, 2, 2, "robot-antennas", "#C39BD3", "Как я могу помочь?", "How can I help?"),
        ("dataset", "Dataset", "artifact", "common", 2, {"passive_stamina": 1}, 0, 0, "database", "#884EA0", "Мусор на входе — мусор на выходе", "Garbage in, garbage out"),
        ("fine_tuning", "Fine-Tuning", "spell", "uncommon", 3, {"buff_attack": 4}, 0, 0, "big-gear", "#6C3483", "Немного своих данных", "A little of your own data"),
        ("attention_head", "Attention Head", "creature", "uncommon", 3, {"extra_attack_end_turn": 1}, 3, 2, "eye-target", "#8E44AD", "Смотрит туда, куда важно", "Looks where it matters"),
        ("gradient_descent", "Gradient Descent", "spell", "uncommon", 3, {"damage_all": 2}, 0, 0, "falling", "#76448A", "Шаг за шагом вниз", "Step by step, downhill"),
        ("guardrails", "Guardrails", "spell", "uncommon", 2, {"limit_enemy_attacks": 1, "shield": 2}, 0, 0, "wooden-fence", "#A569BD", "Не выходи за рамки", "Stay within bounds"),
        ("chain_of_thought", "Chain of Thought", "spell", "uncommon", 3, {"draw": 3, "self_damage": 2}, 0, 0, "crossed-chains", "#9B59B6", "Давай подумаем шаг за шагом", "Let's think step by step"),
        ("embedding_space", "Embedding Space", "artifact", "uncommon", 3, {"reveal_enemy_hand": True, "first_card_discount": 1}, 0, 0, "galaxy", "#5B2C6F", "Похожее рядом с похожим", "Similar lives near similar"),
        ("agent_swarm", "Agent Swarm", "creature", "rare", 5, {"summon_copies": {"count": 2, "attack": 2, "defense": 2}}, 2, 2, "beehive", "#7D3C98", "Каждый агент со своей задачей", "Every agent has a task"),
        ("rlhf", "RLHF", "spell", "rare", 4, {"heal": 6, "shield": 3}, 0, 0, "thumb-up", "#BB8FCE", "Люди сказали: так лучше", "Humans said: this is better"),
        ("mixture_experts", "Mixture of Experts", "creature", "rare", 5, {"multi_attack": 2}, 4, 5, "team-idea", "#6C3483", "Каждому вопросу — свой эксперт", "An expert for every question"),
        ("agi_prototype", "AGI Prototype", "creature", "legendary", 9, {"divine_shield": True, "taunt": True, "stun_enemy": 1}, 8, 8, "brain", "#F5B041", "Пожалуйста, не выключайте", "Please don't turn it off"),
        ("context_1m", "Context Window 1M", "artifact", "legendary", 5, {"hand_size": 2, "passive_draw": 1, "every": 1}, 0, 0, "scroll-unfurled", "#F7DC6F", "Помнит всё. Вообще всё", "Remembers everything. Everything"),
    ]),
    "python_backend": ("#2ECC71", [
        ("get_request", "GET Request", "spell", "common", 1, {"damage": 2}, 0, 0, "arrow-cluster", "#28B463", "200 OK — урон доставлен", "200 OK: damage delivered"),
        ("post_request", "POST Request", "spell", "common", 2, {"damage": 3}, 0, 0, "envelope", "#239B56", "201 Created", "201 Created"),
        ("health_check", "Health Check", "spell", "common", 1, {"heal": 3}, 0, 0, "heart-beats", "#58D68D", "/healthz → 200", "/healthz → 200"),
        ("cron_job", "Cron Job", "artifact", "common", 2, {"passive_damage": 1}, 0, 0, "alarm-clock", "#1D8348", "*/1 * * * * ударить()", "*/1 * * * * strike()"),
        ("db_index", "Database Index", "spell", "common", 2, {"draw": 1, "shield": 2}, 0, 0, "bookmark", "#2ECC71", "Seq Scan побеждён", "Seq Scan defeated"),
        ("migration", "Migration", "spell", "common", 2, {"return_spells": 1}, 0, 0, "back-forth", "#27AE60", "upgrade, downgrade, upgrade", "upgrade, downgrade, upgrade"),
        ("webhook_listener", "Webhook", "creature", "common", 1, {"extra_attack_end_turn": 1}, 1, 2, "fishing-hook", "#52BE80", "Позвони мне, если что", "Call me if anything happens"),
        ("worker", "Worker", "creature", "common", 2, {}, 2, 3, "miner", "#1E8449", "Берёт задачу из очереди", "Takes a job from the queue"),
        ("session_cookie", "Session Cookie", "spell", "common", 1, {"shield": 3}, 0, 0, "cookie", "#7DCEA0", "Помнит, кто ты", "Remembers who you are"),
        ("message_queue", "Message Queue", "artifact", "uncommon", 3, {"passive_stamina": 1, "passive_shield": 1}, 0, 0, "stack", "#229954", "FIFO, как в жизни", "FIFO, just like life"),
        ("circuit_breaker", "Circuit Breaker", "spell", "uncommon", 3, {"limit_enemy_attacks": 1, "heal": 2}, 0, 0, "electric", "#1ABC9C", "Отказ? Остановись и отдохни", "Failing? Stop and rest"),
        ("orm_model", "ORM", "creature", "uncommon", 3, {"taunt": True, "draw": 1}, 2, 4, "linked-rings", "#16A085", "SELECT * FROM heroes", "SELECT * FROM heroes"),
        ("cdn_edge", "CDN", "spell", "uncommon", 3, {"damage_split": 5}, 0, 0, "world", "#48C9B0", "Ближе к каждому врагу", "Closer to every enemy"),
        ("celery_task", "Celery Task", "creature", "uncommon", 2, {"summon_copies": {"count": 1, "attack": 1, "defense": 1}}, 1, 1, "carrot", "#58D68D", ".delay() и забыть", ".delay() and forget"),
        ("jwt_token", "JWT Token", "spell", "uncommon", 2, {"free_weapon_attack": 2}, 0, 0, "key", "#17A589", "Пропуск подписан", "The pass is signed"),
        ("db_shard", "Database Shard", "creature", "rare", 4, {"summon_copies": {"count": 2, "attack": 1, "defense": 2}}, 3, 3, "broken-shield", "#117A65", "Часть целого, но целое", "Part of a whole, yet whole"),
        ("idempotency_key", "Idempotency Key", "spell", "rare", 4, {"shield": 8}, 0, 0, "key-lock", "#0E6655", "Повтор не навредит", "A retry won't hurt"),
        ("graphql", "GraphQL", "spell", "rare", 4, {"draw": 2, "next_free": True}, 0, 0, "molecule", "#E91E63", "Ровно то, что запросил", "Exactly what you asked for"),
        ("distributed_monolith", "Distributed Monolith", "creature", "legendary", 8, {"taunt": True, "damage_all": 2}, 7, 9, "stone-tower", "#F4D03F", "Худшее из двух миров, но огромное", "The worst of both worlds, but huge"),
        ("zero_downtime", "Zero Downtime Deploy", "artifact", "legendary", 6, {"passive_heal": 2, "passive_shield": 2}, 0, 0, "sun", "#F7DC6F", "Пользователи ничего не заметили", "Users noticed nothing"),
    ]),
    "game_designer": ("#E67E22", [
        ("game_juice", "Juice", "spell", "common", 1, {"buff_attack": 2}, 0, 0, "fruit-bowl", "#EB984E", "Тряска экрана решает всё", "Screen shake fixes everything"),
        ("tutorial", "Tutorial", "spell", "common", 1, {"draw": 1, "heal": 2}, 0, 0, "teacher", "#F0B27A", "Нажми E, чтобы победить", "Press E to win"),
        ("save_point", "Save Point", "spell", "common", 2, {"checkpoint": True, "shield": 2}, 0, 0, "save", "#DC7633", "Игра сохранена", "Game saved"),
        ("power_up", "Power-Up", "spell", "common", 2, {"buff_attack": 3}, 0, 0, "mushroom-gills", "#E67E22", "Ты стал больше!", "You got bigger!"),
        ("loot_table", "Loot Table", "spell", "common", 2, {"damage_random": [1, 5]}, 0, 0, "rolling-dices", "#CA6F1E", "Шанс легендарки 0.1%", "Legendary drop chance: 0.1%"),
        ("npc_merchant", "NPC Merchant", "creature", "common", 2, {"heal": 2}, 1, 3, "shop", "#D35400", "Что-нибудь купишь?", "Buying anything?"),
        ("respawn", "Respawn", "spell", "common", 2, {"heal": 4}, 0, 0, "heart-plus", "#F5B041", "Ещё одна попытка", "One more try"),
        ("prototype", "Prototype", "creature", "common", 1, {}, 2, 1, "cube", "#E59866", "Из палок и изоленты", "Sticks and duct tape"),
        ("achievement", "Achievement", "artifact", "common", 2, {"passive_heal": 1}, 0, 0, "trophy-cup", "#F8C471", "Получено: «Первая кровь»", "Unlocked: First Blood"),
        ("boss_pattern", "Boss Pattern", "spell", "uncommon", 3, {"stun_enemy": 1}, 0, 0, "spiral-arrow", "#BA4A00", "Выучи атаки — и бей в окно", "Learn the moves, hit the window"),
        ("difficulty_curve", "Difficulty Curve", "spell", "uncommon", 3, {"damage_per_creature": 1, "draw": 1}, 0, 0, "histogram", "#D35400", "Сложно, но честно", "Hard, but fair"),
        ("combo_system", "Combo System", "artifact", "uncommon", 3, {"first_card_discount": 1, "passive_stamina": 1}, 0, 0, "punch-blast", "#E74C3C", "×2 ×4 ×8!", "×2 ×4 ×8!"),
        ("speedrunner", "Speedrunner", "creature", "uncommon", 3, {"multi_attack": 2}, 3, 1, "sprint", "#F39C12", "Any% без глитчей", "Any%, glitchless"),
        ("game_jam", "Game Jam", "spell", "uncommon", 3, {"turn_discount": 1, "draw": 1}, 0, 0, "hourglass", "#E67E22", "48 часов, одна идея", "48 hours, one idea"),
        ("narrative_designer", "Narrative Designer", "creature", "uncommon", 3, {"draw": 2}, 2, 3, "quill", "#DC7633", "А что, если злодей — это ты?", "What if the villain is you?"),
        ("roguelike_run", "Roguelike Run", "spell", "rare", 4, {"discover": 4, "next_free": True}, 0, 0, "perspective-dice-six-faces-random", "#A04000", "Умри, учись, повтори", "Die, learn, repeat"),
        ("skill_tree", "Skill Tree", "artifact", "rare", 4, {"aura_attack": 1, "passive_draw": 1, "every": 3}, 0, 0, "tree-branch", "#B9770E", "+1 к силе каждые три уровня", "+1 strength every three levels"),
        ("final_boss", "Final Boss", "creature", "rare", 6, {"taunt": True, "stun_enemy": 1}, 6, 6, "crowned-skull", "#922B21", "У него третья фаза", "It has a third phase"),
        ("game_of_year", "Game of the Year", "creature", "legendary", 8, {"divine_shield": True, "extra_attack_end_turn": 1, "heal": 5}, 7, 7, "podium-winner", "#F1C40F", "Все награды сезона", "Every award this season"),
        ("infinite_replay", "Infinite Replayability", "spell", "legendary", 7, {"return_spells": 4, "draw": 2}, 0, 0, "infinity", "#F4D03F", "Ещё одну партию… и спать", "One more run… then bed"),
    ]),
    "level_designer": ("#F1C40F", [
        ("breadcrumbs", "Breadcrumbs", "spell", "common", 1, {"discover": 2}, 0, 0, "footprint", "#D4AC0D", "Свет зовёт игрока вперёд", "Light pulls the player forward"),
        ("cover_point", "Cover Point", "creature", "common", 2, {"taunt": True}, 1, 4, "brick-wall", "#B7950B", "Пригнись и перезаряжайся", "Duck and reload"),
        ("gated_door", "Gated Door", "spell", "common", 2, {"limit_enemy_attacks": 1}, 0, 0, "locked-door", "#9A7D0A", "Сначала найди ключ", "Find the key first"),
        ("health_pack", "Health Pack", "spell", "common", 1, {"heal": 4}, 0, 0, "medical-pack", "#F4D03F", "Всегда за углом перед боссом", "Always around the corner before a boss"),
        ("line_of_sight", "Line of Sight", "spell", "common", 1, {"free_weapon_attack": 1, "draw": 1}, 0, 0, "eye-target", "#F1C40F", "Вижу цель", "Target in sight"),
        ("spawn_point", "Spawn Point", "creature", "common", 2, {"summon_copies": {"count": 1, "attack": 1, "defense": 1}}, 1, 1, "portal", "#D4AC0D", "Появляются отсюда", "They spawn here"),
        ("signpost", "Signpost", "spell", "common", 1, {"next_spell_discount": 2}, 0, 0, "wooden-sign", "#B7950B", "→ К боссу", "→ To the boss"),
        ("ladder", "Ladder", "spell", "common", 2, {"shield": 3, "draw": 1}, 0, 0, "ladder", "#9A7D0A", "Наверху безопаснее", "Safer up high"),
        ("jump_pad", "Jump Pad", "spell", "common", 2, {"free_weapon_attack": 2}, 0, 0, "jump-across", "#F7DC6F", "Боинг!", "Boing!"),
        ("moving_platform", "Moving Platform", "creature", "uncommon", 3, {"divine_shield": True}, 2, 3, "floating-platforms", "#D4AC0D", "Прыгай по таймингу", "Jump on the beat"),
        ("kill_zone", "Kill Zone", "spell", "uncommon", 3, {"damage_all": 2}, 0, 0, "target-arrows", "#B9770E", "Все дороги ведут сюда", "Every path leads here"),
        ("vista", "Vista", "artifact", "uncommon", 3, {"reveal_enemy_hand": True, "passive_draw": 1, "every": 3}, 0, 0, "mountain-cave", "#F4D03F", "Вид на всю карту", "A view of the whole map"),
        ("trap_corridor", "Trap Corridor", "spell", "uncommon", 3, {"freeze_enemy_creature": 3}, 0, 0, "spiked-trunk", "#9A7D0A", "Не наступай на плитки", "Don't step on the tiles"),
        ("hub_world", "Hub World", "artifact", "uncommon", 3, {"passive_stamina": 2}, 0, 0, "village", "#D4AC0D", "Все дороги начинаются здесь", "Every road starts here"),
        ("fog_of_war", "Fog of War", "spell", "uncommon", 2, {"shield": 3, "limit_enemy_attacks": 1}, 0, 0, "fog", "#B7950B", "Враг не видит, куда бить", "The enemy can't see where to strike"),
        ("speedrun_shortcut", "Speedrun Shortcut", "spell", "rare", 4, {"turn_discount": 2}, 0, 0, "magic-portal", "#F1C40F", "Сквозь стену — так быстрее", "Through the wall is faster"),
        ("open_world", "Open World", "artifact", "rare", 5, {"hand_size": 1, "passive_draw": 1, "every": 2}, 0, 0, "treasure-map", "#D4AC0D", "Видишь гору? Можешь залезть", "See that mountain? You can climb it"),
        ("guardian_statue", "Guardian Statue", "creature", "rare", 5, {"taunt": True, "divine_shield": True}, 3, 7, "stone-bust", "#7D6608", "Молчаливый страж прохода", "A silent guardian of the passage"),
        ("megadungeon", "Megadungeon", "creature", "legendary", 9, {"taunt": True, "summon_copies": {"count": 2, "attack": 2, "defense": 2}}, 6, 10, "dungeon-gate", "#F4D03F", "Сто этажей вниз", "A hundred floors down"),
        ("perfect_flow", "Perfect Flow", "spell", "legendary", 6, {"turn_discount": 2, "draw": 3}, 0, 0, "wind-slap", "#F7DC6F", "Игрок даже не заметил уровень", "The player didn't even notice the level"),
    ]),
    "algorithms": ("#00BFD8", [
        ("big_o", "Big O", "spell", "common", 1, {"draw": 1}, 0, 0, "chart", "#1ABC9C", "O(1) — лучшая новость дня", "O(1) is the best news of the day"),
        ("two_pointers", "Two Pointers", "spell", "common", 1, {"damage": 2}, 0, 0, "back-forth", "#16A085", "Навстречу друг другу — и в цель", "Toward each other — and on target"),
        ("hash_map", "Hash Map", "spell", "common", 2, {"discover": 3}, 0, 0, "key", "#00BFD8", "Нашёл за O(1)", "Found it in O(1)"),
        ("stack_frame", "Stack", "creature", "common", 2, {"taunt": True}, 1, 4, "stack", "#1F8A9E", "Последним пришёл — первым принял удар", "Last in, first to take the hit"),
        ("queue_bfs", "BFS", "spell", "common", 2, {"damage_split": 4}, 0, 0, "mesh-network", "#20A4B8", "Уровень за уровнем", "Level by level"),
        ("binary_search", "Binary Search", "spell", "common", 2, {"execute_below": 4}, 0, 0, "magnifying-glass", "#0E9AA7", "Пополам, ещё пополам — попался", "Halve it, halve again — gotcha"),
        ("memo_cache", "Memoization", "artifact", "uncommon", 2, {"first_card_discount": 1}, 0, 0, "files", "#48C9B0", "Уже считали — бери готовое", "Already computed — take it"),
        ("binary_heap", "Binary Heap", "creature", "uncommon", 3, {"shield": 3}, 2, 4, "triforce", "#17A589", "Самое важное — всегда сверху", "The most important always on top"),
        ("merge_sort", "Merge Sort", "spell", "uncommon", 3, {"damage": 3, "draw": 1}, 0, 0, "linked-rings", "#13B5C8", "Разделяй и властвуй", "Divide and conquer"),
        ("dfs_explorer", "DFS Explorer", "creature", "uncommon", 3, {"multi_attack": 2}, 2, 2, "compass", "#0B8A99", "Сначала вглубь, потом посмотрим", "Go deep first, look around later"),
        ("dijkstra", "Dijkstra", "spell", "rare", 4, {"damage_all": 2, "draw": 1}, 0, 0, "target-arrows", "#117A8B", "Кратчайший путь к победе", "The shortest path to victory"),
        ("dynamic_programming", "Dynamic Programming", "artifact", "rare", 4, {"passive_draw": 1, "every": 2}, 0, 0, "spiral-arrow", "#0A6E7C", "Каждая подзадача — один раз", "Every subproblem exactly once"),
        ("red_black_tree", "Red-Black Tree", "creature", "legendary", 7, {"divine_shield": True, "taunt": True, "shield": 4}, 5, 8, "tree-branch", "#F4D03F", "Высота O(log n), как ни крути", "O(log n) height, no matter what"),
    ]),
}


def main():
    data = json.load(open(PATH, encoding="utf-8"))
    cards = data["cards"]
    new_ids = set()
    for spec, (_, items) in SPECS.items():
        for (cid, name, ctype, rarity, cost, effect, atk, dfn, icon, art, fl_ru, fl_en) in items:
            card = {"id": cid, "name": name, "type": ctype, "rarity": rarity, "crystal_cost": cost,
                    "effect": effect, "flavor_text": fl_ru, "flavor_text_en": fl_en,
                    "from_specialization": spec, "art_color": art, "icon": icon}
            if ctype == "creature":
                card["attack"] = atk
                card["defense"] = dfn
            card["description"], card["description_en"] = describe(card)
            new_ids.add(cid)
            cards[:] = [c for c in cards if c["id"] != cid]
            cards.append(card)
    json.dump(data, open(PATH, "w", encoding="utf-8"), ensure_ascii=False, indent="\t")
    print("cards:", len(cards), "new:", len(new_ids))


if __name__ == "__main__":
    main()
