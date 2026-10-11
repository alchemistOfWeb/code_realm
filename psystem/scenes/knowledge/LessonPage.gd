extends Control
## Страница урока: контент узла (markdown → BBCode), отметка «Изучено» (+XP, +энергия),
## навигация по соседним темам, список подтем раздела и заметки для Claude.

var node_data: Dictionary = {}
var spec_id: String = ""
var spec_color: Color = Palette.ACCENT

@onready var breadcrumb: Label = %Breadcrumb
@onready var title_label: Label = %Title
@onready var difficulty_label: Label = %Difficulty
@onready var purple_label: Label = %PurpleLabel
@onready var freq_label: Label = %FreqLabel
@onready var status_label: Label = %StatusLabel
@onready var content_label: RichTextLabel = %ContentLabel
@onready var learn_btn: Button = %LearnButton
@onready var unlearn_btn: Button = %UnlearnButton
@onready var prev_btn: Button = %PrevButton
@onready var next_btn: Button = %NextButton
@onready var related_title: Label = %RelatedTitle
@onready var related_list: VBoxContainer = %RelatedList
@onready var notes_edit: TextEdit = %NotesEdit
@onready var saved_label: Label = %SavedLabel
@onready var notes_timer: Timer = %NotesTimer


func _ready() -> void:
	%BackButton.pressed.connect(EventBus.back)
	learn_btn.pressed.connect(_on_learn_pressed)
	learn_btn.set_meta("sfx", "")          # свой звук — confirm после изучения
	prev_btn.set_meta("sfx", "whoosh")
	next_btn.set_meta("sfx", "whoosh")
	unlearn_btn.pressed.connect(_on_unlearn_pressed)
	prev_btn.pressed.connect(_go_neighbor.bind(-1))
	next_btn.pressed.connect(_go_neighbor.bind(1))
	%TestButton.pressed.connect(_on_test_pressed)
	notes_edit.text_changed.connect(_on_notes_changed)
	notes_timer.timeout.connect(_save_notes)
	content_label.meta_clicked.connect(func(meta): OS.shell_open(str(meta)))


func _exit_tree() -> void:
	if notes_timer and not notes_timer.is_stopped():
		notes_timer.stop()
		_save_notes()


func setup(params: Dictionary) -> void:
	node_data = ContentParser.get_node_data(params.get("node_id", ""))
	if node_data.is_empty():
		title_label.text = "Узел не найден"
		content_label.text = "Узел «%s» отсутствует в контенте (возможно, раздел переименован)." % params.get("node_id", "")
		learn_btn.disabled = true
		return
	spec_id = node_data.spec_id
	spec_color = ContentParser.get_spec_color(spec_id)

	var node_id: String = node_data.id
	if GameManager.get_node_status(node_id) == "":
		GameManager.mark_in_progress(node_id)
		SaveSystem.request_save()

	var crumbs := [ContentParser.get_spec_name(spec_id)]
	if node_data.is_main:
		if node_data.get("group", "") != "":
			crumbs.append(node_data.group)
	else:
		crumbs.append(ContentParser.get_parent_node(node_id).get("title", ""))
	breadcrumb.text = "  ›  ".join(crumbs)
	breadcrumb.add_theme_color_override("font_color", spec_color.lightened(0.2))

	title_label.text = node_data.title
	difficulty_label.text = XPCalculator.stars(node_data.difficulty)
	purple_label.visible = node_data.get("is_purple", false)
	var freq: int = node_data.get("frequency", 0)
	freq_label.visible = freq > 0
	freq_label.text = "%d/100 собесов" % freq
	freq_label.add_theme_color_override("font_color", Palette.HP if freq >= 80 else (Palette.ENERGY if freq >= 50 else Palette.TEXT_DIM))

	_render_content()
	notes_edit.text = GameManager.get_note(node_id)
	_update_status_display()
	_build_related()
	_update_nav_buttons()
	_update_test_button()


func on_resume() -> void:
	if node_data.is_empty():
		return
	_update_status_display()
	_build_related()
	_update_test_button()


func _update_test_button() -> void:
	var btn: Button = %TestButton
	btn.disabled = false
	var rec := GameManager.test_record("node:" + node_data.id)
	var count := QuizGenerator.NODE_TEST_MAIN if node_data.is_main else QuizGenerator.NODE_TEST_SUB
	var tip := "Тест по теме: %d вопроса, зачёт от %d%%.
Зачёт отмечает тему изученной и даёт бонус XP (один раз)." % [count, roundi(XPCalculator.NODE_TEST_PASS_RATIO * 100)]
	if rec.get("passes", 0) > 0:
		btn.text = "Тест ✓"
		tip += "
Лучший результат: %d / %d" % [rec.best, rec.total]
	else:
		btn.text = "Пройти тест"
	btn.tooltip_text = tip


func _on_test_pressed() -> void:
	EventBus.go("test", {"mode": "node", "node_id": node_data.id})


func _render_content() -> void:
	var md: String = node_data.get("content", "")
	if md.strip_edges() == "":
		if node_data.is_main and not node_data.subnodes.is_empty():
			md = "_Раздел состоит из %d подтем — они перечислены справа. Изучи их и отметь раздел целиком._" % node_data.subnodes.size()
		else:
			md = "_Контент этой темы пока пуст. Напиши в «Заметки для Claude», что сюда добавить._"
	content_label.text = MarkdownBBCode.to_bbcode(md, spec_color.lightened(0.25))
	content_label.scroll_to_line(0)


# ---------------------------------------------------------------- Статус / изучение

func _update_status_display() -> void:
	var node_id: String = node_data.id
	var status := GameManager.get_node_status(node_id)
	var learned := status == GameManager.STATUS_LEARNED
	unlearn_btn.visible = learned
	learn_btn.disabled = learned
	if learned:
		learn_btn.text = "Изучено"
		status_label.text = "✓ Изучено"
		status_label.add_theme_color_override("font_color", Palette.MINT)
	else:
		if GameManager.rewarded_nodes.has(node_id):
			learn_btn.text = "Отметить как изученное"
		else:
			learn_btn.text = "Отметить как изученное  (+%d XP)" % node_data.get("xp_reward", 5)
		status_label.text = "В процессе" if status == GameManager.STATUS_IN_PROGRESS else "Не начато"
		status_label.add_theme_color_override("font_color", Palette.ENERGY if status != "" else Palette.TEXT_DIM)


func _on_learn_pressed() -> void:
	if node_data.is_empty() or GameManager.is_learned(node_data.id):
		return
	var xp := GameManager.learn_node(node_data)
	SaveSystem.save_all()
	Audio.play("confirm", 0.0)
	_update_status_display()
	_build_related()
	if xp > 0:
		_show_xp_popup(xp)
	else:
		EventBus.notify("Отмечено как изученное (XP за эту тему уже был получен)", "info")
	# Подсказка: все подтемы раздела изучены
	if not node_data.is_main:
		var parent := ContentParser.get_parent_node(node_data.id)
		var prog: Array = GameManager.subnode_progress(parent)
		if prog[0] == prog[1] and not GameManager.is_learned(parent.id):
			EventBus.notify("Все подтемы раздела «%s» изучены — отметь и сам раздел!" % parent.title, "success")


func _on_unlearn_pressed() -> void:
	GameManager.unlearn_node(node_data.id)
	SaveSystem.save_all()
	_update_status_display()
	_build_related()


func _show_xp_popup(xp: int) -> void:
	var center := learn_btn.global_position + learn_btn.size / 2.0
	var particles := CPUParticles2D.new()
	particles.top_level = true
	particles.z_index = 40
	particles.position = center
	particles.one_shot = true
	particles.amount = 48
	particles.lifetime = 0.9
	particles.explosiveness = 0.95
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.emission_rect_extents = Vector2(learn_btn.size.x / 2.0, 6)
	particles.direction = Vector2(0, -1)
	particles.spread = 70.0
	particles.initial_velocity_min = 140.0
	particles.initial_velocity_max = 320.0
	particles.gravity = Vector2(0, 420)
	particles.scale_amount_min = 2.0
	particles.scale_amount_max = 4.5
	var ramp := Gradient.new()
	ramp.set_color(0, Palette.MINT.lightened(0.3))
	ramp.set_color(1, Color(spec_color, 0.0))
	particles.color_ramp = ramp
	add_child(particles)
	particles.emitting = true
	get_tree().create_timer(1.6).timeout.connect(particles.queue_free)

	var label := Label.new()
	label.text = "+%d XP" % xp
	label.theme_type_variation = &"TitleLabel"
	label.add_theme_font_size_override("font_size", 28)
	label.add_theme_color_override("font_color", Palette.MINT)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 8)
	label.top_level = true
	label.z_index = 41
	add_child(label)
	label.global_position = center - Vector2(50, 60)
	var tw := label.create_tween().set_parallel()
	tw.tween_property(label, "global_position:y", label.global_position.y - 70, 1.2).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(label, "modulate:a", 0.0, 0.8).set_delay(0.5)
	tw.chain().tween_callback(label.queue_free)


# ---------------------------------------------------------------- Навигация

func _update_nav_buttons() -> void:
	var prev := ContentParser.get_neighbor_node(node_data.id, -1)
	var next := ContentParser.get_neighbor_node(node_data.id, 1)
	prev_btn.disabled = prev.is_empty()
	next_btn.disabled = next.is_empty()
	prev_btn.tooltip_text = "← " + prev.get("title", "") if not prev.is_empty() else ""
	next_btn.tooltip_text = "→ " + next.get("title", "") if not next.is_empty() else ""


func _go_neighbor(step: int) -> void:
	var target := ContentParser.get_neighbor_node(node_data.get("id", ""), step)
	if not target.is_empty():
		EventBus.go("lesson", {"node_id": target.id, "replace": true})


func _unhandled_key_input(event: InputEvent) -> void:
	if notes_edit.has_focus() or not event.is_pressed() or event.is_echo():
		return
	if event.is_action("ui_left"):
		_go_neighbor(-1)
		accept_event()
	elif event.is_action("ui_right"):
		_go_neighbor(1)
		accept_event()


func _build_related() -> void:
	for child in related_list.get_children():
		child.queue_free()
	var items: Array = []
	if node_data.is_main:
		var prog: Array = GameManager.subnode_progress(node_data)
		related_title.text = "Подтемы  %d/%d" % prog
		items = node_data.subnodes
		if items.is_empty():
			var empty := Label.new()
			empty.text = "У этого раздела нет подтем."
			empty.theme_type_variation = &"DimLabel"
			related_list.add_child(empty)
	else:
		var parent := ContentParser.get_parent_node(node_data.id)
		related_title.text = "Раздел"
		related_list.add_child(_related_button(parent, false, true))
		var sep := HSeparator.new()
		related_list.add_child(sep)
		items = parent.get("subnodes", [])
	for item in items:
		related_list.add_child(_related_button(item, item.id == node_data.id, false))


func _related_button(item: Dictionary, is_current: bool, is_parent: bool) -> Button:
	var btn := Button.new()
	btn.theme_type_variation = &"GhostButton"
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	btn.clip_text = true
	btn.text = item.get("title", "")
	btn.tooltip_text = item.get("title", "")
	btn.custom_minimum_size.x = 100
	var status := GameManager.get_node_status(item.get("id", ""))
	var learned := status == GameManager.STATUS_LEARNED
	btn.icon = Palette.icon("layers" if is_parent else ("check" if learned else ("book-open" if status != "" else "circle-dot")))
	var color := Palette.MINT if learned else (Palette.TEXT if status != "" else Palette.TEXT_DIM)
	if is_current:
		color = spec_color.lightened(0.35)
		btn.add_theme_stylebox_override("normal", Palette.box(Color(spec_color, 0.15), Color(spec_color, 0.5), 1, 8, 10, 6))
	for key in ["font_color", "font_hover_color", "icon_normal_color", "icon_hover_color"]:
		btn.add_theme_color_override(key, color)
	if item.get("is_purple", false) and not learned:
		btn.add_theme_color_override("icon_normal_color", Palette.PURPLE)
	if not is_current:
		btn.pressed.connect(func(): EventBus.go("lesson", {"node_id": item.id, "replace": true}))
	return btn


# ---------------------------------------------------------------- Заметки для Claude

func _on_notes_changed() -> void:
	saved_label.text = "…"
	notes_timer.start()


func _save_notes() -> void:
	if node_data.is_empty():
		return
	GameManager.set_note(node_data.id, notes_edit.text)
	SaveSystem.save_all()
	ClaudeNotesExporter.export_all()
	if is_instance_valid(saved_label):
		saved_label.text = "Сохранено ✓"
