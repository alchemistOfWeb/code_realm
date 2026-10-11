extends Control
## Экран теста. Режимы (params.mode):
##   "tree" — общий тест мини-дерева (params.spec_id): 10 вопросов, зачёт 70% → награда (RewardScroll)
##   "node" — тест узла (params.node_id): 3–5 вопросов, зачёт 60% → узел изучен + бонус XP
## Вопросы — QuizGenerator. Клавиши 1–4 выбирают ответ, Enter/Space — дальше.

signal completed(passed: bool)

const LETTERS := ["A", "B", "C", "D", "E", "F"]
const KIND_NAMES := {
	"authored": "Вопрос", "fill_gap": "Заполни пропуск", "answer_hint": "Вопрос собеседования",
	"parent": "Структура темы", "member": "Структура темы", "true_false": "Верно или нет",
}

@onready var subtitle: Label = %Subtitle
@onready var title_label: Label = %Title
@onready var quill_icon: TextureRect = %QuillIcon
@onready var progress_label: Label = %ProgressLabel
@onready var score_label: Label = %ScoreLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var content: VBoxContainer = %Content
@onready var footer: HBoxContainer = %Footer
@onready var hint_label: Label = %HintLabel
@onready var next_btn: Button = %NextButton

var mode: String = "tree"
var spec_id: String = ""
var node: Dictionary = {}
var accent: Color = Palette.ACCENT
var questions: Array = []
var answers: Array = []        # индекс выбранного варианта по каждому вопросу
var index: int = 0
var correct_count: int = 0
var result: Dictionary = {}

var _option_buttons: Array[Button] = []
var _answered := false


func _ready() -> void:
	%BackButton.pressed.connect(EventBus.back)
	next_btn.pressed.connect(_on_next)
	next_btn.set_meta("sfx", "")


func setup(params: Dictionary) -> void:
	mode = params.get("mode", "tree")
	if mode == "node":
		node = ContentParser.get_node_data(params.get("node_id", ""))
		spec_id = node.get("spec_id", "")
		subtitle.text = "Тест по теме · %s" % ContentParser.get_spec_name(spec_id)
		title_label.text = node.get("title", "?")
		questions = QuizGenerator.for_node(node)
	else:
		spec_id = params.get("spec_id", "")
		subtitle.text = "Общий тест дерева · зачёт от %d%%" % roundi(XPCalculator.TREE_TEST_PASS_RATIO * 100)
		title_label.text = ContentParser.get_spec_name(spec_id)
		questions = QuizGenerator.for_tree(spec_id)
	accent = ContentParser.get_spec_color(spec_id)
	title_label.add_theme_color_override("font_color", accent.lightened(0.2))
	quill_icon.modulate = accent.lightened(0.2)
	_start()


func _start() -> void:
	answers.clear()
	index = 0
	correct_count = 0
	result = {}
	if questions.size() < 2:
		_show_message("Недостаточно материала для теста",
			"В этой теме мало текста для генерации вопросов. Добавь в контент выделенные **термины** или авторские вопросы `<!-- quiz: ... -->` — или оставь заметку для Claude.")
		return
	_show_question()


# ---------------------------------------------------------------- Вопрос

func _show_question() -> void:
	_clear_content()
	_answered = false
	var q: Dictionary = questions[index]
	progress_label.text = "Вопрос %d / %d" % [index + 1, questions.size()]
	score_label.text = "Верно: %d" % correct_count
	_animate_progress(float(index) / questions.size())
	next_btn.disabled = true
	next_btn.text = "Дальше"
	footer.visible = true
	hint_label.text = "Клавиши 1–%d — выбрать ответ, Enter — дальше" % q.options.size()

	var kind := Label.new()
	kind.text = KIND_NAMES.get(q.kind, "Вопрос").to_upper()
	kind.theme_type_variation = &"MonoLabel"
	kind.add_theme_font_size_override("font_size", 12)
	kind.add_theme_color_override("font_color", accent.lightened(0.3))
	content.add_child(kind)

	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.scroll_active = false
	text.add_theme_font_size_override("normal_font_size", 20)
	text.add_theme_font_size_override("bold_font_size", 20)
	text.text = MarkdownBBCode.to_bbcode(q.question, accent.lightened(0.3))
	content.add_child(text)

	var options_box := VBoxContainer.new()
	options_box.add_theme_constant_override("separation", 10)
	content.add_child(options_box)
	_option_buttons.clear()
	for i in q.options.size():
		var btn := Button.new()
		btn.text = "%s.  %s" % [LETTERS[i], q.options[i]]
		btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.custom_minimum_size = Vector2(200, 48)
		btn.add_theme_font_override("font", Palette.FONT_TEXT)
		btn.add_theme_font_size_override("font_size", 16)
		btn.set_meta("sfx", "")
		btn.pressed.connect(_on_answer.bind(i))
		options_box.add_child(btn)
		_option_buttons.append(btn)
		btn.modulate.a = 0.0
		var tw := btn.create_tween()
		tw.tween_interval(0.05 * i)
		tw.tween_property(btn, "modulate:a", 1.0, 0.2)


func _on_answer(choice: int) -> void:
	if _answered:
		return
	_answered = true
	var q: Dictionary = questions[index]
	var ok: bool = choice == q.correct
	answers.append(choice)
	if ok:
		correct_count += 1
		Audio.play("confirm", 0.0)
	else:
		Audio.play("error", 0.0)
	score_label.text = "Верно: %d" % correct_count
	for i in _option_buttons.size():
		var btn := _option_buttons[i]
		btn.disabled = true
		if i == q.correct:
			_style_option(btn, Palette.MINT, "✓  ")
		elif i == choice:
			_style_option(btn, Palette.HP, "✗  ")
			_shake(btn)
		else:
			btn.modulate.a = 0.45

	var feedback := PanelContainer.new()
	var color := Palette.MINT if ok else Palette.HP
	feedback.add_theme_stylebox_override("panel", Palette.box(Color(color, 0.08), Color(color, 0.5), 1, 10, 14, 10))
	var fb_text := RichTextLabel.new()
	fb_text.bbcode_enabled = true
	fb_text.fit_content = true
	fb_text.scroll_active = false
	fb_text.add_theme_font_size_override("normal_font_size", 15)
	var head := "[b][color=%s]%s[/color][/b]\n" % [Palette.hex(color), "Верно!" if ok else "Неверно"]
	fb_text.text = head + MarkdownBBCode.to_bbcode(q.get("explanation", ""), accent.lightened(0.3))
	feedback.add_child(fb_text)
	content.add_child(feedback)
	feedback.modulate.a = 0.0
	feedback.create_tween().tween_property(feedback, "modulate:a", 1.0, 0.25)

	next_btn.disabled = false
	next_btn.text = "Результаты" if index == questions.size() - 1 else "Дальше"
	next_btn.grab_focus()


func _style_option(btn: Button, color: Color, prefix: String) -> void:
	btn.text = prefix + btn.text
	var sb := Palette.box(Color(color, 0.16), color, 2, 8, 16, 9)
	for state in ["normal", "disabled", "hover", "pressed"]:
		btn.add_theme_stylebox_override(state, sb)
	btn.add_theme_color_override("font_disabled_color", color.lightened(0.3))


func _shake(ctrl: Control) -> void:
	var x := ctrl.position.x
	var tw := ctrl.create_tween()
	for d in [8.0, -8.0, 5.0, -5.0, 0.0]:
		tw.tween_property(ctrl, "position:x", x + d, 0.04)


func _on_next() -> void:
	if result.is_empty() and _answered:
		Audio.play("whoosh")
		index += 1
		if index >= questions.size():
			_finish()
		else:
			_show_question()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo() or not result.is_empty():
		return
	var key := (event as InputEventKey).keycode
	if not _answered and key >= KEY_1 and key <= KEY_6:
		var i := key - KEY_1
		if i < _option_buttons.size():
			_on_answer(i)
			accept_event()
	elif _answered and key in [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE]:
		_on_next()
		accept_event()


# ---------------------------------------------------------------- Итог

func _finish() -> void:
	_animate_progress(1.0)
	if mode == "node":
		result = GameManager.complete_node_test(node, correct_count, questions.size())
	else:
		result = GameManager.complete_tree_test(spec_id, correct_count, questions.size())
	SaveSystem.save_all()
	completed.emit(result.passed)
	_show_result()


func _show_result() -> void:
	_clear_content()
	progress_label.text = "Тест завершён"
	var passed: bool = result.passed
	var total := questions.size()
	var ratio := XPCalculator.NODE_TEST_PASS_RATIO if mode == "node" else XPCalculator.TREE_TEST_PASS_RATIO
	var need := QuizGenerator.pass_threshold(total, ratio)
	var color := Palette.MINT if passed else Palette.HP

	var center := VBoxContainer.new()
	center.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_theme_constant_override("separation", 6)
	content.add_child(center)
	var verdict := Label.new()
	verdict.text = "ТЕСТ ПРОЙДЕН" if passed else "ТЕСТ НЕ СДАН"
	verdict.theme_type_variation = &"MonoLabel"
	verdict.add_theme_color_override("font_color", color)
	verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(verdict)
	var score := Label.new()
	score.text = "%d / %d" % [correct_count, total]
	score.theme_type_variation = &"TitleLabel"
	score.add_theme_font_size_override("font_size", 52)
	score.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(score)
	var sub := Label.new()
	sub.text = "Для зачёта нужно %d верных ответов из %d" % [need, total]
	sub.theme_type_variation = &"DimLabel"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	center.add_child(sub)
	center.modulate.a = 0.0
	center.create_tween().tween_property(center, "modulate:a", 1.0, 0.4)

	var rewards := _rewards_text()
	if rewards != "":
		var rew := RichTextLabel.new()
		rew.bbcode_enabled = true
		rew.fit_content = true
		rew.scroll_active = false
		rew.add_theme_font_size_override("normal_font_size", 16)
		rew.text = "[center]%s[/center]" % rewards
		content.add_child(rew)

	content.add_child(HSeparator.new())
	content.add_child(_review_list())

	# Кнопки
	footer.visible = true
	hint_label.text = ""
	next_btn.visible = false
	for child in footer.get_children():
		if child.has_meta("result_btn"):
			child.queue_free()
	if passed and mode == "tree" and not result.get("cards", []).is_empty():
		_footer_button("Открыть награду", "AccentButton", _open_reward).set_meta("sfx", "scroll_open")
	_footer_button("Пройти ещё раз", "", _retry)
	_footer_button("К уроку" if mode == "node" else "К дереву", "", EventBus.back)

	if passed:
		Audio.play_jingle("reward" if mode == "node" or result.get("cards", []).is_empty() else "fanfare")
		_burst(color)
	else:
		Audio.play("drop")


func _rewards_text() -> String:
	if not result.passed:
		return "[color=%s]Награда не получена. Перечитай темы с ошибками и попробуй снова.[/color]" % Palette.hex(Palette.TEXT_DIM)
	var parts: PackedStringArray = []
	if result.get("xp", 0) > 0:
		parts.append("[color=%s]+%d XP[/color]" % [Palette.hex(Palette.MINT), result.xp])
	if result.get("energy", 0) > 0:
		parts.append("[color=%s]+%d энергии[/color]" % [Palette.hex(Palette.ENERGY), result.energy])
	if not result.get("cards", []).is_empty():
		parts.append("[color=%s]карт: %d[/color]" % [Palette.hex(Palette.GOLD), result.cards.size()])
	if result.get("nodes_marked", 0) > 0:
		parts.append("изучено тем: %d" % result.nodes_marked)
	if result.get("learned_now", false):
		parts.append("тема отмечена изученной")
	var text := "   ·   ".join(parts)
	if result.get("cooldown_left", 0) > 0:
		var hours := ceili(result.cooldown_left / 3600.0)
		text += ("\n" if text != "" else "") + "[color=%s]Повторная награда за дерево будет доступна через %d ч.[/color]" % [Palette.hex(Palette.TEXT_DIM), hours]
	elif mode == "tree" and not result.get("first", false) and text != "":
		text += "\n[color=%s]Повторное прохождение — уменьшенная награда.[/color]" % Palette.hex(Palette.TEXT_DIM)
	elif mode == "node" and not result.get("first", false) and not result.get("learned_now", false):
		text += "\n[color=%s]Бонус за этот тест уже был получен.[/color]" % Palette.hex(Palette.TEXT_DIM)
	return text


func _review_list() -> Control:
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	var head := Label.new()
	head.text = "Разбор ответов"
	head.theme_type_variation = &"HeaderLabel"
	head.add_theme_font_size_override("font_size", 15)
	box.add_child(head)
	for i in questions.size():
		var q: Dictionary = questions[i]
		var ok: bool = answers[i] == q.correct
		var row := RichTextLabel.new()
		row.bbcode_enabled = true
		row.fit_content = true
		row.scroll_active = false
		row.add_theme_font_size_override("normal_font_size", 14)
		var qtext: String = q.question.replace("\n\n", " ").replace("**", "")
		if qtext.length() > 140:
			qtext = qtext.substr(0, 137) + "…"
		var mark := "[color=%s]%s[/color]" % [Palette.hex(Palette.MINT if ok else Palette.HP), "✓" if ok else "✗"]
		var line := "%s  %s" % [mark, MarkdownBBCode.to_bbcode(qtext)]
		if not ok:
			line += "\n      [color=%s]Ответ: %s[/color]" % [Palette.hex(Palette.MINT), q.options[q.correct].replace("[", "[lb]")]
		row.text = line
		box.add_child(row)
	return box


func _footer_button(text: String, variation: String, callback: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	if variation != "":
		btn.theme_type_variation = StringName(variation)
	btn.set_meta("result_btn", true)
	btn.pressed.connect(callback)
	footer.add_child(btn)
	return btn


func _open_reward() -> void:
	EventBus.go("reward", {"result": result, "replace": true, "overlay": true})


func _retry() -> void:
	for child in footer.get_children():
		if child.has_meta("result_btn"):
			child.queue_free()
	next_btn.visible = true
	questions = QuizGenerator.for_node(node) if mode == "node" else QuizGenerator.for_tree(spec_id)
	_start()


func _show_message(title: String, md: String) -> void:
	_clear_content()
	var t := Label.new()
	t.text = title
	t.theme_type_variation = &"HeaderLabel"
	content.add_child(t)
	var body := RichTextLabel.new()
	body.bbcode_enabled = true
	body.fit_content = true
	body.text = MarkdownBBCode.to_bbcode(md)
	content.add_child(body)
	next_btn.visible = false
	_footer_button("Назад", "", EventBus.back)


func _clear_content() -> void:
	for child in content.get_children():
		child.queue_free()


func _animate_progress(value: float) -> void:
	progress_bar.max_value = 1.0
	progress_bar.step = 0.001
	create_tween().tween_property(progress_bar, "value", value, 0.3)


func _burst(color: Color) -> void:
	var particles := CPUParticles2D.new()
	particles.position = size / 2.0 - Vector2(0, 120)
	particles.one_shot = true
	particles.amount = 70
	particles.lifetime = 1.2
	particles.explosiveness = 0.95
	particles.direction = Vector2(0, -1)
	particles.spread = 180.0
	particles.initial_velocity_min = 180.0
	particles.initial_velocity_max = 420.0
	particles.gravity = Vector2(0, 380)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 5.0
	var ramp := Gradient.new()
	ramp.set_color(0, color.lightened(0.4))
	ramp.set_color(1, Color(Palette.GOLD, 0.0))
	particles.color_ramp = ramp
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(2.0).timeout.connect(particles.queue_free)
