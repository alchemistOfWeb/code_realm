class_name QuizGenerator
extends RefCounted
## Тесты — только из авторских вопросов: строки <!-- quiz: Вопрос? | +Верный | Неверный | … || Пояснение -->
## в content/*.md. Каждый вопрос написан человеком по тексту урока, ответ есть в этом тексте.
## (Автогенерация — «заполни пропуск», «какое описание подходит к понятию…», «на какой вопрос это ответ» —
## убрана: такие вопросы звучали неестественно и проверяли форму текста, а не знания.)
##
## Вопрос: {question (markdown), options: Array[String], correct: int, explanation, node_id, kind}

const NODE_TEST_MAIN := 5
const NODE_TEST_SUB := 3
const TREE_TEST := 10
## Сколько своих вопросов должно быть у каждой темы (проверяет QuizReport и smoke-тест).
const MIN_PER_NODE := 3


## Тест по одному узлу: подтема — её вопросы (если не хватает — добор из главной темы);
## главная тема — вопросы её самой и подтем, по возможности из разных подтем.
static func for_node(node: Dictionary) -> Array:
	var is_main: bool = node.get("is_main", false)
	var count := NODE_TEST_MAIN if is_main else NODE_TEST_SUB
	var pool := questions_of(node)
	if is_main:
		for sub in node.get("subnodes", []):
			pool.append_array(questions_of(sub))
	var picked := _pick(pool, count, is_main)
	if picked.size() < count and not is_main:
		var parent := ContentParser.get_parent_node(node.get("id", ""))
		if not parent.is_empty():
			var extra := questions_of(parent)
			for sub in parent.get("subnodes", []):
				if sub.id != node.id:
					extra.append_array(questions_of(sub))
			var used := {}
			for q in picked:
				used[q.question] = true
			for q in _pick(extra.filter(func(x): return not used.has(x.question)), count - picked.size(), true):
				picked.append(q)
	return picked


## Общий тест по дереву: обязательные (не фиолетовые) узлы, по возможности разные темы.
static func for_tree(spec_id: String) -> Array:
	var pool: Array = []
	for n in ContentParser.get_flat_nodes(spec_id):
		if not n.get("is_purple", false):
			pool.append_array(questions_of(n))
	return _pick(pool, TREE_TEST, true)


## Сколько верных ответов нужно для зачёта.
static func pass_threshold(total: int, ratio: float) -> int:
	return int(ceil(total * ratio - 0.0001))


## Мало своих вопросов: у подтемы и темы без подтем — меньше MIN_PER_NODE; у темы с подтемами — ни одного
## (её тест собирается в основном из вопросов подтем).
static func needs_more(node: Dictionary) -> bool:
	var k := questions_of(node).size()
	if node.get("is_main", false) and not node.get("subnodes", []).is_empty():
		return k < 1
	return k < MIN_PER_NODE


## Авторские вопросы узла.
static func questions_of(node: Dictionary) -> Array:
	var out: Array = []
	for q in node.get("quiz", []):
		out.append({"question": q.question, "options": q.options.duplicate(), "correct": q.correct,
			"explanation": q.explanation if q.explanation != "" else "Тема: «%s»" % node.get("title", ""),
			"node_id": node.get("id", ""), "kind": "authored"})
	return out


## Случайные count вопросов без повторов; spread — сначала по одному из каждой темы.
static func _pick(pool: Array, count: int, spread: bool) -> Array:
	var shuffled := pool.duplicate()
	shuffled.shuffle()
	var result: Array = []
	var used_nodes := {}
	var used_text := {}
	for pass_i in 2:
		for q in shuffled:
			if result.size() >= count:
				break
			if used_text.has(q.question) or (spread and pass_i == 0 and used_nodes.has(q.node_id)):
				continue
			used_text[q.question] = true
			used_nodes[q.node_id] = true
			result.append(q)
	result.shuffle()
	for q in result:
		_shuffle_options(q)
	return result


static func _shuffle_options(q: Dictionary) -> void:
	var correct_text: String = q.options[q.correct]
	q.options.shuffle()
	q.correct = q.options.find(correct_text)
