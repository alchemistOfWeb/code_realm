class_name ClaudeNotesExporter
extends RefCounted
## Собирает все непустые заметки для Claude (GameManager.claude_notes) в NOTES_FOR_CLAUDE.md.
## В редакторе файл пишется в корень проекта, в собранной игре — рядом с .exe.

const FILE_NAME := "NOTES_FOR_CLAUDE.md"
const GENERAL_KEY := "_general"

## Если задан — экспорт пишет сюда (используется тестами).
static var override_path: String = ""


static func target_path() -> String:
	if override_path != "":
		return override_path
	if OS.has_feature("editor"):
		return ProjectSettings.globalize_path("res://" + FILE_NAME)
	return OS.get_executable_path().get_base_dir().path_join(FILE_NAME)


static func export_all() -> String:
	var notes: Dictionary = GameManager.claude_notes
	var text := "# NOTES FOR CLAUDE\n"
	text += "> Обновлено: %s\n\n" % Time.get_datetime_string_from_system(false, true)
	text += "Заметки пользователя, адресованные Claude (пишутся в игре в поле «Заметки для Claude»).\n"
	text += "Прочитай этот файл в начале сессии и внеси правки в проект/контент.\n"
	text += "Формат: `id узла` — по нему узел ищется в content/*.md (spec_id/раздел/подраздел).\n\n---\n\n"

	var count := 0
	var general: String = notes.get(GENERAL_KEY, "")
	if general.strip_edges() != "":
		text += "## Общие заметки о приложении\n\n%s\n\n---\n\n" % general.strip_edges()
		count += 1

	for spec_id in ContentParser.get_all_spec_ids():
		var section := ""
		for node in ContentParser.get_flat_nodes(spec_id):
			var note: String = notes.get(node.id, "")
			if note.strip_edges() == "":
				continue
			var title: String = node.title
			if not node.is_main:
				title = ContentParser.get_parent_node(node.id).get("title", "") + " → " + title
			section += "### %s\n`%s`\n\n%s\n\n" % [title, node.id, note.strip_edges()]
			count += 1
		if section != "":
			text += "## %s\n\n%s---\n\n" % [ContentParser.get_spec_name(spec_id), section]

	# Заметки к узлам, которых больше нет в контенте (узел переименован/удалён)
	var orphan := ""
	for node_id in notes:
		if node_id == GENERAL_KEY or not ContentParser.get_node_data(node_id).is_empty():
			continue
		if String(notes[node_id]).strip_edges() != "":
			orphan += "### `%s`\n\n%s\n\n" % [node_id, String(notes[node_id]).strip_edges()]
			count += 1
	if orphan != "":
		text += "## Заметки к удалённым/переименованным узлам\n\n%s---\n\n" % orphan

	if count == 0:
		text += "_Заметок пока нет._\n"

	var path := target_path()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("ClaudeNotesExporter: не удалось записать " + path)
		EventBus.notify("Не удалось сохранить заметки: " + path, "error")
		return ""
	file.store_string(text)
	file.close()
	EventBus.notes_exported.emit(path)
	return path
