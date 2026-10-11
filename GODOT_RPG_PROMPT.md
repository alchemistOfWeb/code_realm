# CodeRealm — обзор проекта (для Claude)

Геймифицированная RPG-система изучения знаний на **Godot 4.6.3** (GDScript, рендер Compatibility, Windows).
Пользователь изучает темы 5 специализаций (подготовка к собеседованиям) → XP, уровни, энергия, карты →
вылазки в 3D-мир (WoW / King's Bounty-стиль), карточные бои, снаряжение. Проект Godot лежит в `psystem/` (res:// = `psystem/`).
Репозиторий: https://github.com/alchemistOfWeb/code_realm (ветка main).

**В начале каждой сессии:** прочитай `psystem/NOTES_FOR_CLAUDE.md` (правки пользователя из игры).
**После изменений:** запусти smoke-тест (`tools/SmokeTest.tscn`, сейчас 133 проверки); после правок ThemeFactory —
перегенерируй тему; после новых строк интерфейса — `python tools/i18n/extract.py` и переведи пустые ключи `locale/en.json`
(команды в `psystem/README.md`).
Godot: `C:\Users\user\games\godot\Godot_v4.6.3-stable_win64_console.exe`. Редактор обычно открыт — после правок
`project.godot` пользователю нужно Project → Reload Current Project.
**Экран пользователя 1366×768.** Базовое разрешение UI — 1280×720 (stretch canvas_items/expand), все экраны должны
помещаться в 1280×720 (HUD — впритык, новые кнопки делай иконками). Новые экраны регистрируй в `Main.SCREENS`
(полноэкранные без HUD — в `Main.FULLSCREEN`).

---

## Статус итераций

- **Итерации 1–4 — ГОТОВЫ** (дерево знаний, уроки, тесты, награды, карточный бой, диалоги BG3-стиля, загадки,
  Python-сейфы). Подробности в git-истории и разделах ниже.
- **Итерация 5 — ГОТОВА (18 улучшений пользователя):**
  1. Вылазка стоит 10 энергии (`XPCalculator.SORTIE_ENERGY_COST`), было 30.
  2. «Выйти из игры»: главное меню, меню Esc (Main `_toggle_game_menu`), меню вылазки; сохранение перед выходом.
  3. Потери золота нет (поражение/падение — без штрафа золотом).
  4. Глобальная карта: 100 локаций (`data/world_map.json`, генератор `tools/gen_world_map.py`), уровень-рекомендация,
     % исследования, биомы, дороги; 2 реализованы (Шепчущая роща, Руины Феррограда), остальные «в разработке».
  5. Карта локации: граф подлокаций (`data/locations.json`), состояния hidden/known/open/visited/cleared; в подлокацию
     можно отправиться только если найден проход из соседней; найденные проходы — быстрый старт с карты.
  6. Лавка «Медный молот» (`scenes/shop/ShopScreen`): оружие, щиты, броня, украшения (не карты), примерка на 3D-герое,
     покупка/«купить и надеть»/продажа за 50%.
  7. Снаряжение и инвентарь (вкладка «Снаряжение» персонажа): 10 слотов, без ограничений веса/объёма; влияет на бой
     (атаки по оружию, броня = щит в начале боя, урон, HP, атрибуты, уклонение) и на вид героя.
  8. Новая сборка колоды: коллекция с отступами (рамки не обрезаются), ленты «✓ В колоде ×N», затемнение исчерпанных,
     колода справа мини-картами с ×N, кривая стоимости, состав по типам, поиск и фильтры.
  9. Минимума колоды нет (`MIN_DECK_SIZE = 0`, максимум 30); бой с пустой колодой возможен.
  10–12. Взрослые герои Quaternius (6 рас D&D: человек, эльф, дворф, орк, полурослик, тифлинг; 2 пола) — сборка в Blender
     (`tools/blender/build_hero.py`), анимации Universal Animation Library; создание героя (раса, пол, кожа, причёска,
     цвет волос, борода, расцветка одежды). Локации в стиле WoW/King's Bounty (Stylized Nature, Fantasy Props,
     Medieval Village MegaKit, монстры Quaternius).
  13. Бег (Shift) тратит выносливость (полоска в HUD вылазки; при истощении — шаг, восстановление после паузы).
  14. Space — пауза с белой надписью «ПАУЗА»; Esc — меню вылазки (продолжить, настройки, в лагерь, выйти).
  15. Локализация ru/en (`Loc`, `locale/en.json`, переключатель в главном меню и настройках) + главное меню с профилями
     (выбрать/создать/удалить).
  16. Титры (`scenes/menu/Credits`) — авторы ассетов, движка, шрифтов, звука.
  17. +100 карт (`tools/gen_cards.py`, всего 138; описания ru/en собираются из эффектов).
  18. Прыжок (F по умолчанию — Space занят паузой по просьбе пользователя; клавиши переназначаются в настройках),
     движущиеся платформы над пропастью/рекой; падение = гибель: вся энергия теряется, возврат на базу.
- **Идеи на потом:** реализовать ещё локации (данные уже есть на карте), дома из модулей Medieval Village, 3D-иконки
  предметов (рендер моделей оружия), больше NPC и квестов между вылазками, перевод контента уроков.

Dev-аргументы Main (после `--`): `--screen=menu | creator | credits | shop | map | location:<loc> |
sortie:<loc>:<node>[:seed] [--look=platforms|exit] [--walk=N] | world | mini:<spec> | lesson:<id> | character[:tab] |
settings | test:<spec> | reward:<spec> | lootbox | combat:<enemy> [--auto=N] | dialogue:<npc> | riddle:<id> | safe:<id>`,
`--demo` (временный герой с прогрессом, user://demo_saves/), `--autodeck`, `--lang=en` (язык без сохранения),
`--shot=<png> [--shot-delay=s]` (скриншот без баннера уровня; без --demo — user://dev_saves/), `--levelup`, `--toast=`.

---

## Структура файлов (psystem/)

### Автолоады (`scripts/autoload/`, порядок: EventBus, Settings, ContentParser, GameManager, SaveSystem, Audio)
- **Settings** — `user://settings.cfg`: окно, разрешение, масштаб UI, VSync, громкости, музыка, `language` ("ru"/"en"),
  `bindings` (действие → physical keycode), `mouse_sensitivity`. Действия ввода регистрируются в коде (`INPUT_ACTIONS`):
  move_*, sprint (Shift), jump (F), interact (E), pause (Space), map (M), camera_left/right (Q/R). `REBINDABLE`,
  `rebind(action, key)` (меняет местами при конфликте), `action_key_name()`. При смене языка вызывает `Loc.setup`.
- **EventBus** — `navigate(screen, params)` (`params.root` — очистить стек, `replace`, `overlay`), `navigate_back`,
  `navigate_home`, `toast`, `progress_changed`, `combat_finished`, `dialogue_finished`, `riddle_finished`,
  `safe_finished`, `quit_requested`, `game_menu_requested`; хелперы `go()`, `back()`, `notify()`, `quit_game()`, `go_main_menu()`.
- **GameManager** — состояние героя: `player_data` (level, xp, hp, energy, gold, attributes, lootboxes, **name, look,
  inventory, equipment**), знания, тесты, заметки, коллекция и колода, `world` (flags, items, quests, **locations**, stats).
  Снаряжение: `create_hero(name, look)` (расовый бонус + стартовый комплект), `give_starter_kit`, `equipped(slot)`,
  `buy_item/buy_block_reason/sell_item`, `equip(id, slot="")` (кинжал — `offhand`), `unequip`, `equipment_stats`,
  `effective_attributes`, `recalc_max_hp` (HP = 15 + 3×уровень + бонус вещей), `combat_weapons` (по оружию; без — кулаки),
  `combat_stats()` для CombatState, `hero_outfit()` для HeroRig. `after_load()` — миграции. Сигнал `equipment_changed`.
- **SaveSystem** — **профили**: `user://profiles.json` + папки `user://profiles/<id>/` (4 JSON: player, knowledge,
  cards, world). `list_profiles/get_profile/last_profile_id/create_profile/select_profile/close_profile/delete_profile`,
  `use_dir(dir)` (dev/тесты), `profiles_file/profiles_dir` подменяются тестами. Старые `user://saves/` при первом запуске
  переносятся в профиль «Странник». Автосохранение только при активном профиле. SAVE_VERSION 3.
- **ContentParser**, **Audio** — как раньше (Audio не подключает звук к кнопке повторно при reparent).

### Утилиты (`scripts/utils/`)
- **Loc** — локализация: русский — исходный язык (строки в коде), `locale/en.json` — перевод «рус → англ».
  `Loc.t(s)` (переводить строки с `%` ДО форматирования), `Loc.f(dict, key)` (поле `key_en` или перевод), `Loc.localized`,
  `Loc.plural`. Английский словарь подключается к TranslationServer только при английском языке (иначе Godot
  подмешивает его как fallback). Control/Label3D переводят простые тексты сами (auto_translate).
- **XPCalculator** — баланс: `SORTIE_ENERGY_COST` 10, колода 0–30, `RUN_STAMINA` 6 с бега, `WEAPONS` (fists, sword,
  dagger, bow, axe, hammer, spear), `RUNES`, `ATTRIBUTES`, `dodge_chance(agility, bonus)` ≤60%.
- **ItemDatabase** — `data/items.json` (47 предметов): слоты `SLOTS`, категории лавки, `STAT_NAMES`, `STARTER`,
  `get_item/all_items/shop_items/fits/sell_price/icon/tier_color/stat_lines`.
- **CardDatabase** — каталоги карт/врагов, перечитываются при смене языка (поля `*_en`).
- Остальные (QuizGenerator, MarkdownBBCode, ThemeFactory, Palette, PythonRunner, ClaudeNotesExporter) — как раньше.
  QuizGenerator и ContentParser намеренно не локализуются (контент уроков — на русском).

### Персонажи (`scripts/characters/`)
- **Appearance** — `RACES` (имя, описание, бонус, масштаб скелета, компенсация головы, расовые части, палитра кожи),
  `HAIRSTYLES`, `HAIR_COLORS`, `default_look`, `random_look(seed)`, `tint_for` (цвет → множитель текстуры).
- **HeroRig** (Node3D) — модель `assets/characters/hero_<gender>.glb` (все части включаются видимостью: Outfit_Peasant_*,
  Outfit_Ranger_*, Hair_*, Race_ElfEar_*, Race_OrcTusk_*, Race_Horn_*), анимации UAL (`ual_anims.glb`, библиотека "ual"),
  `apply_look`, `apply_equipment({outfit, variants, weapon, offhand})`, `set_weapon/set_offhand` (BoneAttachment3D
  hand_r/hand_l, повороты подобраны), `play/play_once/height`. Класс `HeadScaler` (SkeletonModifier3D) возвращает
  голове нормальные пропорции у дворфов/полуросликов.
- **MonsterRig** — 11 монстров (`assets/monsters`): рост, высота полёта, роли анимаций idle/move/attack/death/hit;
  Imp и Puglin используют UAL.
- `scripts/dungeon/CharacterRig.gd` — tint/first_mesh для моделей Kenney.

### Мир (`scripts/world/`)
- **WorldData** — карта мира и графы локаций (`location`, `node`, `start_node`, `NODE_KINDS`, `BIOMES`), прогресс в
  `GameManager.world.locations[loc].nodes[node]` {visited, exits, chests, kills, total_*, boss}: `node_status`,
  `is_open`, `node_progress` (30% посещение + 30% проходы + 20% сундуки + 20% победы), `location_progress`,
  `visit_node/mark_exit/mark_chest/mark_kill`, `node_seed` (раскладка подлокации постоянна).
- **OutdoorGenerator** — поверхность: сетка 1 м (0 непроходимо, 1 поляна, 2 тропа, 3 пропасть/река), поляны + тропы
  (MST), выходы к соседям, при `features.platforms` — пропасть/река поперёк карты и цепочка движущихся платформ,
  NPC, сундуки, сейф, враги, босс, `sealed`-выход для `riddle_gate`.
- `scripts/dungeon/DungeonGenerator.gd` — подземелья (BSP) с `opts` из подлокации: NPC, враги из пула, сундуки, сейф,
  решётки (загадка/Страж), босс, выходы к соседям (назад — в стартовой комнате, вперёд — лестница за решёткой).
- **LevelBuilder** — 3D: рельеф одним мешем с вырезом пропасти, обрывы, вода (shaders/water) или туман пропасти,
  земля со стилизованным шейдером (shaders/ground: пятна, «мазки», маска тропы), невидимые стены (слой 1|4),
  кроны — коллизия только для камеры (слой 4), растительность/руины/камни через MultiMesh; подземелья: плитка Kenney
  (стены вытянуты ×2.3 под взрослых), пещера — скалы и светящиеся грибы/кристаллы, гробница — свечи и вазы.
- **SortiePlayer** — герой: камера от третьего лица (SpringArm3D, ПКМ/колесо/Q/R), WASD от камеры, бег с выносливостью,
  прыжок с койот-таймом и буфером, анимации UAL, `fall_y` → сигнал `fell`.
- **SortieEnemy** — враг: patrol → alert → chase по AStarGrid2D (только проходимые клетки), контакт → бой.
- **MovingPlatform** (AnimatableBody3D) — пинг-понг между точками с плавным разгоном, покачивание.
- **WorldStyle** — палитры земли по биому, небо/свет (`day`, `sunset`, `gloom`, `cave`), вода, костёр и частицы огня.
- **CampScene** — 3D-фон главного меню и создания героя (поляна у костра, герой).

### Сцены (`scenes/`)
- **main/Main** — стек экранов, HUD (скрыт на FULLSCREEN-экранах), тосты, баннер уровня, игровое меню (Esc на WorldTree:
  продолжить / настройки / титры / главное меню / выход). Старт — главное меню.
- **menu/MainMenu** — профили (список, двойной клик — играть), «Новый герой», «Удалить» (подтверждение), «Играть»,
  настройки, титры, выход, RU/EN. **menu/CharacterCreator** — создание героя (CampScene, вращение мышью).
  **menu/Credits** — прокручиваемые титры.
- **world/WorldMap** — 100 маркеров (`MapMarker`: биом, уровень, кольцо %, молоток «в разработке»), шейдер
  `shaders/world_map.gdshader` (море, берег, регионы биомов по Вороному, рельеф, пергамент), глифы и дороги, панорама/зум,
  панель локации. **world/LocationMap** — граф подлокаций (`NodeMarker`), тропы (найденные — сплошные со следами),
  панель с особенностями и кнопкой «Вылазка». **world/SortieWorld** — вылазка: загрузка подлокаций, переходы,
  взаимодействия (NPC, сундуки с золотом/предметами/картами, сейфы, двери-загадки, выходы), бой, мини-карта (M — крупно),
  пауза/меню, итоги (`leave`/`defeat`/`fall`).
- **shop/ShopScreen**, **character/EquipmentPanel** (кукла + инвентарь), **ui/HeroPreview** (3D-превью героя/NPC),
  **ui/ItemTile** (плитка предмета, подсказка с характеристиками).
- **character/CharacterScreen** — вкладки: Статистика, Снаряжение, Коллекция карт, Колода (`DeckBuilder`).
- **settings/SettingsScreen** — экран (+ язык), звук, управление (переназначение клавиш, чувствительность камеры).
- Остальные (knowledge/*, rewards/*, combat/*, dialogue/*, dungeon/RiddleScreen, dungeon/SafeScreen, ui/HUD) — как раньше.
  HUD: иконки «Карта мира», «Лавка», «Меню»; музыка переключается в настройках.

### Данные (`data/`)
- `world_map.json` (100 локаций: id, name/_en, biome, level, pos, status; дороги), `locations.json` (графы двух
  локаций: kind, links, features {enemies, pool, chests, npcs, safe, riddle_gate, warden, boss, platforms}, floor),
  `items.json`, `cards_catalog.json` (138), `enemies_catalog.json` (20, поле `model` + `model_size/model_tint`),
  `dialogues.json`, `riddles.json`, `safes.json`, `specializations.json`.
- `locale/en.json` — ~1030 строк (интерфейс, диалоги, загадки, сейфы, описания старых карт/врагов).

### Инструменты (`tools/`)
- `SmokeTest.tscn` (133 проверки, профили/предметы/мир/вылазка/падение/локализация; не трогает реальные профили),
  `ModelViewer.tscn` (`--model=` / `--hero=male --race=elf --weapon=Sword --anim=Idle --shot=`), `QuizReport.tscn`,
  `build_theme.gd`, `content_report.gd`.
- `gen_world_map.py`, `gen_cards.py`, `i18n/wrap.py` (обёртка русских литералов в Loc.t), `i18n/extract.py`
  (сбор ключей в en.json, `--missing out.json`), `i18n/scan.py`.
- `blender/` — сборка героев (`build_hero.py`), правки GLB (`fix_webp_glb.py`, `fix_alpha_glb.py`), копирование китов.

### Ассеты
- `assets/characters` (hero_male/female.glb, ual_anims.glb, текстуры расцветок), `assets/monsters`, `assets/weapons`,
  `assets/world/{nature,props,village}` — Quaternius, CC0 (LICENSE.txt в папках). `assets/models/dungeon` — Kenney.
- Иконки game-icons.net (CC BY 3.0, авторы в `assets/icons/game/LICENSE.txt` и в титрах), Lucide (ISC), шрифты OFL,
  звук/музыка — `assets/audio/CREDITS.txt`.

---

## Правила игры и баланс

- Старт: уровень 1, 50/50 энергии, HP = 15 + 3×уровень (+ HP снаряжения), атрибуты max_mana 10, strength 1, agility 1,
  max_stamina 10 + расовый бонус. Стартовый комплект: ржавый меч, льняная рубаха, штаны, обмотки, нарукавники.
- Знания: XP за узел один раз, +5 энергии; тесты — как раньше (зачёт 60% узел / 70% дерево, награды, перезарядка 20 ч).
- Вылазка: −10 энергии, HP восстанавливается в начале и в конце; переходы между подлокациями бесплатны; поражение
  в бою — возврат в лагерь без потерь; падение в пропасть/реку — гибель: энергия = 0, возврат на базу.
- Сундук в вылазке: 8–18 + 4×уровень локации золота, 25% предмет, 35% зелье, 20% карта; сейф: 15–30 золота, 50% предмет
  или 60% карта, +15 XP. Босс: +50 XP и сундук с картой. Побеждённые враги и открытые сундуки не возвращаются.
- Бой: атаки оружием по экипировке (sword 2+2×Сила, dagger 1+Ловк., bow 1+Ловк. сквозь Taunt, axe 3+2×Сила,
  hammer 2+Сила и сбивает щиты, spear 2+Ловк. и задевает героя, fists 1+Сила) + бонус урона вещей; броня — щит в начале
  боя; уклонение 3%×Ловкость + бонус вещей. Новые пассивы артефактов: passive_heal, passive_shield, passive_damage;
  у существ при розыгрыше работают draw, shield, damage_all, damage_split, stun_enemy, free_weapon_attack и др.

### Визуальный стиль
UI: тёмный фон #0D0D1A, акцент #7B68EE, мята #00D4AA, HP #FF6B6B, энергия #FFD700. 3D: яркий стилизованный мир
(WoW / King's Bounty): насыщенная зелень, тёплый свет, крупные деревья, туман, мягкие тени.

---

## Известные ограничения / идеи
- Реализованы 2 локации из 100; остальные показываются «в разработке».
- Контент уроков, вопросы тестов и экспорт заметок — только на русском (английский — интерфейс и игровые данные).
- `.tscn` пишутся вручную (без uid) — Godot допишет uid при пересохранении в редакторе.
- Для экспорта игры добавить `*.md` и `*.json` в include filter экспорт-пресета.
