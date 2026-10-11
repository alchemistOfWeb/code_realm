extends Control
## Сейф с испорченным Python-кодом: исправь ошибку, чтобы тесты прошли, — и замок откроется.
## params: {safe_id}. Итог — EventBus.safe_finished(safe_id, opened).

const DATA_FILE := "res://data/safes.json"
const PY_KEYWORDS := ["def", "return", "if", "elif", "else", "for", "while", "in", "not", "and", "or", "is",
	"None", "True", "False", "lambda", "import", "from", "as", "try", "except", "finally", "raise", "with",
	"class", "pass", "break", "continue", "yield", "assert", "global", "nonlocal"]
const PY_BUILTINS := ["sum", "len", "range", "sorted", "print", "list", "dict", "set", "tuple", "str", "int",
	"reversed", "enumerate", "zip", "min", "max", "abs", "any", "all", "map", "filter"]

static var _safes: Dictionary = {}

var safe: Dictionary = {}
var _editor: CodeEdit
var _result: RichTextLabel
var _hint: RichTextLabel
var _check_btn: Button
var _attempts := 0
var _opened := false


static func get_safe(id: String) -> Dictionary:
	if _safes.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_FILE))
		for s in parsed.get("safes", []):
			_safes[s.id] = s
	return _safes.get(id, {})


static func all_ids() -> Array:
	get_safe("")
	return _safes.keys()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(params: Dictionary) -> void:
	safe = get_safe(params.get("safe_id", ""))
	_build()
	Audio.play("chest_latch")


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.03, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for s in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + s, 24)
	add_child(margin)
	var panel := PanelContainer.new()
	var brass := Color("#C9A24A")
	panel.add_theme_stylebox_override("panel", Palette.glow_box(Color("#14110C", 0.97), brass, Color(brass, 0.25), 16, 14))
	margin.add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	panel.add_child(row)

	# Описание
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 340
	left.add_theme_constant_override("separation", 10)
	row.add_child(left)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 10)
	left.add_child(head)
	var icon := TextureRect.new()
	icon.texture = Palette.game_icon("dial-padlock")
	icon.custom_minimum_size = Vector2(44, 44)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = brass
	head.add_child(icon)
	var title := Label.new()
	title.text = "Сейф: %s" % safe.get("title", "?")
	title.theme_type_variation = &"HeaderLabel"
	title.add_theme_color_override("font_color", brass.lightened(0.2))
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var story := Label.new()
	story.text = safe.get("story", "")
	story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	story.add_theme_color_override("font_color", Color("#E8DCC0"))
	left.add_child(story)
	var tests_head := Label.new()
	tests_head.text = "Механизм проверяет:"
	tests_head.theme_type_variation = &"MonoLabel"
	tests_head.add_theme_color_override("font_color", brass)
	left.add_child(tests_head)
	var tests := RichTextLabel.new()
	tests.bbcode_enabled = true
	tests.fit_content = true
	tests.text = MarkdownBBCode.to_bbcode("```python\n%s```" % safe.get("tests", ""))
	left.add_child(tests)
	_hint = RichTextLabel.new()
	_hint.bbcode_enabled = true
	_hint.fit_content = true
	left.add_child(_hint)
	_update_hint()
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(sp)
	var method := Label.new()
	method.theme_type_variation = &"DimLabel"
	method.add_theme_font_size_override("font_size", 12)
	method.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	method.text = "Код запускается в Python на твоём компьютере." if PythonRunner.available() else "Python не найден — проверка по шаблону исправления."
	left.add_child(method)

	# Редактор
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.add_theme_constant_override("separation", 10)
	row.add_child(right)
	var ed_head := Label.new()
	ed_head.text = "Найди и исправь ошибку (Ctrl+Enter — проверить)"
	ed_head.theme_type_variation = &"DimLabel"
	right.add_child(ed_head)
	_editor = CodeEdit.new()
	_editor.text = safe.get("code", "")
	_editor.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_editor.gutters_draw_line_numbers = true
	_editor.indent_automatic = true
	_editor.indent_use_spaces = true
	_editor.indent_size = 4
	_editor.auto_brace_completion_enabled = true
	_editor.add_theme_font_override("font", Palette.FONT_UI)
	_editor.add_theme_font_size_override("font_size", 16)
	_editor.add_theme_color_override("background_color", Color("#0A0A12"))
	_editor.add_theme_color_override("font_color", Color("#D6DEEB"))
	_editor.add_theme_color_override("line_number_color", Color("#55557A"))
	_editor.syntax_highlighter = _python_highlighter()
	right.add_child(_editor)
	_result = RichTextLabel.new()
	_result.bbcode_enabled = true
	_result.fit_content = true
	_result.custom_minimum_size.y = 24
	right.add_child(_result)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	right.add_child(buttons)
	_check_btn = Button.new()
	_check_btn.text = "Проверить код"
	_check_btn.icon = Palette.icon("check")
	_check_btn.theme_type_variation = &"MintButton"
	_check_btn.set_meta("sfx", "gear")
	_check_btn.pressed.connect(_on_check)
	buttons.add_child(_check_btn)
	var reset := Button.new()
	reset.text = "Сбросить"
	reset.icon = Palette.icon("rotate-ccw")
	reset.pressed.connect(func(): _editor.text = safe.get("code", ""))
	buttons.add_child(reset)
	var sp2 := Control.new()
	sp2.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	buttons.add_child(sp2)
	var leave := Button.new()
	leave.text = "Отойти"
	leave.theme_type_variation = &"GhostButton"
	leave.pressed.connect(_close)
	buttons.add_child(leave)
	_editor.grab_focus.call_deferred()


func _python_highlighter() -> CodeHighlighter:
	var h := CodeHighlighter.new()
	h.number_color = Color("#F78C6C")
	h.symbol_color = Color("#89DDFF")
	h.function_color = Color("#82AAFF")
	h.member_variable_color = Color("#D6DEEB")
	for k in PY_KEYWORDS:
		h.add_keyword_color(k, Color("#C792EA"))
	for b in PY_BUILTINS:
		h.add_keyword_color(b, Color("#FFCB6B"))
	h.add_color_region("#", "", Color("#5C6390"), true)
	h.add_color_region("\"\"\"", "\"\"\"", Color("#C3E88D"))
	h.add_color_region("\"", "\"", Color("#C3E88D"))
	h.add_color_region("'", "'", Color("#C3E88D"))
	return h


func _update_hint() -> void:
	if GameManager.has_flag("safe_hint") or _attempts >= 1:
		_hint.text = "[color=#F5C542]💡 Подсказка:[/color] %s" % safe.get("hint", "").replace("[", "[lb]")
	else:
		_hint.text = "[color=#8C8CB0]Подсказка появится после первой попытки (или если помочь Архивариусу Сайферу).[/color]"


func _on_check() -> void:
	if _opened or _check_btn.disabled:
		return
	_check_btn.disabled = true
	_result.text = "[color=#8C8CB0]Шестерёнки проворачиваются…[/color]"
	var res: Dictionary = await PythonRunner.check(self, _editor.text, safe)
	_check_btn.disabled = false
	_attempts += 1
	if res.ok:
		_opened = true
		_result.text = "[color=#00D4AA][b]Щёлк! Замок открыт.[/b][/color]"
		Audio.play("gate")
		Audio.play_jingle("reward")
		_check_btn.disabled = true
		await get_tree().create_timer(1.0).timeout
		_close()
	else:
		_result.text = "[color=#FF6B6B]%s[/color]" % String(res.error).replace("[", "[lb]")
		Audio.play("error")
		_update_hint()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ENTER and (event as InputEventKey).ctrl_pressed:
		_on_check()
		accept_event()


func _close() -> void:
	EventBus.safe_finished.emit(safe.get("id", ""), _opened)
	EventBus.back()
