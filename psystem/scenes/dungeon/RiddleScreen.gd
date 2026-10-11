extends Control
## Загадка на двери-механизме. Если тема загадки изучена — «Ты узнаёшь это»: два неверных
## варианта отсекаются. Ошибка бьёт током (−2 HP), можно пробовать снова.
## params: {riddle_id}. Итог — EventBus.riddle_finished(riddle_id, solved).

const DATA_FILE := "res://data/riddles.json"
const WRONG_DAMAGE := 2

static var _riddles: Dictionary = {}

var riddle: Dictionary = {}
var _options_box: VBoxContainer
var _result: RichTextLabel
var _solved := false


static func get_riddle(id: String) -> Dictionary:
	if _riddles.is_empty():
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(DATA_FILE))
		for r in parsed.get("riddles", []):
			_riddles[r.id] = r
	return _riddles.get(id, {})


static func all_ids() -> Array:
	get_riddle("")
	return _riddles.keys()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(params: Dictionary) -> void:
	riddle = get_riddle(params.get("riddle_id", ""))
	_build()
	Audio.play("gear")


func _build() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.01, 0.03, 0.82)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var bronze := Color("#B87333")
	panel.add_theme_stylebox_override("panel", Palette.glow_box(Color("#15100C", 0.97), bronze, Color(bronze, 0.3), 18, 14))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 720
	box.add_theme_constant_override("separation", 12)
	panel.add_child(box)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	box.add_child(head)
	var icon := TextureRect.new()
	icon.texture = Palette.game_icon("dungeon-gate")
	icon.custom_minimum_size = Vector2(48, 48)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.modulate = bronze.lightened(0.2)
	head.add_child(icon)
	var title := Label.new()
	title.text = "Дверь-механизм"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", bronze.lightened(0.3))
	head.add_child(title)
	var inscription := Label.new()
	inscription.text = riddle.get("inscription", "")
	inscription.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inscription.add_theme_font_size_override("font_size", 18)
	inscription.add_theme_color_override("font_color", Color("#EADBC0"))
	inscription.add_theme_font_override("font", Palette.italic_font())
	box.add_child(inscription)
	var q := Label.new()
	q.text = riddle.get("question", "")
	q.add_theme_font_override("font", Palette.FONT_TEXT_BOLD)
	q.add_theme_font_size_override("font_size", 17)
	box.add_child(q)

	var req := {"spec": riddle.get("spec", ""), "topic": riddle.get("topic", "")}
	var knows := Requirements.knowledge_met(req)
	var hint := RichTextLabel.new()
	hint.bbcode_enabled = true
	hint.fit_content = true
	var spec_color := Palette.hex(ContentParser.get_spec_color(req.spec).lightened(0.25))
	if knows:
		hint.text = "[color=%s][b][ЗНАНИЕ · %s][/b][/color] Ты узнаёшь это: два неверных варианта отсечены." % [spec_color, Requirements.knowledge_label(req)]
	else:
		hint.text = "[color=#8C8CB0]Знание темы [color=%s]«%s»[/color] подсказало бы ответ.[/color]" % [spec_color, Requirements.knowledge_label(req)]
	box.add_child(hint)

	_options_box = VBoxContainer.new()
	_options_box.add_theme_constant_override("separation", 8)
	box.add_child(_options_box)
	var options: Array = []
	var opts: Array = riddle.get("options", [])
	var correct: int = riddle.get("correct", 0)
	for i in opts.size():
		options.append({"text": opts[i], "ok": i == correct})
	if knows:
		var wrong := options.filter(func(o): return not o.ok)
		wrong.shuffle()
		for i in mini(2, wrong.size() - 1):
			options.erase(wrong[i])
	options.shuffle()
	for o in options:
		var b := Button.new()
		b.text = o.text
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.custom_minimum_size.y = 44
		b.add_theme_font_override("font", Palette.FONT_TEXT)
		b.add_theme_font_size_override("font_size", 16)
		b.set_meta("sfx", "")
		b.pressed.connect(_answer.bind(b, o.ok))
		_options_box.add_child(b)
	_result = RichTextLabel.new()
	_result.bbcode_enabled = true
	_result.fit_content = true
	box.add_child(_result)
	var leave := Button.new()
	leave.text = "Отойти от двери"
	leave.theme_type_variation = &"GhostButton"
	leave.pressed.connect(_close)
	box.add_child(leave)


func _answer(btn: Button, ok: bool) -> void:
	if _solved:
		return
	if ok:
		_solved = true
		btn.add_theme_stylebox_override("normal", Palette.box(Color(Palette.MINT, 0.2), Palette.MINT, 2, 8, 16, 9))
		_result.text = "[color=#00D4AA][b]Механизм щёлкает — решётка поднимается![/b][/color]\n[color=#8C8CB0]%s[/color]" % riddle.get("explanation", "")
		Audio.play("gate")
		Audio.play_jingle("reward")
		GameManager.gain_xp(10)
		GameManager.add_stat("riddles")
		for b in _options_box.get_children():
			b.disabled = true
		await get_tree().create_timer(2.2).timeout
		_close()
	else:
		btn.disabled = true
		btn.add_theme_stylebox_override("disabled", Palette.box(Color(Palette.HP, 0.15), Palette.HP, 1, 8, 16, 9))
		GameManager.damage_player(WRONG_DAMAGE)
		if GameManager.player_data.hp <= 0:
			GameManager.player_data.hp = 1
		_result.text = "[color=#FF6B6B]Разряд! Механизм бьёт током (−%d HP). Попробуй ещё раз.[/color]" % WRONG_DAMAGE
		Audio.play("hit_heavy")
		var tw := btn.create_tween()
		for d in [8.0, -8.0, 4.0, 0.0]:
			tw.tween_property(btn, "position:x", btn.position.x + d, 0.04)


func _close() -> void:
	EventBus.riddle_finished.emit(riddle.get("id", ""), _solved)
	EventBus.back()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_close()
