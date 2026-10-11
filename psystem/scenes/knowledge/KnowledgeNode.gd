extends PanelContainer
## Узел мини-дерева. Визуальные состояния:
##   не изучен — тёмный, пунктирная рамка; в процессе — слабое свечение;
##   изучен — яркое свечение + ✓; фиолетовый (дополнительный) — фиолетовая рамка, полупрозрачный.

signal pressed(node_data: Dictionary)

const MAIN_SIZE := Vector2(230, 96)
const SUB_SIZE := Vector2(210, 80)

var node_data: Dictionary = {}
var spec_id: String = ""
var spec_color: Color = Palette.ACCENT
var _status: String = ""
var _hover_tween: Tween

@onready var status_icon: TextureRect = $VBox/Top/StatusIcon
@onready var title_label: Label = $VBox/Top/Title
@onready var stars_label: Label = $VBox/Bottom/Stars
@onready var freq_label: Label = $VBox/Bottom/Freq
@onready var info_label: Label = $VBox/Bottom/Info


func _ready() -> void:
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


func setup_mini(data: Dictionary, sid: String) -> void:
	node_data = data
	spec_id = sid
	spec_color = ContentParser.get_spec_color(sid)
	var is_main: bool = data.get("is_main", false)
	custom_minimum_size = MAIN_SIZE if is_main else SUB_SIZE
	size = custom_minimum_size
	pivot_offset = size / 2.0
	title_label.text = data.get("title", "")
	if is_main:
		title_label.add_theme_font_override("font", Palette.FONT_TEXT_SEMI)
		title_label.add_theme_font_size_override("font_size", 15)
	stars_label.text = XPCalculator.stars(data.get("difficulty", 1))
	var freq: int = data.get("frequency", 0)
	freq_label.visible = freq > 0
	freq_label.text = "%d%%" % freq
	freq_label.tooltip_text = Loc.t("Частота вопроса на собеседованиях")
	tooltip_text = data.get("title", "")
	refresh()


func refresh() -> void:
	_status = GameManager.get_node_status(node_data.get("id", ""))
	var learned := _status == GameManager.STATUS_LEARNED
	var purple: bool = node_data.get("is_purple", false)
	var border_color := Palette.PURPLE if purple else spec_color
	var is_main: bool = node_data.get("is_main", false)

	var sb: StyleBoxFlat
	if learned:
		sb = Palette.glow_box(spec_color.darkened(0.72), Palette.MINT, Color(Palette.MINT, 0.3), 10, 10)
	elif _status == GameManager.STATUS_IN_PROGRESS:
		sb = Palette.glow_box(Palette.PANEL_2, Color(border_color, 0.75), Color(border_color, 0.18), 6, 10)
		sb.set_border_width_all(1)
	else:
		sb = Palette.box(Color(Palette.PANEL, 0.88), Color.TRANSPARENT, 0, 10)
	if purple and not learned:
		sb.border_color = Palette.PURPLE
		sb.set_border_width_all(2 if _status != "" else 0)
	sb.content_margin_left = 12
	sb.content_margin_right = 12
	sb.content_margin_top = 10
	sb.content_margin_bottom = 8
	add_theme_stylebox_override("panel", sb)

	modulate.a = 0.85 if purple and not learned else 1.0
	title_label.add_theme_color_override("font_color", Color.WHITE if learned else (Palette.TEXT if _status != "" else Palette.TEXT_DIM))
	status_icon.texture = Palette.icon("check" if learned else ("book-open" if _status != "" else "circle-dot"))
	status_icon.modulate = Palette.MINT if learned else Color(border_color, 0.9 if _status != "" else 0.5)

	if is_main and not node_data.get("subnodes", []).is_empty():
		var prog: Array = GameManager.subnode_progress(node_data)
		info_label.text = "%d/%d" % prog
		info_label.tooltip_text = Loc.t("Изучено подтем")
	else:
		info_label.text = "✓" if learned else "+%d XP" % node_data.get("xp_reward", 0)
	info_label.add_theme_color_override("font_color", Palette.MINT if learned else Palette.TEXT_DIM)
	queue_redraw()


func _draw() -> void:
	# Пунктирная рамка для неизученных узлов
	if _status != "":
		return
	var color := Color(Palette.PURPLE if node_data.get("is_purple", false) else spec_color, 0.45)
	var r := Rect2(Vector2(1, 1), size - Vector2(2, 2))
	var corners := [r.position, Vector2(r.end.x, r.position.y), r.end, Vector2(r.position.x, r.end.y)]
	for i in 4:
		draw_dashed_line(corners[i], corners[(i + 1) % 4], color, 1.5, 6.0)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if Rect2(Vector2.ZERO, size).has_point(event.position):
			Audio.play("click")
			pressed.emit(node_data)
			accept_event()


func _make_custom_tooltip(_for_text: String) -> Object:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 380
	var title := Label.new()
	title.text = node_data.get("title", "")
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title.add_theme_font_override("font", Palette.FONT_TEXT_BOLD)
	title.add_theme_color_override("font_color", spec_color.lightened(0.3))
	box.add_child(title)
	var meta := Label.new()
	meta.text = "%s   +%d XP%s" % [XPCalculator.stars(node_data.get("difficulty", 1)), node_data.get("xp_reward", 0),
		Loc.t("   · дополнительный") if node_data.get("is_purple", false) else ""]
	meta.add_theme_color_override("font_color", Palette.ENERGY)
	meta.add_theme_font_size_override("font_size", 13)
	box.add_child(meta)
	var preview := ContentParser.plain_preview(node_data.get("content", ""), 260)
	if preview != "":
		var body := Label.new()
		body.text = preview
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_color_override("font_color", Palette.TEXT_DIM)
		body.add_theme_font_size_override("font_size", 13)
		box.add_child(body)
	return box


func _set_hover(on: bool) -> void:
	if _hover_tween:
		_hover_tween.kill()
	z_index = 5 if on else 0
	if on:
		Audio.play_hover()
	_hover_tween = create_tween()
	_hover_tween.tween_property(self, "scale", Vector2.ONE * (1.06 if on else 1.0), 0.15) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
