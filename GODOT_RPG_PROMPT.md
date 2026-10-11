# CodeRealm — обзор проекта (для Claude)

Геймифицированная RPG-система изучения знаний на **Godot 4.6.3** (GDScript, рендер Compatibility, Windows).
Пользователь ежедневно изучает темы 5 специализаций (подготовка к собеседованиям) → XP, уровни, энергия →
дальше карты, карточный бой и 3D-подземелье. Проект Godot лежит в `psystem/` (res:// = `psystem/`).

**В начале каждой сессии:** прочитай `psystem/NOTES_FOR_CLAUDE.md` (правки пользователя из игры).
**После изменений:** запусти smoke-тест; после правок ThemeFactory — перегенерируй тему (команды в `psystem/README.md`).
Godot: `C:\Users\user\games\godot\Godot_v4.6.3-stable_win64_console.exe`. Редактор обычно открыт — после правок
`project.godot` пользователю нужно Project → Reload Current Project.
**Экран пользователя 1366×768.** Базовое разрешение UI — 1280×720 (stretch canvas_items/expand), все экраны должны
помещаться в 1280×720. Стартовое окно 1024×576 (override, чтобы влезать во встроенную вкладку Game редактора),
затем Settings разворачивает окно до авто-разрешения. Новые экраны регистрируй в `Main.SCREENS`.

---

## Статус итераций

- **Итерация 1 — ГОТОВА.** Структура, автолоады, парсер контента, WorldTree, MiniTree, LessonPage,
  CharacterScreen (статы/атрибуты), сохранения, HUD, тосты, баннер уровня, туториал «Путь новичка»,
  заметки для Claude + экспорт, каталоги карт/врагов (JSON), инструменты и smoke-тест.
- **Доп. к итерации 1:** базовое разрешение 1280×720 (экран пользователя 1366×768), автоподбор окна под экран,
  экран настроек (окно/разрешение/масштаб UI/VSync/громкость), звуки интерфейса, джинглы, фоновая музыка.
- **Итерация 2 — ГОТОВА.** Тесты (общий по дереву и по узлу, генератор вопросов + 105 авторских вопросов в .md),
  RewardScroll (свиток с печатью, фанфара, переворот карт), сундуки LootBox за уровни, CardVisual, каталог 38 карт
  (по 7–8 на специализацию, иконки game-icons.net), коллекция с фильтрами и просмотром карты, анимации XP-бара
  (блик, несколько уровней подряд), баннер уровня с лучами/искрами и оркестровой фанфарой. Smoke-тест: 67 проверок.
- **Итерация 3 — ГОТОВА.** Карточный бой: `scripts/combat/CombatState.gd` (логика, все ~40 эффектов, оружие/руны,
  существа, артефакты, ИИ врага, specials: double_attack, steal_card, grow, regen, armor, summon), `scenes/combat/CombatScreen.gd`
  (UI, цели, анимации, журнал, результат; Esc не выходит из боя), `CreatureToken.gd`. Сборка колоды —
  `scenes/character/DeckBuilder.gd` (вкладка «Колода»: drag&drop, кривая стоимости, автосборка, стартовый набор
  Странника 10 карт, тренировочный бой). Колода: 10–20 карт, ≤3 копии, легендарная ≤1. HP = 15 + 3×уровень
  (SaveSystem v2 мигрирует старые сохранения). Боевая музыка — Audio.push_music/pop_music.
- **Итерация 4 — ГОТОВА (изменённая концепция).** Экспедиции в «Руины Феррограда» — сломанный механический мир:
  `scenes/dungeon/DungeonWorld.gd` (3D в SubViewport, 3 этажа, HUD, мини-карта с туманом, пауза, итоги; вход с кнопки
  «Экспедиция в руины» на WorldTree, −30 энергии), `scripts/dungeon/DungeonGenerator.gd` (BSP, выход за решётками:
  загадка или Страж Моста, NPC×2, сейф, сундуки, враги по этажу, мини-босс на 2-м, босс corrupted_compiler на 3-м),
  `Player.gd`/`Enemy.gd` (Kenney Mini Dungeon, AStarGrid2D-погоня), `CharacterRig.gd`.
  Диалоги BG3-стиля: `data/dialogues.json` (6 NPC: greta, oracle, lio, rzhavchik, warden, cipher; 58 узлов),
  `scripts/dialogue/DialogueRunner.gd` + `Requirements.gd` (реплики по знаниям `{"spec","topic"|"min"|"tree_test"}`,
  проверки d20 + атрибут + бонус знаний, золото/предметы/флаги/квесты), `scenes/dialogue/DialogueScreen.gd`.
  Загадки: `data/riddles.json` (16) + `RiddleScreen.gd` (знание темы отсекает 2 неверных варианта, ошибка −2 HP).
  Сейфы: `data/safes.json` (10 Python-багов с тестами, проверены) + `SafeScreen.gd` (CodeEdit) + `scripts/utils/PythonRunner.gd`
  (запуск python с таймаутом 4 с; без Python — проверка по regex `checks`). Мир сохраняется в `world_state.json`
  (GameManager.world: flags, items, quests, stats). Ввод экспедиции регистрирует Settings._register_input.
- **Итерация 5** — полировка: Civ-дерево, переходы, баланс; идеи: больше NPC/квестов между экспедициями, торговля картами.

Smoke-тест: 96 проверок (`tools/SmokeTest.tscn`), включая автобои против всех врагов и цикл экспедиции.
Dev-аргументы Main: `--screen=combat:<enemy> [--auto=N] | dungeon[:seed] [--walk=N] | dialogue:<npc> [--pick=N] | riddle:<id> | safe:<id>`.

---

## Структура файлов (psystem/)

### Автолоады (`scripts/autoload/`, порядок важен: EventBus, Settings, ContentParser, GameManager, SaveSystem, Audio)
- **Settings** — `user://settings.cfg` (ConfigFile): window_mode (windowed/maximized/fullscreen), resolution ("auto"/"WxH"),
  ui_scale (root.content_scale_factor), vsync, master/music/sfx_volume (0..1), music_enabled, ui_sounds.
  `get_value`, `set_value` (сохраняет + применяет + сигнал `changed(key)`), `reset_to_defaults`, `apply_window`
  (центрирует окно в рабочей области экрана), `available_resolutions`, `auto_resolution`, `is_embedded()`
  (игра во вкладке Game редактора — окном не управляем).
- **Audio** — шины Music/SFX (создаются в коде), пул плееров, `play(name)`, `play_hover()`, `play_jingle(name)`
  (приглушает музыку), плейлист музыки (`next_track`, `current_track_title`, сигнал `track_changed`).
  Автоозвучка: все BaseButton через `SceneTree.node_added` (клик + тихий hover); meta `"sfx"` переопределяет звук
  ("" — без звука); кнопки с именем `BackButton` молчат (звук «назад» играет Main при pop). Звуки: click, hover, back,
  open, confirm, error, toggle, select, notify, drop, whoosh, levelup (оркестровая фанфара), reward, fanfare (длинная,
  свиток), card_flip, scroll_open, cloth, coins, chest_latch, chest_creak, book_place.
- **EventBus** — сигналы: `navigate(screen, params)`, `navigate_back`, `navigate_home`, `toast(text, kind)`,
  `progress_changed(spec_id)`, `notes_exported(path)`. Хелперы `go()`, `back()`, `notify()`.
- **ContentParser** — парсит `content/*.md` по списку `data/specializations.json` (+ автообнаружение новых .md).
  API: `get_all_spec_ids`, `get_specialization`, `get_spec_meta/name/color`, `get_node_data(id)`, `get_parent_node`,
  `get_flat_nodes(spec)` (порядок чтения), `get_neighbor_node(id, ±1)`, `count_nodes`, `total_node_count`,
  `plain_preview(md)`, `reload()`. Кэша нет — парсинг при каждом запуске (быстро).
- **GameManager** — состояние: `player_data`, `knowledge_progress` (id → "learned"/"in_progress"),
  `rewarded_nodes` (за какие узлы XP уже выдан — защита от фарма после сброса), `claude_notes` (id → текст,
  ключ `_general` — общие заметки), `card_collection` (card_id → кол-во), `combat_deck`.
  Функции: `gain_xp`, `gain_energy`, `spend_energy`, `add_gold`, `increase_attribute`, `learn_node` (→ XP),
  `unlearn_node`, `mark_in_progress`, `reset_spec`, `count_learned`, `total_learned`, `subnode_progress`,
  `get/set_note`, `add_card_to_collection`, `collection_size`, `reset_all`, `default_player_data()`.
  Тесты: `test_records` ("tree:<spec>"/"node:<id>" → {attempts, passes, best, total, last_pass}), `test_record(key)`,
  `complete_tree_test(spec, correct, total)` (первый зачёт: все обязательные узлы learned+rewarded, XP = `tree_xp_bonus`
  (сумма xp_reward главных узлов), +20 энергии, карты; повтор — 1 карта, +10 энергии, 25% XP раз в 20 ч),
  `complete_node_test(node, correct, total)` (узел изучен + бонус difficulty×3 один раз), `tree_test_cooldown_left`.
  Сундуки: `player_data.lootboxes` (+1 за уровень, +2 на каждом 5-м), `lootbox_count`, `open_lootbox()` → [card_id].
  Сигналы: `xp_gained`, `level_up`, `energy_changed`, `gold_changed`, `knowledge_unlocked`, `knowledge_reset`, `player_changed`.
- **SaveSystem** — `user://saves/`: `player_save.json`, `knowledge_progress.json` {progress, rewarded, notes, tests},
  `card_collection.json` {collection, deck}. Атомарная запись (.tmp), приведение float→int после JSON,
  дозаполнение новых полей дефолтами, автосохранение по сигналам GameManager (`request_save` — отложенное),
  `wipe()`, `save_dir` подменяется тестами/скриншотами.

### Утилиты (`scripts/utils/`, class_name; в режиме `--script` автолоады недоступны — тесты запускать сценой)
- **XPCalculator** — весь баланс: `xp_to_next(level)=(level+1)*10`, HP=уровень, `node_xp` (главный difficulty×10,
  подузел difficulty×5), энергия (старт/макс 50, +5 за узел, +20 за тест дерева, вход в данж 30), колода 10–20,
  словарь `ATTRIBUTES` (имя, старт, описание, иконка), `stars()`, `dodge_chance()`. Тесты: зачёт дерева 70%,
  узла 60%, перезарядка повтора 20 ч; шансы редкостей; `node_test_bonus`, `tree_card_count`, `lootboxes_for_level`.
- **QuizGenerator** — вопросы тестов: `for_tree(spec)` (10, только обязательные узлы, по возможности разные темы),
  `for_node(node)` (5 для раздела, 3 для подтемы), `pass_threshold`. Виды: authored (из `<!-- quiz -->`), fill_gap
  (пропуск **термина** в строке урока, отвлекающие — термины других тем), answer_hint (узлы-вопросы AI: что ожидают
  в ответе), parent/member/true_false (структура дерева). Квоты: ~50% authored, ~30% fill_gap/answer_hint, остальное структура.
- **Palette** — цвета, шрифты, `icon(name)` (Lucide SVG из assets/icons), `game_icon(name)` (game-icons.net из
  assets/icons/game), `box()`/`glow_box()` (StyleBoxFlat), `RARITY_COLORS`.
- **ThemeFactory** — строит Theme → `assets/ui/theme.tres` (генерируется `tools/build_theme.gd`). Вариации:
  Label: TitleLabel, HeaderLabel, MonoLabel, StatLabel, DimLabel; Button: AccentButton, MintButton, DangerButton,
  GhostButton; PanelContainer: CardPanel, GlassPanel, HudPanel; ProgressBar: HPBar, XPBar, EnergyBar, MintBar.
- **MarkdownBBCode** — `to_bbcode(md, accent)`: заголовки, жирный/курсив, код, блоки кода с подсветкой
  (комментарии по языку фенса), списки, цитаты, таблицы, ссылки.
- **ClaudeNotesExporter** — `export_all()` → `NOTES_FOR_CLAUDE.md` (в редакторе — корень проекта, в билде — рядом с exe).
  Вызывается при сохранении заметки урока, из диалога «Заметки» в HUD, при выходе.
- **CardDatabase** — ленивая загрузка `data/cards_catalog.json` / `enemies_catalog.json` (числа → int), `get_card`,
  `cards_for_spec`, `sort_by_rarity`, `avg_tree_difficulty`, `roll_rarity(d)`, `roll_card(pool, d)`,
  `roll_tree_cards(spec, count=-1)`, названия редкостей и типов.

### Сцены (`scenes/`)
- **main/Main** — корень: фон (shader starfield), `ScreenRoot` (стек экранов), HUD, Overlay (тосты, баннер уровня).
  Экраны: `SCREENS` = world, mini_tree, lesson, character, settings, test, reward, lootbox. Экран реализует
  `setup(params)` и `on_resume()`; `params.replace=true` заменяет верхний экран, `params.overlay=true` — оверлей поверх
  видимого экрана (reward, lootbox). Esc/мышь «назад» — pop. Баннер уровня: лучи (rays shader), искры, фанфара.
  Dev-аргументы: `--screen=` (world | mini:<spec> | lesson:<id> | character[:tab] | settings | test:<spec> [--answer=N
  [--finish]] | reward:<spec> | lootbox [--open]), `--shot=`, `--shot-delay=`, `--demo` (прогресс + 14 карт), `--levelup`, `--toast=`.
- **ui/HUD** — уровень, XP-бар (блик bar_shine; при нескольких уровнях доливается до конца и заполняется заново),
  HP, энергия, золото, кнопка сундука «×N» (пульсирует, если есть), «+N очк.», «Заметки», «Персонаж», музыка, настройки.
  Ширина HUD рассчитана на 1280 px — при добавлении элементов проверяй, что строка помещается.
- **knowledge/WorldTree** — «Древо знаний»: центральное «Ядро знаний» + сферы специализаций по эллипсу (любое
  количество; масштаб сфер `SpecOrb.base_scale` и эллипс подстраиваются под размер экрана), линии Line2D с шейдером,
  счётчик «Знания: X / Y», панель туториала «Путь новичка» (левый верхний угол).
- **knowledge/SpecOrb** — светящаяся сфера (shader orb: цвет, кольцо прогресса, hover).
- **knowledge/MiniTree** — колонки: главный узел + подузлы, связи Line2D, баннеры групп (тиры), легенда,
  прогресс, сброс (ConfirmationDialog), прокрутка колесом/перетаскиванием, кнопка «Пройти общий тест»
  (тултип: награды, лучший результат, перезарядка).
- **knowledge/KnowledgeNode** — карточка узла: состояния не начато (пунктир) / в процессе / изучено (свечение, ✓) /
  фиолетовый; кастомный тултип с превью.
- **knowledge/LessonPage** — заголовок, хлебные крошки, звёзды, частота вопроса, контент (RichTextLabel),
  «Отметить как изученное (+XP)» с частицами, «Снять отметку», «Пройти тест» (тест узла), Пред./След. (←/→),
  список подтем, заметки для Claude (автосохранение 1.2 с).
- **knowledge/TestScreen** — тест (mode tree/node): вопрос (markdown), 2–4 варианта (клавиши 1–4), подсветка верного/
  неверного, пояснение, прогресс; итог: счёт, награды, разбор ответов, «Открыть награду» (→ reward, replace+overlay),
  «Пройти ещё раз», назад. Награды начисляются в момент завершения теста.
- **rewards/RewardScroll** — оверлей: пергамент (parchment shader) с деревянными валиками, сургучная печать
  (клик или авто через 2.2 с), разворачивание + фанфара, строки наград, карты рубашкой → переворот (rare/legendary — вспышка).
- **rewards/LootBox** — оверлей: сундук (game-icons chest/open-chest), тряска, щелчок замка, карта вылетает и переворачивается.
- **combat/CardVisual** — карта 200×280 (`card_scale`): кристалл стоимости, имя, арт (card_art shader + иконка),
  тип·редкость, описание, атака/защита существ или флейвор, «×N», рамка card_glow (legendary — shimmer), `locked`
  (неполученная — силуэт «?»), `show_back()`, `flip_to_front()`, сигнал `clicked(card_id)`.
- **settings/SettingsScreen** — две карточки «Экран» и «Звук» (строятся в коде), «Следующий трек», сброс настроек,
  подсказка для режима встроенного запуска в редакторе. Открывается шестерёнкой в HUD.
- **character/CharacterScreen** — вкладки: Статистика (аватар-сфера, HP/XP/энергия, золото, уклонение, атрибуты с «+»,
  прогресс по специализациям), Коллекция карт (CardVisual-сетка, фильтры редкость/специализация, «Показать
  неполученные», «Открыть сундук (N)», клик — крупный просмотр карты), Колода (заглушка). Кнопки «Папка сохранений»,
  «Начать заново».
- Папка `scenes/dungeon` — пустая (итерация 4).

### Прочее
- `shaders/`: `starfield` (фон), `orb` (сферы), `tree_connection` (линии; альфа цвета Line2D = «активность» связи),
  `card_glow` (рамка/shimmer), `card_art` (генеративный арт), `parchment` (свиток), `rays` (лучи), `bar_shine` (блик бара).
- `data/`: `specializations.json` (id, name, short, color, icon, content_file, description), `cards_catalog.json`
  (38 карт: id, name, type, rarity, crystal_cost, attack/defense, description, effect, flavor_text, from_specialization,
  art_color, icon — имя файла из assets/icons/game),
  `enemies_catalog.json` (5 врагов).
- `content/`: python_developer, python_backend, level_designer (написаны Claude), ai_developer (= файл пользователя
  `Documents/ed/interview_questions_junior_ai_engineer.md`), game_designer (программа от Claude + исследование
  пользователя `Downloads/game_designer_skills_2026.md` как группа). Всего ~395 узлов.
- `tools/`: `build_theme.gd`, `content_report.gd`, `SmokeTest.tscn` + `smoke_test.gd`, `QuizReport.tscn` +
  `quiz_report.gd` (сколько вопросов каждого вида генерируется, `-- --sample` — примеры).
- `assets/`: шрифты JetBrains Mono / Inter / Unbounded (OFL), иконки Lucide (ISC, перекрашены в белый, тонируются modulate),
  `icons/game` — game-icons.net (CC BY 3.0, авторы в LICENSE.txt), `audio/ui`, `audio/rpg` и `audio/jingles` — Kenney (CC0)
  + фанфары Spring Spring (levelup — CC-BY 4.0, fanfare_reward — CC0), `audio/music` — 3 CC0-трека (`audio/CREDITS.txt`).

---

## Формат контента

- Первый `# ` — название документа; последующие `# ` — **группы** узлов (тиры). «ТИР A/B» → сложность 1, C → 2,
  D → 3, E → 3 + фиолетовый. Контент сразу под группой без `##` превращается в узел с именем группы.
- `## ` — главный узел, `### ` — подузел. В разделе без `###` строки `` `[NN/100]` **Вопрос** `` становятся подузлами
  (поле `frequency`).
- Маркеры в заголовках: `<!-- difficulty: N -->`, `<!-- optional -->` (фиолетовый), `<!-- skip -->`.
- Авторские вопросы теста — отдельной строкой в тексте узла: `<!-- quiz: Вопрос | +Верный | Неверный | ... || Пояснение -->`
  (ровно один вариант с `+`; не видны ни в .md-превью, ни в игре). Сейчас: python_developer 36, python_backend 29,
  level_designer 20, game_designer 20; ai_developer — генерация из подсказок вопросов. Для fill_gap важно выделять
  ключевые **термины** жирным (1–3 слова).
- Эвристики: сложность по словам (продвинут/advanced/архитект/middle/senior → 3, средн/junior → 2, основ/базов/trainee → 1),
  фиолетовый по словам (дополнит/опционал/бонус/нишев). Подузел наследует сложность и «фиолетовость» родителя.
- **ID узла** = `spec_id/слаг_раздела[/слаг_подраздела]` (слаг: lowercase, кириллица сохраняется). Переименование
  заголовка меняет ID → теряется прогресс узла (заметки попадут в раздел «удалённые узлы» экспорта).
- Узел: id, spec_id, title, content (md), difficulty 1–3, xp_reward, is_purple, is_main, group, subnodes / parent_id,
  frequency, quiz (Array {question, options, correct, explanation}).

---

## Правила игры и баланс (реализовано)

- Старт: уровень 1, 0 XP, 50/50 энергии, HP = уровень, атрибуты: max_mana 10, strength 1, agility 1, max_stamina 10.
- Level up: +1 очко атрибутов, HP = новый уровень, XP до следующего = (уровень+1)×10.
- Изучение узла: XP = xp_reward (один раз за узел навсегда), +5 энергии. Открытие урока → статус «в процессе».
- Сброс дерева снимает отметки, XP и заметки остаются.
- Тест узла: зачёт ≥60% → узел изучен (+его XP, если не выдавался) + бонус difficulty×3 (один раз).
- Общий тест дерева (10 вопросов): зачёт ≥70%. Первый зачёт: обязательные узлы изучены, XP = сумма xp_reward главных
  узлов, +20 энергии, 1–3 карты (round средней сложности дерева) из пула специализации. Повтор: раз в 20 ч — 1 карта,
  +10 энергии, 25% XP; чаще — без награды. Новый уровень → сундук (на каждом 5-м — 2); в сундуке 1 карта из всего
  каталога, сложность для шансов = 1 + уровень/10.
- Атрибуты: strength +2 урона мечом/луком, agility +1 урон кинжалом и +3% уклонения, max_mana — руны, max_stamina — оружие.

---

## Спецификация будущих итераций (сжатое ТЗ)

### Итерация 2: тесты и награды — реализована (см. выше)
Идеи на потом: таймер/серии ответов, тесты по слабым темам (по ошибкам из test_records), развёрнутые ответы для ai_developer.

### Итерация 3: карточный бой (упрощённый Magic с UX Hearthstone)
- Ресурсы: **кристаллы** (1→10, +1 к максимуму каждый ход, восстанавливаются), **мана** (руны, не восполняется
  сама; = max_mana), **выносливость** (атаки оружием; = max_stamina). HP игрока = GameManager hp.
- Ход: начало (+1 кристалл, добор до 5 карт; стартовая рука 4) → основная фаза (карты, руны, оружие) → конец (ход врага).
- Типы карт: spell, creature (attack/defense), artifact (пассив). Эффекты из `effect` в каталоге: damage, draw,
  next_spell_discount, taunt, isolate_enemy, execute_below, divine_shield, reveal_enemy_hand, multi_attack,
  passive_crystal_regen, control_enemy_creature, extra_play/next_free, checkpoint, on_death_resurrect.
- ИИ врага: атакует самое слабое существо игрока, иначе игрока напрямую; special: double_attack, steal_card; is_miniboss.
- Поражение: HP игрока → 1, без потерь. Победа: xp_reward, gold_reward врага, +10 энергии. Экран результата CombatResult.
- Колода: сборка drag&drop из коллекции, максимум 20, минимум 10 для данжа.
- Словарь эффектов карт (каталог уже использует): damage, damage_all, damage_random [min,max], damage_split,
  damage_per_creature, execute_below, draw, discover, next_spell_discount, spell_discount, first_card_discount,
  turn_discount, extra_play/next_free, shield, heal, self_damage, buff_attack{+duration}, aura_attack, set_all_attack,
  taunt, isolate_enemy, stun_enemy, freeze_enemy_creature, limit_enemy_attacks, control_enemy_creature{max_attack,duration},
  copy_enemy_attack, multi_attack, extra_attack_end_turn, summon_copies{count,attack,defense}, on_death_resurrect,
  divine_shield, reveal_enemy_hand, checkpoint, passive_crystal_regen, passive_draw{every}, passive_stamina, hand_size,
  free_weapon_attack, boss_damage_bonus, max_crystal_bonus, return_spells.

### Итерация 4: подземелье (3D top-down roguelike)
- Вход стоит 30 энергии (проверка колоды ≥10). Этаж: +10 золота, +5 энергии. Смерть: −20% золота.
- Генерация (BSP): комнат 5 + этаж×2, типы start/normal/treasure(20%)/boss; коридоры; враги и лут по этажу.
- Player: CharacterBody3D, WASD (move_forward/back/left/right — добавить в Input Map), камера сверху (y≈10, −65°), пауза — Space.
- Enemy: состояния PATROL → ALERT («!», 0.8 с) → CHASE → RETURN; VISION_RANGE 8, скорость патруля 1.5, погони 3.5;
  контакт < 1.2 м → карточный бой с enemy_data из каталога. Увеличивать `player_data.dungeon_runs` (туториал, шаг 4).

### Итерация 5: полировка
Civ-style MiniTree (стрелки, ряды по сложности), card_glow shader, переходы между экранами, звуки, баланс XP.

### Визуальный стиль
Dark fantasy + tech: фон #0D0D1A, акцент #7B68EE, мята #00D4AA (изучено), HP #FF6B6B, энергия #FFD700,
фиолетовый #9B59B6. Цвета специализаций: python_developer #4A9EFF, ai_developer #9B59B6, python_backend #2ECC71,
game_designer #E74C3C, level_designer #F39C12. UI-шрифт моноширинный, контент — Inter, заголовки — Unbounded.
Карты: рамка по редкости, иллюстрация сверху (генеративный шейдер/иконка), текст снизу.

### Планы на расширение
- 6-я специализация «университетский граф знаний» — просто добавить .md в content/ (+ запись в specializations.json).
- Для экспорта игры добавить `*.md` в include filter экспорт-пресета (иначе контент не попадёт в билд).

---

## Известные ограничения / идеи
- Контент ai_developer — только вопросы с подсказками (без развёрнутых ответов); можно дописывать по заметкам.
- Нет ленивой подгрузки узлов в MiniTree (до ~150 узлов работает без проблем).
- `.tscn` пишутся вручную (без uid) — Godot сам допишет uid при пересохранении в редакторе.
