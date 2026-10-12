class_name QuizGenerator
extends RefCounted
## Генерация вопросов теста из контента дерева знаний.
##
## Вопрос: {question (markdown), options: Array[String], correct: int, explanation, node_id, kind, priority}
## Виды (kind), по убыванию ценности:
##   authored    — авторский вопрос <!-- quiz: ... --> из .md                   (priority 3)
##   fill_gap    — пропуск выделенного **термина** в предложении из урока       (priority 2)
##   answer_hint — «что ожидают в ответе на вопрос собеса» (узлы-вопросы)       (priority 2)
##   definition  — «о каком понятии речь»: определение из урока → термин         (priority 2)
##   term_fact   — «что верно о термине»: верное определение среди чужих        (priority 1)
## Вопросы о структуре дерева («к какому разделу относится тема», «какая тема входит в раздел»)
## проверяют не знания, а оглавление, — их нет.

const NODE_TEST_MAIN := 5
const NODE_TEST_SUB := 3
const TREE_TEST := 10
const TRUE_TEXT := "Верно"
const FALSE_TEXT := "Неверно"
const BLANK := "＿＿＿＿"   # полноширинные подчёркивания — не конфликтуют с markdown-курсивом

static var _re_bold: RegEx
static var _re_numbered: RegEx
static var _re_def: RegEx


## Тест по одному узлу (главный узел — вместе с подтемами).
static func for_node(node: Dictionary) -> Array:
	var ctx := _context(node.get("spec_id", ""))
	var nodes: Array = [node]
	if node.get("is_main", false):
		nodes.append_array(node.get("subnodes", []))
	var count := NODE_TEST_MAIN if node.get("is_main", false) else NODE_TEST_SUB
	return _pick(_collect(nodes, ctx), count, node.get("is_main", false))


## Общий тест по дереву: только обязательные (не фиолетовые) узлы, по возможности разные темы.
static func for_tree(spec_id: String) -> Array:
	var ctx := _context(spec_id)
	var nodes: Array = []
	for n in ContentParser.get_flat_nodes(spec_id):
		if not n.get("is_purple", false):
			nodes.append(n)
	return _pick(_collect(nodes, ctx), TREE_TEST, true)


## Сколько верных ответов нужно для зачёта.
static func pass_threshold(total: int, ratio: float) -> int:
	return int(ceil(total * ratio - 0.0001))


# ---------------------------------------------------------------- Контекст специализации

static func _context(spec_id: String) -> Dictionary:
	if _re_bold == null:
		_re_bold = RegEx.new()
		_re_bold.compile("\\*\\*(.+?)\\*\\*")
		_re_numbered = RegEx.new()
		_re_numbered.compile("^\\d+[.)]\\s*")
		# «- **Термин** — определение» / «**Термин**: определение»
		_re_def = RegEx.new()
		_re_def.compile("^(?:[-*]\\s+)?\\*\\*([^*]+)\\*\\*\\s*(?:—|–|-|:)\\s+(.+)$")
	var ctx := {"mains": [], "terms": [], "hints": [], "subs": [], "defs": []}
	for node in ContentParser.get_flat_nodes(spec_id):
		if node.is_main:
			ctx.mains.append(node)
		else:
			ctx.subs.append(node)
		for term in _terms_of(node):
			ctx.terms.append({"term": term, "node_id": node.id})
		var hint := _hint_of(node)
		if hint != "":
			ctx.hints.append({"hint": hint, "node_id": node.id})
		for d in _definitions_of(node):
			ctx.defs.append(d)
	return ctx


static func _collect(nodes: Array, ctx: Dictionary) -> Array:
	var pool: Array = []
	for node in nodes:
		for q in node.get("quiz", []):
			pool.append(_make(q.question, q.options, q.correct,
				q.explanation if q.explanation != "" else "Тема: «%s»" % node.title, node, "authored", 3))
		var gaps := 0
		for q in _fill_gaps(node, ctx):
			if gaps >= 2:
				break
			pool.append(q)
			gaps += 1
		var hint_q := _answer_hint(node, ctx)
		if not hint_q.is_empty():
			pool.append(hint_q)
		var reverse_q := _hint_reverse(node, ctx)
		if not reverse_q.is_empty():
			pool.append(reverse_q)
		var defs := 0
		for d in ctx.defs:
			if d.node_id != node.id or defs >= 2:
				continue
			var q := _definition(d, ctx) if defs % 2 == 0 else _term_fact(d, ctx)
			if not q.is_empty():
				pool.append(q)
				defs += 1
	return pool


## Выбор вопросов по квотам: ~50% авторских, ~30% по терминам/ответам/определениям, остальное — факты о терминах.
## Нехватка в одной группе добирается из других. По возможности — разные темы (spread).
static func _pick(pool: Array, count: int, spread: bool) -> Array:
	var tiers := {3: [], 2: [], 1: []}
	for q in pool:
		tiers[q.priority].append(q)
	for t in tiers:
		tiers[t].shuffle()
	var quota := {3: roundi(count * 0.5), 2: roundi(count * 0.3), 1: count}
	var result: Array = []
	var used_nodes := {}
	var used_text := {}
	for pass_i in 2:
		for t in [3, 2, 1]:
			var taken := result.filter(func(q): return q.priority == t).size()
			for q in tiers[t]:
				if result.size() >= count:
					break
				if pass_i == 0 and taken >= quota[t]:
					break
				if used_text.has(q.question) or (spread and pass_i == 0 and used_nodes.has(q.node_id)):
					continue
				used_text[q.question] = true
				used_nodes[q.node_id] = true
				result.append(q)
				taken += 1
	result.shuffle()
	for q in result:
		_shuffle_options(q)
	return result


# ---------------------------------------------------------------- Генераторы вопросов

static func _make(question: String, options: Array, correct: int, explanation: String, node: Dictionary, kind: String, priority: int) -> Dictionary:
	return {"question": question, "options": options.duplicate(), "correct": correct, "explanation": explanation,
		"node_id": node.id, "kind": kind, "priority": priority}


static func _fill_gaps(node: Dictionary, ctx: Dictionary) -> Array:
	var result: Array = []
	var in_code := false
	for raw in node.get("content", "").split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("```"):
			in_code = not in_code
			continue
		if in_code or line == "" or line.begins_with("|") or line.begins_with("#") or line.begins_with("<!--"):
			continue
		var m := _re_bold.search(line)
		if m == null:
			continue
		var term := _clean_term(m.get_string(1))
		if not _good_term(term):
			continue
		var sentence := line.substr(0, m.get_start()) + BLANK + line.substr(m.get_end())
		sentence = sentence.replace("**", "").trim_prefix("- ").trim_prefix("* ").trim_prefix("> ").strip_edges()
		sentence = _re_numbered.sub(sentence, "")
		var rest := sentence.replace(BLANK, "").strip_edges()
		if rest.length() < 18 or sentence.length() > 240 or sentence.ends_with(":"):
			continue
		var distractors := _distractor_terms(term, line, node.id, ctx)
		if distractors.size() < 3:
			continue
		var options: Array = [term]
		options.append_array(distractors)
		var expl := "%s\n\nТема: «%s»" % [line.replace("**", ""), node.title]
		result.append(_make("Заполни пропуск:\n\n" + sentence, options, 0, expl, node, "fill_gap", 2))
	result.shuffle()
	return result


static func _answer_hint(node: Dictionary, ctx: Dictionary) -> Dictionary:
	var hint := _hint_of(node)
	if hint == "" or node.get("frequency", 0) <= 0:
		return {}
	var others: Array = []
	for h in ctx.hints:
		if h.node_id != node.id and h.hint != hint:
			others.append(h.hint)
	if others.size() < 3:
		return {}
	others.shuffle()
	var options: Array = [hint]
	options.append_array(others.slice(0, 3))
	return _make("Что ожидают услышать в ответе на вопрос собеседования?\n\n**%s**" % node.title, options, 0,
		"Вопрос встречается в %d/100 собеседований." % node.frequency, node, "answer_hint", 2)


## Обратный к answer_hint: по ожидаемому ответу узнать вопрос собеседования.
static func _hint_reverse(node: Dictionary, ctx: Dictionary) -> Dictionary:
	var hint := _hint_of(node)
	if hint == "":
		return {}
	var others: Array = []
	for h in ctx.hints:
		if h.node_id != node.id:
			var t: String = ContentParser.get_node_data(h.node_id).get("title", "")
			if t != "" and t != node.title and not t in others:
				others.append(t)
	if others.size() < 3:
		return {}
	others.shuffle()
	var options: Array = [node.title]
	options.append_array(others.slice(0, 3))
	return _make("На какой вопрос собеседования это хороший ответ?\n\n«%s»" % hint, options, 0,
		"Вопрос: **%s**" % node.title, node, "hint_reverse", 2)


## «О каком понятии идёт речь?» — определение из урока, ответ — термин.
static func _definition(d: Dictionary, ctx: Dictionary) -> Dictionary:
	var others: Array = []
	var seen := {d.term.to_lower(): true}
	for o in ctx.defs:
		var tl: String = o.term.to_lower()
		if seen.has(tl) or tl in d.text.to_lower():
			continue
		seen[tl] = true
		others.append(o.term)
	if others.size() < 3:
		for t in ctx.terms:
			var tl: String = t.term.to_lower()
			if not seen.has(tl) and not tl in d.text.to_lower():
				seen[tl] = true
				others.append(t.term)
	if others.size() < 3:
		return {}
	others.shuffle()
	var options: Array = [d.term]
	options.append_array(others.slice(0, 3))
	var node := ContentParser.get_node_data(d.node_id)
	return _make("О каком понятии идёт речь?\n\n«%s»" % d.text, options, 0,
		"**%s** — %s\n\nТема: «%s»" % [d.term, d.text, node.get("title", "")], node, "definition", 2)


## «Что верно о …?» — верное определение термина среди определений других терминов.
static func _term_fact(d: Dictionary, ctx: Dictionary) -> Dictionary:
	var others: Array = []
	for o in ctx.defs:
		if o.term.to_lower() != d.term.to_lower() and o.text != d.text and not d.term.to_lower() in o.text.to_lower():
			others.append(o.text)
	if others.size() < 3:
		return {}
	others.shuffle()
	var options: Array = [d.text]
	options.append_array(others.slice(0, 3))
	var node := ContentParser.get_node_data(d.node_id)
	return _make("Какое описание подходит к понятию **%s**?" % d.term, options, 0,
		"**%s** — %s\n\nТема: «%s»" % [d.term, d.text, node.get("title", "")], node, "term_fact", 1)


# ---------------------------------------------------------------- Вспомогательное

static func _terms_of(node: Dictionary) -> Array:
	var terms: Array = []
	var in_code := false
	for raw in node.get("content", "").split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("```"):
			in_code = not in_code
			continue
		if in_code:
			continue
		for m in _re_bold.search_all(line):
			var t := _clean_term(m.get_string(1))
			if _good_term(t) and not t in terms:
				terms.append(t)
	return terms


static func _clean_term(t: String) -> String:
	return t.replace("`", "").strip_edges().trim_suffix(".").trim_suffix(",")


static func _good_term(t: String) -> bool:
	if t.length() < 2 or t.length() > 42 or t.ends_with(":") or t.ends_with("?"):
		return false
	if t.split(" ", false).size() > 3 or "%" in t or t[0].is_valid_int():
		return false
	if t.to_lower().begins_with("на собесе") or t.is_valid_float():
		return false
	return true


static func _distractor_terms(term: String, line: String, node_id: String, ctx: Dictionary) -> Array:
	var low_line := line.to_lower()
	var low_term := term.to_lower()
	var candidates: Array = []
	var seen := {}
	for t in ctx.terms:
		var tl: String = t.term.to_lower()
		if t.node_id == node_id or tl == low_term or seen.has(tl) or tl in low_line or low_term in tl or tl in low_term:
			continue
		seen[tl] = true
		candidates.append(t.term)
	candidates.shuffle()
	return candidates.slice(0, 3)


static func _hint_of(node: Dictionary) -> String:
	if node.get("frequency", 0) <= 0:
		return ""
	for raw in node.get("content", "").split("\n"):
		var line: String = raw.strip_edges()
		if line == "" or line.begins_with("```") or line.begins_with("<!--"):
			continue
		line = line.trim_prefix("_").trim_suffix("_").replace("**", "").replace("`", "")
		for prefix in ["Ключевые слова:", "Ожидается:", "Ожидаемо:", "Ответ:"]:
			line = line.trim_prefix(prefix)
		line = line.strip_edges()
		if line.length() < 8:
			return ""
		return line if line.length() <= 150 else line.substr(0, 147) + "…"
	return ""


## Определения из урока: строки вида «**Термин** — текст» (если термин не повторяется в тексте).
static func _definitions_of(node: Dictionary) -> Array:
	var result: Array = []
	var in_code := false
	for raw in node.get("content", "").split("\n"):
		var line: String = raw.strip_edges()
		if line.begins_with("```"):
			in_code = not in_code
			continue
		if in_code:
			continue
		var m := _re_def.search(line)
		if m == null:
			continue
		var term := _clean_term(m.get_string(1))
		var text := m.get_string(2).replace("**", "").replace("`", "").strip_edges()
		if not _good_term(term) or text.length() < 22 or text.length() > 170 or text.ends_with(":"):
			continue
		# Перечисления («события, интенсивность, длительность») — не определения
		if text.count(",") >= 2 and text.split(" ", false).size() <= 9:
			continue
		if term.to_lower() in text.to_lower():
			continue
		result.append({"term": term, "text": text, "node_id": node.id})
	return result


static func _shuffle_options(q: Dictionary) -> void:
	if q.options.size() == 2 and q.options[0] == TRUE_TEXT:
		return   # «Верно/Неверно» — порядок фиксирован
	var correct_text: String = q.options[q.correct]
	q.options.shuffle()
	q.correct = q.options.find(correct_text)
