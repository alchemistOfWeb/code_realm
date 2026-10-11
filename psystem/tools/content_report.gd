extends SceneTree
## Отчёт по распарсенному контенту: число узлов, сложности, фиолетовые узлы, пустые узлы.
## Также прогоняет MarkdownBBCode по всем узлам (ловит ошибки конвертера).
## Запуск: Godot --headless --path <project> --script res://tools/content_report.gd [-- --verbose]

var _done := false


func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true
	var parser = root.get_node("/root/ContentParser")
	var verbose := "--verbose" in OS.get_cmdline_user_args()
	var total := 0
	for spec_id in parser.get_all_spec_ids():
		var spec: Dictionary = parser.get_specialization(spec_id)
		var mains: int = spec.nodes.size()
		var subs := 0
		var purple := 0
		var empty := 0
		var diff := [0, 0, 0, 0]
		var xp := 0
		for node in parser.get_flat_nodes(spec_id):
			if not node.is_main:
				subs += 1
			if node.is_purple:
				purple += 1
			if node.content.strip_edges() == "" and (not node.is_main or node.subnodes.is_empty()):
				empty += 1
			diff[node.difficulty] += 1
			xp += node.xp_reward
			var bb := MarkdownBBCode.to_bbcode(node.content)
			if bb.count("[table") != bb.count("[/table]"):
				print("  !! unbalanced table in ", node.id)
		total += mains + subs
		print("%-18s mains=%3d subs=%3d purple=%3d empty=%2d diff(1/2/3)=%d/%d/%d xp=%d  title=%s" % [spec_id, mains, subs, purple, empty, diff[1], diff[2], diff[3], xp, spec.title])
		if verbose:
			for node in spec.nodes:
				print("    [%d%s] %s  (%d subs) group=%s" % [node.difficulty, "P" if node.is_purple else "", node.title, node.subnodes.size(), node.group])
	print("TOTAL nodes: ", total)
	return true
