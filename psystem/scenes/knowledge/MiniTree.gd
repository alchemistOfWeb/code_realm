extends Control
## Дерево навыков одной специализации: колонки «главный узел + подузлы под ним»,
## главные узлы соединены по горизонтали. Группы (тиры из # заголовков) — баннеры сверху.

const NODE_SCENE := preload("res://scenes/knowledge/KnowledgeNode.tscn")
const LINE_SHADER := preload("res://shaders/tree_connection.gdshader")

const PAD := 30.0
const COL_W := 280.0
const SUB_INDENT := 44.0
const SUB_GAP := 14.0
const GROUP_H := 34.0
const MAIN_SIZE := Vector2(230, 96)   # = KnowledgeNode.MAIN_SIZE
const SUB_SIZE := Vector2(210, 80)    # = KnowledgeNode.SUB_SIZE

@onready var spec_title: Label = %SpecTitle
@onready var spec_desc: Label = %SpecDesc
@onready var spec_icon: TextureRect = %SpecIcon
@onready var progress_label: Label = %ProgressLabel
@onready var progress_bar: ProgressBar = %ProgressBar
@onready var reset_btn: Button = %ResetButton
@onready var test_btn: Button = %TestButton
@onready var scroll: ScrollContainer = %Scroll
@onready var nodes_area: Control = %NodesArea
@onready var lines_layer: Control = %Lines
@onready var legend: HBoxContainer = %Legend

var current_spec_id: String = ""
var spec_data: Dictionary = {}
var spec_color: Color = Palette.ACCENT

var _visuals: Array = []      # KnowledgeNode
var _lines: Array = []        # [Line2D, node_id]
var _line_material: ShaderMaterial
var _dragging := false


func _ready() -> void:
	_line_material = ShaderMaterial.new()
	_line_material.shader = LINE_SHADER
	%BackButton.pressed.connect(EventBus.back)
	reset_btn.pressed.connect(_on_reset_pressed)
	test_btn.pressed.connect(_on_test_pressed)
	scroll.gui_input.connect(_on_scroll_input)
	nodes_area.gui_input.connect(_on_area_input)
	EventBus.progress_changed.connect(_on_progress_changed)


func _on_progress_changed(_spec_id: String) -> void:
	if is_visible_in_tree():
		_refresh_states()


func setup(params: Dictionary) -> void:
	current_spec_id = params.get("spec_id", "")
	spec_data = ContentParser.get_specialization(current_spec_id)
	spec_color = ContentParser.get_spec_color(current_spec_id)
	var meta := ContentParser.get_spec_meta(current_spec_id)
	spec_title.text = meta.get("name", current_spec_id)
	spec_title.add_theme_color_override("font_color", spec_color.lightened(0.15))
	spec_desc.text = meta.get("description", spec_data.get("title", ""))
	spec_icon.modulate = spec_color
	if ResourceLoader.exists(meta.get("icon", "")):
		spec_icon.texture = load(meta.icon)
	_build_legend()
	_build_tree()
	_update_progress()


func on_resume() -> void:
	_refresh_states()


# ---------------------------------------------------------------- Построение дерева

func _build_tree() -> void:
	for child in nodes_area.get_children():
		if child != lines_layer:
			child.queue_free()
	for child in lines_layer.get_children():
		child.queue_free()
	_visuals.clear()
	_lines.clear()

	var nodes: Array = spec_data.get("nodes", [])
	if nodes.is_empty():
		var empty := Label.new()
		empty.text = Loc.t("Контент не найден. Добавь .md файл в content/ и укажи его в data/specializations.json")
		empty.theme_type_variation = &"DimLabel"
		empty.position = Vector2(PAD, PAD)
		nodes_area.add_child(empty)
		return

	var has_groups := false
	for node in nodes:
		if node.get("group", "") != "":
			has_groups = true
			break
	var top := PAD + (GROUP_H + 16.0 if has_groups else 0.0)
	var main_w := MAIN_SIZE.x
	var main_h := MAIN_SIZE.y
	var sub_h := SUB_SIZE.y
	var max_y := top + main_h

	for i in nodes.size():
		var node: Dictionary = nodes[i]
		var x := PAD + i * COL_W
		_add_node(node, Vector2(x, top))
		var trunk_x := x + 20.0
		var prev_y := top + main_h
		var y := top + main_h + 22.0
		for sub in node.subnodes:
			_add_node(sub, Vector2(x + SUB_INDENT, y))
			var cy := y + sub_h / 2.0
			_add_line(PackedVector2Array([Vector2(trunk_x, prev_y), Vector2(trunk_x, cy), Vector2(x + SUB_INDENT, cy)]), sub.id, 3.0)
			prev_y = cy
			y += sub_h + SUB_GAP
		max_y = maxf(max_y, y)
		if i < nodes.size() - 1:
			var my := top + main_h / 2.0
			_add_line(PackedVector2Array([Vector2(x + main_w, my), Vector2(x + COL_W, my)]), node.id, 5.0)

	if has_groups:
		_build_group_banners(nodes, main_w)
	nodes_area.custom_minimum_size = Vector2(PAD * 2.0 + (nodes.size() - 1) * COL_W + main_w, max_y + PAD)
	lines_layer.size = nodes_area.custom_minimum_size


func _add_node(data: Dictionary, pos: Vector2) -> void:
	var visual := NODE_SCENE.instantiate()
	nodes_area.add_child(visual)
	visual.position = pos
	visual.setup_mini(data, current_spec_id)
	visual.pressed.connect(_on_node_pressed)
	_visuals.append(visual)


func _add_line(points: PackedVector2Array, node_id: String, width: float) -> void:
	var line := Line2D.new()
	line.points = points
	line.width = width
	line.texture_mode = Line2D.LINE_TEXTURE_STRETCH
	line.joint_mode = Line2D.LINE_JOINT_ROUND
	line.antialiased = true
	line.material = _line_material
	lines_layer.add_child(line)
	_lines.append([line, node_id])
	_color_line(line, node_id)


func _color_line(line: Line2D, node_id: String) -> void:
	var node := ContentParser.get_node_data(node_id)
	var base := Palette.PURPLE if node.get("is_purple", false) else spec_color
	line.default_color = Color(base, 1.0 if GameManager.is_learned(node_id) else 0.2)


func _build_group_banners(nodes: Array, main_w: float) -> void:
	var start := 0
	for i in range(1, nodes.size() + 1):
		if i < nodes.size() and nodes[i].get("group", "") == nodes[start].get("group", ""):
			continue
		var group: String = nodes[start].get("group", "")
		if group != "":
			var banner := PanelContainer.new()
			var sb := Palette.box(Color(spec_color, 0.10), Color(spec_color, 0.45), 1, 8, 12, 4)
			banner.add_theme_stylebox_override("panel", sb)
			banner.position = Vector2(PAD + start * COL_W, PAD)
			banner.size = Vector2((i - 1 - start) * COL_W + main_w, GROUP_H)
			banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
			var label := Label.new()
			label.text = group
			label.theme_type_variation = &"MonoLabel"
			label.add_theme_font_size_override("font_size", 13)
			label.add_theme_color_override("font_color", spec_color.lightened(0.35))
			label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			label.clip_text = true
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			banner.add_child(label)
			nodes_area.add_child(banner)
		start = i


func _build_legend() -> void:
	for child in legend.get_children():
		child.queue_free()
	var items := [
		[Loc.t("Изучено"), Palette.glow_box(spec_color.darkened(0.72), Palette.MINT, Color(Palette.MINT, 0.3), 3, 4)],
		[Loc.t("В процессе"), Palette.box(Palette.PANEL_2, Color(spec_color, 0.75), 1, 4)],
		[Loc.t("Не начато"), Palette.box(Palette.PANEL, Color(spec_color, 0.3), 1, 4)],
		[Loc.t("Дополнительный"), Palette.box(Palette.PANEL, Palette.PURPLE, 2, 4)],
	]
	for item in items:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		var swatch := Panel.new()
		swatch.custom_minimum_size = Vector2(16, 16)
		swatch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		swatch.add_theme_stylebox_override("panel", item[1])
		row.add_child(swatch)
		var label := Label.new()
		label.text = item[0]
		label.theme_type_variation = &"DimLabel"
		row.add_child(label)
		legend.add_child(row)


# ---------------------------------------------------------------- Состояние

func _refresh_states() -> void:
	for v in _visuals:
		if is_instance_valid(v):
			v.refresh()
	for pair in _lines:
		_color_line(pair[0], pair[1])
	_update_progress()


func _update_progress() -> void:
	var total := ContentParser.count_nodes(current_spec_id)
	var learned := GameManager.count_learned(current_spec_id)
	var pct := roundi(100.0 * learned / maxf(total, 1))
	progress_label.text = Loc.t("%d / %d узлов (%d%%)") % [learned, total, pct]
	progress_bar.max_value = maxi(total, 1)
	progress_bar.value = learned
	_update_test_button()


func _update_test_button() -> void:
	var rec := GameManager.test_record("tree:" + current_spec_id)
	var tip := "Общий тест: %d вопросов по обязательным темам, зачёт от %d%%.
" % [QuizGenerator.TREE_TEST, roundi(XPCalculator.TREE_TEST_PASS_RATIO * 100)]
	tip += Loc.t("Первый зачёт: все обязательные темы изучены, +%d XP, +%d энергии и %d карт(ы).") % [
		GameManager.tree_xp_bonus(current_spec_id), XPCalculator.TREE_TEST_ENERGY_REWARD,
		XPCalculator.tree_card_count(CardDatabase.avg_tree_difficulty(current_spec_id))]
	test_btn.disabled = false
	if rec.get("passes", 0) > 0:
		test_btn.text = Loc.t("Общий тест ✓  %d/%d") % [rec.best, rec.total]
		var left := GameManager.tree_test_cooldown_left(current_spec_id)
		tip += "

Пройден %d раз(а). Повтор: 1 карта, +%d энергии, 25%% XP — " % [rec.passes, XPCalculator.TREE_RETEST_ENERGY]
		tip += Loc.t("доступно сейчас.") if left == 0 else Loc.t("через %d ч.") % ceili(left / 3600.0)
	else:
		test_btn.text = Loc.t("Пройти общий тест")
	test_btn.tooltip_text = tip


func _on_test_pressed() -> void:
	EventBus.go("test", {"mode": "tree", "spec_id": current_spec_id})


func _on_node_pressed(node_data: Dictionary) -> void:
	EventBus.go("lesson", {"node_id": node_data.id})


# ---------------------------------------------------------------- Сброс

func _on_reset_pressed() -> void:
	var dialog := ConfirmationDialog.new()
	dialog.title = Loc.t("Сбросить прогресс?")
	dialog.dialog_text = Loc.t("Все отметки дерева «%s» будут сброшены.\nXP и энергия останутся, повторно за эти узлы XP не начисляется.\nЗаметки для Claude сохранятся.") % spec_title.text
	dialog.ok_button_text = Loc.t("Сбросить")
	dialog.cancel_button_text = Loc.t("Отмена")
	dialog.confirmed.connect(_do_reset)
	dialog.visibility_changed.connect(_free_if_hidden.bind(dialog))
	add_child(dialog)
	dialog.popup_centered()


func _free_if_hidden(dialog: Window) -> void:
	if not dialog.visible:
		dialog.queue_free()


func _do_reset() -> void:
	Audio.play("drop")
	GameManager.reset_spec(current_spec_id)
	SaveSystem.save_all()
	_refresh_states()
	EventBus.notify(Loc.t("Прогресс дерева «%s» сброшен") % spec_title.text, "warning")


# ---------------------------------------------------------------- Прокрутка

func _on_scroll_input(event: InputEvent) -> void:
	# Колесо крутит по горизонтали, если вертикально прокручивать нечего
	if event is InputEventMouseButton and event.pressed and not event.shift_pressed:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if nodes_area.size.y <= scroll.size.y + 1.0:
				var dir := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
				scroll.scroll_horizontal += dir * 90
				scroll.accept_event()


func _on_area_input(event: InputEvent) -> void:
	# Перетаскивание пустого места — панорамирование
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE]:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		scroll.scroll_horizontal -= int(event.relative.x)
		scroll.scroll_vertical -= int(event.relative.y)
