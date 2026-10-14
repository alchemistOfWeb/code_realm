extends Node
## Отчёт по вопросам тестов: сколько авторских вопросов у каждого дерева и какие темы недобрали
## QuizGenerator.MIN_PER_NODE вопросов (их тест будет короче или с добором из соседних тем).
## Запуск: Godot --headless --path <project> res://tools/QuizReport.tscn [-- --sample]

func _ready() -> void:
	var total_short := 0
	for spec_id in ContentParser.get_all_spec_ids():
		var nodes := ContentParser.get_flat_nodes(spec_id)
		var count := 0
		var short: PackedStringArray = []
		for n in nodes:
			var k := QuizGenerator.questions_of(n).size()
			count += k
			if QuizGenerator.needs_more(n):
				short.append("%s (%d)" % [n.title, k])
		total_short += short.size()
		print("%-18s узлов=%3d вопросов=%4d мало вопросов: %d" % [spec_id, nodes.size(), count, short.size()])
		for s in short:
			print("    — ", s)
		if "--sample" in OS.get_cmdline_user_args():
			for q in QuizGenerator.for_tree(spec_id).slice(0, 4):
				print("   %s\n      -> %s | %s" % [q.question.replace("\n", " "), q.options[q.correct], q.options])
	print("QUIZ_SHORT ", total_short)
	get_tree().quit()
