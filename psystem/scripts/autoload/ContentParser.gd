extends Node
## Парсит .md файлы из content/ в деревья знаний.
##
## Список специализаций и их метаданные — data/specializations.json.
## Любой .md в content/, не упомянутый в json, подхватывается автоматически
## как новая специализация (расширяемость без изменения кода).
##
## Структура .md:
##   `# Заголовок`      — первый: название документа; последующие: группа (тир) узлов
##   `## Раздел`        — главный узел дерева
##   `### Подраздел`    — подузел
##   `` `[NN/100]` **Вопрос** `` — если в разделе нет ###, каждый такой вопрос становится подузлом
## Маркеры в заголовках (HTML-комментарии, в превью .md не видны):
##   <!-- difficulty: 2 -->  <!-- optional -->  <!-- skip -->
## Авторские вопросы теста (отдельной строкой в тексте узла, в превью .md не видны):
##   <!-- quiz: Вопрос? | +Правильный | Неверный | Неверный || Пояснение -->

const SPECS_FILE := "res://data/specializations.json"
const CONTENT_DIR := "res://content/"
const EXCLUDED_FILES := ["README.md"]

const DIFF3_WORDS := ["продвинут", "advanced", "архитект", "middle", "senior", "глубже", "нишев", "expert", "эксперт"]
const DIFF2_WORDS := ["средн", "intermediate", "junior"]
const DIFF1_WORDS := ["trainee", "intern", "основ", "базов", "введение", "beginner"]
const OPTIONAL_WORDS := ["дополнит", "опционал", "бонус", "optional", "bonus", "нишев"]
const FALLBACK_COLORS := ["#1ABC9C", "#E67E22", "#3498DB", "#E84393", "#00CEC9", "#FDCB6E"]

## spec_id -> {id, title, intro, nodes: Array[node], connections: Array[{from, to}]}
var specializations: Dictionary = {}
## spec_id -> {id, name, short, color, icon, content_file, description}
var spec_meta: Dictionary = {}
var spec_order: Array[String] = []

var _node_index: Dictionary = {}   # node_id -> node dict
var _flat: Dictionary = {}         # spec_id -> Array узлов в порядке чтения (main, его subs, ...)

var _re_marker := RegEx.new()
var _re_tier := RegEx.new()
var _re_question := RegEx.new()


func _ready() -> void:
	_re_marker.compile("<!--(.*?)-->")
	_re_tier.compile("(?:ТИР|TIER|Тир|Tier)\\s+([A-EАВСЕ])\\b")
	_re_question.compile("^`\\[(\\d+)/100\\]`\\s*\\*\\*(.+?)\\*\\*")
	reload()


## Полная перезагрузка контента (можно вызывать во время игры).
func reload() -> void:
	specializations.clear()
	spec_meta.clear()
	spec_order.clear()
	_node_index.clear()
	_flat.clear()
	for meta in _load_specs_meta():
		var spec_id: String = meta.id
		spec_meta[spec_id] = meta
		spec_order.append(spec_id)
		specializations[spec_id] = _parse_md_file(spec_id, meta.content_file)
		_index_spec(spec_id)


# ---------------------------------------------------------------- API

func get_specialization(spec_id: String) -> Dictionary:
	return specializations.get(spec_id, {})


func get_all_spec_ids() -> Array[String]:
	return spec_order


## Метаданные специализации; name, short и description переводятся (locale/en.json).
func get_spec_meta(spec_id: String) -> Dictionary:
	var m: Dictionary = spec_meta.get(spec_id, {})
	if m.is_empty() or Loc.lang() == "ru":
		return m
	var out := m.duplicate()
	for key in ["name", "short", "description"]:
		if out.has(key):
			out[key] = Loc.t(String(out[key]))
	return out


func get_spec_name(spec_id: String) -> String:
	return get_spec_meta(spec_id).get("name", spec_id)


func get_spec_color(spec_id: String) -> Color:
	return Color.from_string(get_spec_meta(spec_id).get("color", "#7B68EE"), Color("#7B68EE"))


func get_node_data(node_id: String) -> Dictionary:
	return _node_index.get(node_id, {})


## Для подузла — его главный узел, для главного — пустой словарь.
func get_parent_node(node_id: String) -> Dictionary:
	var node := get_node_data(node_id)
	return get_node_data(node.get("parent_id", ""))


## Все узлы специализации в порядке чтения: главный, его подузлы, следующий главный...
func get_flat_nodes(spec_id: String) -> Array:
	return _flat.get(spec_id, [])


## Соседний узел в порядке чтения (step = -1 / +1). Пустой словарь, если его нет.
func get_neighbor_node(node_id: String, step: int) -> Dictionary:
	var node := get_node_data(node_id)
	var flat := get_flat_nodes(node.get("spec_id", ""))
	for i in flat.size():
		if flat[i].id == node_id:
			var j := i + step
			return flat[j] if j >= 0 and j < flat.size() else {}
	return {}


func count_nodes(spec_id: String) -> int:
	return get_flat_nodes(spec_id).size()


func total_node_count() -> int:
	var total := 0
	for spec_id in spec_order:
		total += count_nodes(spec_id)
	return total


## Текст без markdown-разметки для тултипов и превью.
func plain_preview(md: String, max_len: int = 220) -> String:
	var out := ""
	var in_code := false
	for line in md.split("\n"):
		var s := line.strip_edges()
		if s.begins_with("```"):
			in_code = not in_code
			continue
		if in_code or s == "" or s == "---" or s.begins_with("|") or s.begins_with("<!--"):
			continue
		s = s.trim_prefix("> ").trim_prefix("- ").trim_prefix("* ")
		s = s.replace("**", "").replace("`", "").replace("_", " ").replace("#", "")
		out += s + " "
		if out.length() > max_len:
			break
	out = out.strip_edges()
	if out.length() > max_len:
		out = out.substr(0, max_len - 1) + "…"
	return out


# ---------------------------------------------------------------- Загрузка метаданных

func _load_specs_meta() -> Array:
	var result: Array = []
	var known_files := {}
	if FileAccess.file_exists(SPECS_FILE):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(SPECS_FILE))
		if parsed is Dictionary:
			for meta in parsed.get("specializations", []):
				if not meta is Dictionary or not meta.has("id"):
					continue
				var m: Dictionary = meta.duplicate()
				m.id = String(m.id)
				if not m.has("content_file"):
					m.content_file = CONTENT_DIR + m.id + ".md"
				m.merge({"name": m.id, "short": m.get("name", m.id), "color": "#7B68EE",
					"icon": "res://assets/icons/book-open.svg", "description": ""})
				known_files[m.content_file.get_file()] = true
				result.append(m)
	else:
		push_warning("ContentParser: не найден " + SPECS_FILE)

	# Автообнаружение новых .md файлов
	var dir := DirAccess.open(CONTENT_DIR)
	if dir:
		var files := Array(dir.get_files())
		files.sort()
		for file_name in files:
			if not file_name.ends_with(".md") or known_files.has(file_name) or file_name in EXCLUDED_FILES:
				continue
			var spec_id: String = file_name.get_basename()
			result.append({
				"id": spec_id,
				"name": spec_id.capitalize(),
				"short": spec_id.capitalize(),
				"color": FALLBACK_COLORS[result.size() % FALLBACK_COLORS.size()],
				"icon": "res://assets/icons/book-open.svg",
				"content_file": CONTENT_DIR + file_name,
				"description": "",
			})
	return result


# ---------------------------------------------------------------- Парсинг .md

func _parse_md_file(spec_id: String, path: String) -> Dictionary:
	var spec := {"id": spec_id, "title": "", "intro": "", "nodes": [], "connections": []}
	if not FileAccess.file_exists(path):
		push_warning("ContentParser: файл контента не найден: " + path)
		return spec

	var lines := FileAccess.get_file_as_string(path).replace("\r", "").split("\n")
	var used_ids := {}
	var group := {"title": "", "difficulty": 0, "purple": false}
	var node = null      # текущий главный узел (Dictionary) или null
	var sub = null       # текущий подузел или null
	var skipping := false
	var in_code := false

	for line in lines:
		var stripped := line.strip_edges()
		var is_fence := stripped.begins_with("```") or stripped.begins_with("~~~")

		if not in_code and not is_fence:
			# --- Авторский вопрос теста
			if stripped.begins_with("<!-- quiz:") or stripped.begins_with("<!--quiz:"):
				var quiz := _parse_quiz(stripped)
				var target = sub if sub != null else node
				if not quiz.is_empty() and target != null:
					target.quiz.append(quiz)
				continue

			# --- # Документ / группа
			if line.begins_with("# "):
				var info := _parse_heading(line.substr(2))
				if spec.title == "" and spec.nodes.is_empty() and node == null:
					spec.title = info.title
				else:
					node = null
					sub = null
					skipping = info.skip
					var tier := _tier_info(info.title)
					group = {
						"title": info.title,
						"difficulty": info.difficulty if info.difficulty > 0 else tier.difficulty,
						"purple": info.purple or tier.purple or _is_additional(info.title),
					}
				continue

			# --- ## Главный узел
			if line.begins_with("## "):
				var info := _parse_heading(line.substr(3))
				skipping = info.skip
				sub = null
				node = null
				if not skipping:
					node = _make_main_node(spec_id, info, group, used_ids)
					spec.nodes.append(node)
				continue

			# --- ### Подузел
			if line.begins_with("### ") and not skipping:
				var info := _parse_heading(line.substr(4))
				if node == null:
					node = _make_main_node(spec_id, info, group, used_ids)
					spec.nodes.append(node)
					sub = null
					continue
				if info.skip:
					sub = {"_discard": true, "content": "", "quiz": []}
					continue
				node._mode = "headings"
				sub = _make_sub_node(node, info, used_ids)
				node.subnodes.append(sub)
				continue

			# --- `[NN/100]` **Вопрос** — подузел-вопрос
			if node != null and node._mode != "headings":
				var m := _re_question.search(stripped)
				if m:
					node._mode = "questions"
					var qinfo := {"title": m.get_string(2).strip_edges(), "difficulty": 0, "purple": false, "skip": false}
					sub = _make_sub_node(node, qinfo, used_ids)
					sub.frequency = m.get_string(1).to_int()
					node.subnodes.append(sub)
					var rest := stripped.substr(m.get_end()).strip_edges()
					if rest != "":
						sub.content += rest + "\n"
					continue

		if is_fence:
			in_code = not in_code

		if skipping:
			continue
		if sub != null:
			sub.content += line + "\n"
		elif node != null:
			node.content += line + "\n"
		elif group.title != "" and stripped != "" and stripped != "---":
			# Контент сразу под группой без ## — группа сама становится узлом
			node = _make_main_node(spec_id, {"title": group.title, "difficulty": 0, "purple": false}, group, used_ids)
			spec.nodes.append(node)
			node.content += line + "\n"
		else:
			spec.intro += line + "\n"

	# Финализация: чистим контент, считаем XP, убираем служебные поля
	spec.intro = _clean_content(spec.intro)
	for n in spec.nodes:
		n.erase("_mode")
		n.content = _clean_content(n.content)
		n.xp_reward = XPCalculator.node_xp(n.difficulty, true)
		var kept: Array = []
		for s in n.subnodes:
			if s.get("_discard", false):
				continue
			s.content = _clean_content(s.content)
			s.xp_reward = XPCalculator.node_xp(s.difficulty, false)
			kept.append(s)
		n.subnodes = kept

	for i in range(spec.nodes.size() - 1):
		spec.connections.append({"from": spec.nodes[i].id, "to": spec.nodes[i + 1].id})
	return spec


func _make_main_node(spec_id: String, info: Dictionary, group: Dictionary, used_ids: Dictionary) -> Dictionary:
	var difficulty: int = info.difficulty
	if difficulty == 0:
		difficulty = _estimate_difficulty(info.title)
	if difficulty == 0:
		difficulty = group.difficulty if group.difficulty > 0 else 1
	return {
		"id": _unique_id(spec_id, info.title, used_ids),
		"spec_id": spec_id,
		"title": info.title,
		"content": "",
		"difficulty": difficulty,
		"xp_reward": 0,
		"is_purple": info.purple or group.purple or _is_additional(info.title),
		"is_main": true,
		"group": group.title,
		"subnodes": [],
		"quiz": [],
		"_mode": "",
	}


func _make_sub_node(parent: Dictionary, info: Dictionary, used_ids: Dictionary) -> Dictionary:
	var difficulty: int = info.difficulty
	if difficulty == 0:
		difficulty = _estimate_difficulty(info.title)
	if difficulty == 0:
		difficulty = parent.difficulty
	return {
		"id": _unique_id(parent.id, info.title, used_ids),
		"spec_id": parent.spec_id,
		"parent_id": parent.id,
		"title": info.title,
		"content": "",
		"difficulty": difficulty,
		"xp_reward": 0,
		"is_purple": info.purple or parent.is_purple or _is_additional(info.title),
		"is_main": false,
		"frequency": 0,
		"quiz": [],
	}


## `<!-- quiz: Вопрос | +Верный | Неверный ... || Пояснение -->` → {question, options, correct, explanation}
func _parse_quiz(line: String) -> Dictionary:
	var body := line.trim_prefix("<!--").trim_suffix("-->").strip_edges()
	body = body.substr(body.find(":") + 1).strip_edges()
	var explanation := ""
	if "||" in body:
		explanation = body.get_slice("||", 1).strip_edges()
		body = body.get_slice("||", 0)
	var parts := body.split("|")
	if parts.size() < 3:
		return {}
	var options: Array = []
	var correct := -1
	for i in range(1, parts.size()):
		var opt := parts[i].strip_edges()
		if opt.begins_with("+"):
			if correct != -1:
				return {}
			correct = options.size()
			opt = opt.substr(1).strip_edges()
		if opt != "":
			options.append(opt)
	if correct == -1:
		return {}
	return {"question": parts[0].strip_edges(), "options": options, "correct": correct, "explanation": explanation}


## Разбирает текст заголовка: убирает маркеры <!-- ... --> и markdown, возвращает флаги.
func _parse_heading(raw: String) -> Dictionary:
	var info := {"title": "", "difficulty": 0, "purple": false, "skip": false}
	for m in _re_marker.search_all(raw):
		for part in m.get_string(1).to_lower().replace(";", ",").split(","):
			var p := part.strip_edges()
			if p.begins_with("difficulty") or p.begins_with("сложность"):
				info.difficulty = clampi(p.get_slice(":", 1).strip_edges().to_int(), 1, 3)
			elif p in ["optional", "purple", "дополнительно"]:
				info.purple = true
			elif p == "skip":
				info.skip = true
	var title := _re_marker.sub(raw, "", true)
	info.title = title.replace("**", "").replace("`", "").strip_edges()
	return info


## Тиры вида "ТИР A ... ТИР E" в заголовках групп: A/B → 1, C → 2, D/E → 3, E — дополнительный.
func _tier_info(title: String) -> Dictionary:
	var m := _re_tier.search(title)
	if m == null:
		return {"difficulty": _estimate_difficulty(title), "purple": false}
	var letter := m.get_string(1)
	match letter:
		"A", "А", "B", "В":
			return {"difficulty": 1, "purple": false}
		"C", "С":
			return {"difficulty": 2, "purple": false}
		"D":
			return {"difficulty": 3, "purple": false}
		_:
			return {"difficulty": 3, "purple": true}


## Эвристика сложности по ключевым словам. 0 — не удалось определить.
func _estimate_difficulty(title: String) -> int:
	var t := title.to_lower()
	for w in DIFF3_WORDS:
		if w in t:
			return 3
	for w in DIFF2_WORDS:
		if w in t:
			return 2
	for w in DIFF1_WORDS:
		if w in t:
			return 1
	return 0


## Фиолетовые узлы — дополнительные, не обязательные.
func _is_additional(title: String) -> bool:
	var t := title.to_lower()
	for w in OPTIONAL_WORDS:
		if w in t:
			return true
	return false


func _unique_id(base: String, title: String, used_ids: Dictionary) -> String:
	var slug := _slugify(title)
	if slug == "":
		slug = "node"
	var id := base + "/" + slug
	var n := 2
	while used_ids.has(id):
		id = "%s/%s_%d" % [base, slug, n]
		n += 1
	used_ids[id] = true
	return id


func _slugify(text: String) -> String:
	var out := ""
	var last_sep := true
	for ch in text.to_lower():
		var c := ch.unicode_at(0)
		var ok := (c >= 48 and c <= 57) or (c >= 97 and c <= 122) or (c >= 0x0430 and c <= 0x044F) or c == 0x0451
		if ok:
			out += ch
			last_sep = false
		elif not last_sep:
			out += "_"
			last_sep = true
	out = out.trim_suffix("_")
	if out.length() > 48:
		out = out.substr(0, 48).trim_suffix("_")
	return out


## Убирает пустые строки и разделители "---" по краям.
func _clean_content(text: String) -> String:
	var lines := Array(text.split("\n"))
	while not lines.is_empty() and lines[0].strip_edges() in ["", "---"]:
		lines.pop_front()
	while not lines.is_empty() and lines[-1].strip_edges() in ["", "---"]:
		lines.pop_back()
	return "\n".join(lines)


func _index_spec(spec_id: String) -> void:
	var flat: Array = []
	for node in specializations[spec_id].nodes:
		_node_index[node.id] = node
		flat.append(node)
		for sub in node.subnodes:
			_node_index[sub.id] = sub
			flat.append(sub)
	_flat[spec_id] = flat
