extends Control
## Диалог в стиле Baldur's Gate 3: портрет и имя NPC, печатающийся текст, нумерованные реплики
## с тегами [ЗНАНИЕ · …] (цвет специализации), [СИЛА · СЛ 13] (шанс), заблокированные реплики
## с подсказкой, анимированный бросок d20.
##
## params: {npc_id}. По завершении — EventBus.dialogue_finished(npc_id, world_actions).

var runner := DialogueRunner.new()
var _text: RichTextLabel
var _rewards: RichTextLabel
var _choices: VBoxContainer
var _portrait: TextureRect
var _name: Label
var _title: Label
var _panel: PanelContainer
var _busy := false
var _color := Palette.ACCENT
var _typing: Tween


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(params: Dictionary) -> void:
	var id: String = params.get("npc_id", "")
	_build(DialogueRunner.get_npc(id))
	var msgs := runner.start(id)
	Audio.play("open")
	_show_node(msgs)


func _build(npc: Dictionary) -> void:
	_color = Color.from_string(npc.get("color", "#7B68EE"), Palette.ACCENT)
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var grad := GradientTexture2D.new()
	grad.fill_from = Vector2(0, 0)
	grad.fill_to = Vector2(0, 1)
	var g := Gradient.new()
	g.set_color(0, Color(0, 0, 0, 0.15))
	g.set_color(1, Color(0, 0, 0, 0.88))
	grad.gradient = g
	var tex := TextureRect.new()
	tex.texture = grad
	tex.set_anchors_preset(Control.PRESET_FULL_RECT)
	tex.stretch_mode = TextureRect.STRETCH_SCALE
	tex.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(tex)

	var root := HBoxContainer.new()
	root.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	root.anchor_top = 0.18
	root.offset_left = 30
	root.offset_right = -30
	root.offset_bottom = -20
	root.add_theme_constant_override("separation", 22)
	root.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(root)

	# Портрет
	var left := VBoxContainer.new()
	left.custom_minimum_size.x = 230
	left.alignment = BoxContainer.ALIGNMENT_END
	left.add_theme_constant_override("separation", 6)
	root.add_child(left)
	var frame := PanelContainer.new()
	frame.custom_minimum_size = Vector2(200, 200)
	frame.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	var fsb := Palette.glow_box(_color.darkened(0.75), _color, Color(_color, 0.4), 18, 100)
	frame.add_theme_stylebox_override("panel", fsb)
	left.add_child(frame)
	_portrait = TextureRect.new()
	_portrait.texture = Palette.game_icon(npc.get("portrait", "hooded-figure"))
	_portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.modulate = _color.lightened(0.35)
	frame.add_child(_portrait)
	_name = Label.new()
	_name.text = Loc.f(npc, "name", "?")
	_name.theme_type_variation = &"HeaderLabel"
	_name.add_theme_color_override("font_color", _color.lightened(0.3))
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(_name)
	_title = Label.new()
	_title.text = Loc.f(npc, "title")
	_title.theme_type_variation = &"DimLabel"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	left.add_child(_title)

	# Текст и реплики
	_panel = PanelContainer.new()
	_panel.custom_minimum_size.x = 760
	_panel.size_flags_vertical = Control.SIZE_SHRINK_END
	var psb := Palette.box(Color("#0B0A14", 0.94), Color(_color, 0.45), 1, 14, 22, 18)
	psb.border_width_top = 3
	_panel.add_theme_stylebox_override("panel", psb)
	root.add_child(_panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	_panel.add_child(box)
	_text = RichTextLabel.new()
	_text.bbcode_enabled = true
	_text.fit_content = true
	_text.scroll_active = false
	_text.add_theme_font_size_override("normal_font_size", 17)
	_text.add_theme_font_size_override("italics_font_size", 16)
	_text.add_theme_color_override("default_color", Color("#E8E2D0"))
	box.add_child(_text)
	_rewards = RichTextLabel.new()
	_rewards.bbcode_enabled = true
	_rewards.fit_content = true
	_rewards.scroll_active = false
	_rewards.add_theme_font_override("normal_font", Palette.FONT_UI_BOLD)
	_rewards.add_theme_font_size_override("normal_font_size", 13)
	box.add_child(_rewards)
	box.add_child(HSeparator.new())
	_choices = VBoxContainer.new()
	_choices.add_theme_constant_override("separation", 4)
	box.add_child(_choices)


# ---------------------------------------------------------------- Узел

func _show_node(messages: Array) -> void:
	if runner.finished:
		_finish()
		return
	var md: String = Loc.t(runner.node.get("text", ""))
	_text.text = MarkdownBBCode.to_bbcode(md, _color.lightened(0.3)).replace("[i]", "[i][color=#A9A2C4]").replace("[/i]", "[/color][/i]")
	_text.visible_ratio = 0.0
	if _typing:
		_typing.kill()
	_typing = create_tween()
	_typing.tween_property(_text, "visible_ratio", 1.0, clampf(md.length() / 220.0, 0.4, 2.2))
	_show_rewards(messages)
	_build_choices()


func _show_rewards(messages: Array) -> void:
	if messages.is_empty():
		_rewards.text = ""
		_rewards.visible = false
		return
	_rewards.visible = true
	var parts: PackedStringArray = []
	for m in messages:
		var col := "#F5C542"
		if m.begins_with("−"):
			col = "#FF6B6B"
		elif "XP" in m or "HP" in m:
			col = "#00D4AA"
		elif m.begins_with(Loc.t("Нов")) or Loc.t("квест") in m.to_lower():
			col = "#C792EA"
		parts.append("[color=%s]%s[/color]" % [col, m])
	_rewards.text = "  ·  ".join(parts)
	Audio.play("coins")


func _build_choices() -> void:
	for c in _choices.get_children():
		c.queue_free()
	var n := 0
	for entry in runner.visible_choices():
		n += 1
		_choices.add_child(_choice_row(n, entry))


func _choice_row(n: int, entry: Dictionary) -> Control:
	var row := PanelContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_STOP
	row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if entry.available else Control.CURSOR_FORBIDDEN
	var normal := Palette.box(Color(0, 0, 0, 0), Color.TRANSPARENT, 0, 6, 10, 5)
	var hover := Palette.box(Color(_color, 0.14), Color(_color, 0.5), 1, 6, 10, 5)
	row.add_theme_stylebox_override("panel", normal)
	var label := RichTextLabel.new()
	label.bbcode_enabled = true
	label.fit_content = true
	label.scroll_active = false
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("normal_font_size", 16)
	label.add_theme_font_size_override("bold_font_size", 14)
	var tag := ""
	var tag_color := "#8C8CB0"
	match entry.tag_kind:
		"knowledge":
			tag_color = Palette.hex(ContentParser.get_spec_color(entry.spec).lightened(0.25))
		"check":
			tag_color = Palette.hex(Palette.ENERGY)
		"trade":
			tag_color = Palette.hex(Palette.GOLD)
	if entry.tag != "":
		tag = "[b][color=%s][%s][/color][/b] " % [tag_color, entry.tag.replace("[", "")]
	var chance := "  [color=#8C8CB0](≈%d%%)[/color]" % entry.chance if entry.chance >= 0 else ""
	var text_color := "#E8E2D0" if entry.available else "#5A5A78"
	var num_color := Palette.hex(_color.lightened(0.3)) if entry.available else "#5A5A78"
	label.text = "[color=%s]%d.[/color]  %s[color=%s]%s[/color]%s" % [num_color, n, tag if entry.available else "[color=#5A5A78]🔒 %s[/color]" % tag.replace("[b]", "").replace("[/b]", ""), text_color, entry.text.replace("[", "[lb]"), chance]
	if not entry.available:
		label.text += "\n[font_size=12][color=#8C6A4A]      %s[/color][/font_size]" % entry.reason
		row.tooltip_text = entry.reason
	row.add_child(label)
	row.mouse_entered.connect(func():
		if entry.available:
			row.add_theme_stylebox_override("panel", hover)
			Audio.play_hover())
	row.mouse_exited.connect(func(): row.add_theme_stylebox_override("panel", normal))
	row.gui_input.connect(func(e):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_pick(entry))
	row.set_meta("entry", entry)
	return row


func _pick(entry: Dictionary) -> void:
	if _busy:
		return
	if not entry.available:
		Audio.play("error")
		EventBus.notify(entry.reason, "warning")
		return
	if _typing and _typing.is_running():
		_typing.kill()
		_text.visible_ratio = 1.0
	_busy = true
	Audio.play("click")
	var result := runner.choose(entry.index)
	if not result.roll.is_empty():
		await _show_roll(result.roll)
	_busy = false
	if result.ended:
		_finish()
	else:
		_show_node(result.messages)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).keycode
	if key >= KEY_1 and key <= KEY_9:
		var i := key - KEY_1
		if i < _choices.get_child_count():
			_pick(_choices.get_child(i).get_meta("entry"))
			accept_event()
	elif key == KEY_SPACE and _typing and _typing.is_running():
		_typing.kill()
		_text.visible_ratio = 1.0
		accept_event()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()   # из диалога выходят репликой


# ---------------------------------------------------------------- Бросок d20

func _show_roll(roll: Dictionary) -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.6)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	center.add_child(box)
	var caption := Label.new()
	caption.text = Loc.t("ПРОВЕРКА: %s · СЛ %d") % [Loc.t(Requirements.ATTR_NAMES.get(roll.attr, roll.attr)), roll.dc]
	caption.theme_type_variation = &"MonoLabel"
	caption.add_theme_color_override("font_color", Palette.ENERGY)
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(caption)
	var die := Control.new()
	die.custom_minimum_size = Vector2(170, 170)
	box.add_child(die)
	var icon := TextureRect.new()
	icon.texture = Palette.game_icon("dice-twenty-faces-twenty")
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.size = Vector2(170, 170)
	icon.pivot_offset = Vector2(85, 85)
	icon.modulate = Color("#C9B27A")
	die.add_child(icon)
	var num := Label.new()
	num.add_theme_font_override("font", Palette.FONT_DISPLAY)
	num.add_theme_font_size_override("font_size", 44)
	num.add_theme_color_override("font_color", Color.WHITE)
	num.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	num.add_theme_constant_override("outline_size", 10)
	num.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	num.size = Vector2(170, 170)
	die.add_child(num)
	var detail := Label.new()
	detail.theme_type_variation = &"MonoLabel"
	detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(detail)
	var verdict := Label.new()
	verdict.theme_type_variation = &"TitleLabel"
	verdict.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(verdict)

	# Вращение и мелькание чисел
	var spin := icon.create_tween()
	spin.tween_property(icon, "rotation", TAU * 3, 1.1).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for i in 14:
		num.text = str(randi_range(1, 20))
		Audio.play("gear", 0.2)
		await get_tree().create_timer(0.05 + i * 0.006).timeout
	num.text = str(roll.roll)
	var parts := Loc.t("%d (кубик)") % roll.roll
	if roll.attr_bonus != 0:
		parts += " + %d (%s)" % [roll.attr_bonus, Loc.t(Requirements.ATTR_NAMES.get(roll.attr, roll.attr)).to_lower()]
	if roll.know_bonus != 0:
		parts += Loc.t(" + %d (знания)") % roll.know_bonus
	detail.text = Loc.t("%s = %d  против СЛ %d") % [parts, roll.total, roll.dc]
	var color := Palette.MINT if roll.success else Palette.HP
	verdict.text = roll.natural if roll.natural != "" else (Loc.t("УСПЕХ") if roll.success else Loc.t("ПРОВАЛ"))
	verdict.add_theme_color_override("font_color", color)
	icon.modulate = color.lightened(0.2)
	Audio.play_jingle("reward" if roll.success else "drop")
	var pop := num.create_tween()
	num.pivot_offset = Vector2(85, 85)
	num.scale = Vector2(1.6, 1.6)
	pop.tween_property(num, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	await get_tree().create_timer(1.4).timeout
	overlay.queue_free()


func _finish() -> void:
	SaveSystem.save_all()
	EventBus.dialogue_finished.emit(runner.npc_id, runner.pending_world)
	EventBus.back()
