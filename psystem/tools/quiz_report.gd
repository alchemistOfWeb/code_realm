extends Node
## Отчёт по генерации вопросов: сколько вопросов каждого вида можно собрать по каждому дереву.
## Запуск: Godot --headless --path <project> res://tools/QuizReport.tscn [-- --sample]

func _ready() -> void:
	for spec_id in ContentParser.get_all_spec_ids():
		var ctx := QuizGenerator._context(spec_id)
		var pool := QuizGenerator._collect(ContentParser.get_flat_nodes(spec_id), ctx)
		var kinds := {}
		for q in pool:
			kinds[q.kind] = kinds.get(q.kind, 0) + 1
		print("%-18s terms=%3d hints=%3d pool=%3d %s" % [spec_id, ctx.terms.size(), ctx.hints.size(), pool.size(), kinds])
		if "--sample" in OS.get_cmdline_user_args():
			for q in QuizGenerator.for_tree(spec_id).slice(0, 4):
				print("   [%s] %s\n      -> %s | %s" % [q.kind, q.question.replace("\n", " "), q.options[q.correct], q.options])
	get_tree().quit()
