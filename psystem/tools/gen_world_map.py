# Генерация data/world_map.json: 100 локаций глобальной карты (позиции, биомы, уровни).
# Запуск (из папки psystem): python tools/gen_world_map.py
# Открыты четыре локации (OPEN), остальные — «в разработке».
import json, math, random, os

random.seed(42)
CAMP = (0.30, 0.56)

BIOMES = {
    "forest": ((0.24, 0.47), 0.13, 0, [
        ("whisper_grove", "Шепчущая роща", "Whispering Grove"), ("oldwood", "Старолесье", "Oldwood"),
        ("rootoak", "Дубрава Корней", "Rootoak Glade"), ("emerald_thicket", "Изумрудная чаща", "Emerald Thicket"),
        ("firefly_woods", "Лес Светлячков", "Firefly Woods"), ("dusky_pinewood", "Сумрачный бор", "Dusky Pinewood"),
        ("hunters_trail", "Тропа Охотника", "Hunter's Trail"), ("witch_hollow", "Ведьмин лог", "Witch Hollow"),
        ("druids_clearing", "Поляна Друидов", "Druids' Clearing"), ("maple_dale", "Кленовый дол", "Maple Dale"),
        ("bears_nook", "Медвежий угол", "Bear's Nook"), ("silver_underbrush", "Серебряный подлесок", "Silver Underbrush")]),
    "meadow": ((0.40, 0.66), 0.11, 1, [
        ("honey_meadows", "Медовые луга", "Honey Meadows"), ("windy_hills", "Ветреные холмы", "Windy Hills"),
        ("valley_of_mills", "Долина Мельниц", "Valley of Mills"), ("sunny_dale", "Солнечный дол", "Sunny Dale"),
        ("shepherds_ridge", "Пастушья гряда", "Shepherd's Ridge"), ("poppy_field", "Маковое поле", "Poppy Field"),
        ("quiet_hamlet", "Тихий хутор", "Quiet Hamlet"), ("three_roads", "Перекрёсток Трёх Дорог", "Three Roads Crossing"),
        ("starfall_meadow", "Луг Падающих Звёзд", "Starfall Meadow")]),
    "ruins": ((0.47, 0.50), 0.10, 2, [
        ("ferrograd_ruins", "Руины Феррограда", "Ferrograd Ruins"), ("forgotten_aqueduct", "Забытый акведук", "Forgotten Aqueduct"),
        ("compiler_tower", "Башня Компилятора", "Compiler's Tower"), ("shattered_library", "Разбитая библиотека", "Shattered Library"),
        ("temple_recursion", "Храм Рекурсии", "Temple of Recursion"), ("cogwork_abbey", "Обитель Шестерён", "Cogwork Abbey"),
        ("stone_amphitheater", "Каменный амфитеатр", "Stone Amphitheater"), ("fallen_bastion", "Павший бастион", "Fallen Bastion"),
        ("arch_first_lines", "Арка Первых Строк", "Arch of First Lines")]),
    "swamp": ((0.20, 0.76), 0.09, 3, [
        ("misty_marshes", "Туманные топи", "Misty Marshes"), ("rotwater", "Гнилая заводь", "Rotwater Backwater"),
        ("frog_kingdom", "Лягушачье царство", "Frog Kingdom"), ("bog_lost_links", "Болото Утерянных Ссылок", "Bog of Lost Links"),
        ("reedlands", "Камышовый край", "Reedlands"), ("mire_lights", "Трясина Тысячи Огней", "Mire of a Thousand Lights"),
        ("sunken_village", "Затонувшая деревня", "Sunken Village"), ("black_pool", "Чёрный омут", "Black Pool")]),
    "mountains": ((0.46, 0.27), 0.12, 6, [
        ("copper_hills", "Медные холмы", "Copper Hills"), ("server_peak", "Пик Сервера", "Server Peak"),
        ("dwarven_pass", "Гномий перевал", "Dwarven Pass"), ("eagles_nest", "Орлиное гнездо", "Eagle's Nest"),
        ("stone_spine", "Каменный хребет", "Stone Spine"), ("deepore_mines", "Шахты Глубинной Руды", "Deepore Mines"),
        ("thundering_cliff", "Грохочущий утёс", "Thundering Cliff"), ("pass_of_winds", "Перевал Ветров", "Pass of Winds"),
        ("beardforge", "Кузницы Бородачей", "Beardforge"), ("sky_stair", "Небесная лестница", "Sky Stair")]),
    "snow": ((0.40, 0.11), 0.10, 14, [
        ("frost_march", "Ледяной предел", "Frost March"), ("frozen_wastes", "Стылые пустоши", "Frozen Wastes"),
        ("crystal_glacier", "Хрустальный ледник", "Crystal Glacier"), ("mammoth_barrows", "Мамонтовы курганы", "Mammoth Barrows"),
        ("northern_lighthouse", "Северный маяк", "Northern Lighthouse"), ("snow_keep", "Снежная крепость", "Snow Keep"),
        ("eternal_ice_lake", "Озеро Вечного Льда", "Lake of Eternal Ice"), ("blizzard_canyon", "Вьюжный каньон", "Blizzard Canyon")]),
    "desert": ((0.66, 0.78), 0.11, 10, [
        ("sandbox_sands", "Пески Песочницы", "Sandbox Sands"), ("cache_oasis", "Оазис Кэша", "Cache Oasis"),
        ("sun_pyramid", "Солнечная пирамида", "Sun Pyramid"), ("binary_dunes", "Барханы Бинарника", "Binary Dunes"),
        ("caravan_road", "Караванный путь", "Caravan Road"), ("scorpion_canyon", "Каньон Скорпионов", "Scorpion Canyon"),
        ("mirage_city", "Миражный город", "Mirage City"), ("dry_sea", "Сухое море", "Dry Sea"),
        ("daemon_pharaoh", "Гробница Фараона-Демона", "Tomb of the Daemon Pharaoh")]),
    "coast": ((0.10, 0.50), 0.08, 4, [
        ("smugglers_cove", "Бухта Контрабандистов", "Smugglers' Cove"), ("last_commit_light", "Маяк Последнего Коммита", "Last Commit Lighthouse"),
        ("pearl_shore", "Жемчужный берег", "Pearl Shore"), ("sirens_rocks", "Скалы Сирен", "Sirens' Rocks"),
        ("fishing_village", "Рыбацкий посёлок", "Fishing Village"), ("parrot_isle", "Остров Попугаев", "Parrot Isle"),
        ("sunken_fleet", "Затонувший флот", "Sunken Fleet"), ("salt_caves", "Солёные пещеры", "Salt Caves"),
        ("packet_port", "Порт Пакетов", "Packet Port")]),
    "volcano": ((0.80, 0.52), 0.09, 18, [
        ("fire_mountain", "Огненная гора", "Fire Mountain"), ("ash_fields", "Пепельные поля", "Ash Fields"),
        ("lava_rivers", "Лавовые реки", "Lava Rivers"), ("titans_forge", "Кузня Титанов", "Titans' Forge"),
        ("obsidian_maze", "Обсидиановый лабиринт", "Obsidian Maze"), ("dragons_lair", "Драконье логово", "Dragon's Lair"),
        ("sulfur_valley", "Серная долина", "Sulfur Valley"), ("volcano_heart", "Сердце Вулкана", "Heart of the Volcano")]),
    "dark": ((0.84, 0.24), 0.10, 24, [
        ("cursed_lands", "Проклятые земли", "Cursed Lands"), ("deprecated_graveyard", "Кладбище Устаревших", "Graveyard of the Deprecated"),
        ("necromancer_castle", "Замок Некроманта", "Necromancer's Castle"), ("shadow_forest", "Теневой лес", "Shadow Forest"),
        ("crimson_waste", "Багровая пустошь", "Crimson Waste"), ("mad_mage_spire", "Шпиль Безумного Мага", "Mad Mage's Spire"),
        ("ghost_valley", "Долина Призраков", "Valley of Ghosts"), ("abyss_gate", "Врата Бездны", "Abyss Gate"),
        ("eternal_night", "Цитадель Вечной Ночи", "Citadel of Eternal Night")]),
    "caves": ((0.62, 0.36), 0.10, 8, [
        ("mushroom_caverns", "Грибные пещеры", "Mushroom Caverns"), ("crystal_grotto", "Хрустальный грот", "Crystal Grotto"),
        ("echo_cave", "Пещера Эха", "Echo Cave"), ("goblin_warrens", "Гоблинские норы", "Goblin Warrens"),
        ("underground_lake", "Подземное озеро", "Underground Lake"), ("bat_cave", "Пещера Летучих Мышей", "Bat Cave"),
        ("worm_tunnels", "Тоннели Червей", "Worm Tunnels"), ("glowing_abyss", "Светящаяся бездна", "Glowing Abyss"),
        ("mountain_king", "Чертоги Горного Короля", "Halls of the Mountain King")]),
}
OPEN = {"whisper_grove": ((0.255, 0.50), 1), "ferrograd_ruins": ((0.405, 0.52), 3),
        "maple_dale": ((0.3088, 0.5001), 5), "valley_of_mills": ((0.3516, 0.6027), 7)}


def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])


points = [CAMP] + [p for p, _ in OPEN.values()]
locations = []
for biome, (center, spread, lvl_bonus, names) in BIOMES.items():
    placed = []
    for loc_id, ru, en in names:
        if loc_id in OPEN:
            pos = OPEN[loc_id][0]
        else:
            for _ in range(4000):
                a = random.random() * math.tau
                r = spread * math.sqrt(random.random())
                pos = (center[0] + math.cos(a) * r * 1.25, center[1] + math.sin(a) * r)
                if not (0.06 < pos[0] < 0.94 and 0.07 < pos[1] < 0.93):
                    continue
                if all(dist(pos, q) > 0.052 for q in points):
                    break
            points.append(pos)
        placed.append((loc_id, ru, en, pos))
    # Ближе к лагерю — ниже уровень
    for loc_id, ru, en, pos in placed:
        d = dist(pos, CAMP)
        level = OPEN[loc_id][1] if loc_id in OPEN else max(2, min(60, round(2 + d * 55 + lvl_bonus)))
        locations.append({"id": loc_id, "name": ru, "name_en": en, "biome": biome, "level": level,
                          "pos": [round(pos[0], 4), round(pos[1], 4)], "status": "open" if loc_id in OPEN else "wip"})

locations.sort(key=lambda l: (l["level"], l["id"]))
# Дороги: минимальное остовное дерево + несколько коротких дополнительных рёбер
nodes = [{"id": "camp", "pos": CAMP}] + locations
edges = set()
in_tree = {0}
while len(in_tree) < len(nodes):
    best = None
    for i in in_tree:
        for j in range(len(nodes)):
            if j in in_tree:
                continue
            d = dist(nodes[i]["pos"], nodes[j]["pos"])
            if best is None or d < best[0]:
                best = (d, i, j)
    in_tree.add(best[2])
    edges.add((min(best[1], best[2]), max(best[1], best[2])))
for i in range(len(nodes)):
    near = sorted(range(len(nodes)), key=lambda j: dist(nodes[i]["pos"], nodes[j]["pos"]))[1:3]
    for j in near:
        if dist(nodes[i]["pos"], nodes[j]["pos"]) < 0.085 and random.random() < 0.45:
            edges.add((min(i, j), max(i, j)))
roads = [[nodes[a]["id"], nodes[b]["id"]] for a, b in sorted(edges)]
out = {"_doc": "Сгенерировано tools/gen_world_map.py. pos — координаты на карте 0..1.",
       "camp": {"name": "Лагерь искателей", "name_en": "Seekers' Camp", "pos": list(CAMP)},
       "locations": locations, "roads": roads}
path = os.path.join(os.path.dirname(__file__), "..", "data", "world_map.json")
json.dump(out, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent="\t")
print(len(locations), "locations,", len(roads), "roads")
