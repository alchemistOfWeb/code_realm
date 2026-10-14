extends Control
## Экран карточного боя. Логика — CombatState, здесь только отображение и ввод.
##
## params: {enemy_id, context: "training"|"expedition"}
## По завершении: EventBus.combat_finished(result) и возврат на предыдущий экран.
## result: {won, enemy_id, context, xp, gold, energy, cards, hp_left}

const CARD_SCENE := preload("res://scenes/combat/CardVisual.tscn")
const TOKEN_SCRIPT := preload("res://scenes/combat/CreatureToken.gd")
const HAND_SCALE := 0.52
## Увеличенная карта при наведении на карту в руке (описание читается полностью).
const PREVIEW_SCALE := 1.45
const EVENT_DELAY := 0.32

var state: CombatState
var enemy_data: Dictionary = {}
var context := "training"
var _targeting := {}          # {mode: "card"|"weapon"|"rune"|"creature", index/id/uid, type}
var _busy := false
var _finished := false

# UI
var _enemy_panel: PanelContainer
var _enemy_icon: TextureRect
var _enemy_hp: ProgressBar
var _enemy_hp_label: Label
var _enemy_intent: Label
var _enemy_info: Label
var _enemy_board: HBoxContainer
var _player_board: HBoxContainer
var _hand: HBoxContainer
var _player_hp: ProgressBar
var _player_hp_label: Label
var _res_label: RichTextLabel
var _weapons_box: HBoxContainer
var _runes_box: HBoxContainer
var _end_btn: Button
var _log: RichTextLabel
var _hint: Label
var _preview: Label
var _hover_card: Control
var _artifacts_player: HBoxContainer
var _artifacts_enemy: HBoxContainer
var _tokens := {}             # "side:uid" -> token


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_preset(Control.PRESET_FULL_RECT)


func setup(params: Dictionary) -> void:
	context = params.get("context", "training")
	enemy_data = XPCalculator.scaled_enemy(_find_enemy(params.get("enemy_id", "syntax_error")), float(params.get("power", 1.0)))
	var stats := GameManager.combat_stats()
	if context == "training":
		stats.hp = stats.max_hp
	stats.hp = maxi(1, stats.hp)
	var deck: Array = params.get("deck", GameManager.combat_deck_entries())
	state = CombatState.new()
	state.start(enemy_data, deck, stats)
	_build()
	Audio.push_music(Audio.BATTLE_MUSIC)
	Audio.play("draw", 0.0)
	_process_events(false)
	_refresh()


func _exit_tree() -> void:
	if state != null:
		Audio.pop_music()


static func _find_enemy(enemy_id: String) -> Dictionary:
	for e in CardDatabase.all_enemies():
		if e.id == enemy_id:
			return e
	return CardDatabase.all_enemies()[0]


# ---------------------------------------------------------------- Построение UI

func _build() -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.02, 0.02, 0.05, 0.55)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 12)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(root)

	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(col)

	# --- Враг
	var enemy_row := HBoxContainer.new()
	enemy_row.add_theme_constant_override("separation", 14)
	col.add_child(enemy_row)
	_enemy_panel = PanelContainer.new()
	_enemy_panel.custom_minimum_size = Vector2(400, 96)
	_enemy_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_enemy_panel.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_enemy_panel.gui_input.connect(_on_enemy_hero_input)
	enemy_row.add_child(_enemy_panel)
	var ep := HBoxContainer.new()
	ep.add_theme_constant_override("separation", 12)
	ep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_enemy_panel.add_child(ep)
	_enemy_icon = TextureRect.new()
	_enemy_icon.texture = Palette.game_icon(enemy_data.get("icon", "android-mask"))
	_enemy_icon.custom_minimum_size = Vector2(72, 72)
	_enemy_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_enemy_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_enemy_icon.modulate = Color.from_string(enemy_data.get("color", "#E74C3C"), Palette.HP).lightened(0.25)
	_enemy_icon.pivot_offset = Vector2(36, 36)
	_enemy_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ep.add_child(_enemy_icon)
	var ei := VBoxContainer.new()
	ei.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ei.add_theme_constant_override("separation", 3)
	ei.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ep.add_child(ei)
	var en := Label.new()
	en.text = "%s — %s" % [enemy_data.get("name", "?"), enemy_data.get("title", "")]
	en.theme_type_variation = &"HeaderLabel"
	en.add_theme_font_size_override("font_size", 15)
	en.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ei.add_child(en)
	var hp_row := HBoxContainer.new()
	hp_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ei.add_child(hp_row)
	_enemy_hp = _bar("HPBar", hp_row)
	_enemy_hp_label = _mono(hp_row, "", Palette.HP)
	_enemy_intent = _mono(ei, "", Palette.ENERGY)
	_enemy_info = _mono(ei, "", Palette.TEXT_DIM)
	_enemy_info.add_theme_font_size_override("font_size", 11)

	var desc := Label.new()
	desc.text = enemy_data.get("description", "")
	desc.theme_type_variation = &"DimLabel"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.custom_minimum_size.x = 160
	desc.max_lines_visible = 3
	desc.clip_text = true
	enemy_row.add_child(desc)
	_artifacts_enemy = HBoxContainer.new()
	enemy_row.add_child(_artifacts_enemy)

	_enemy_board = _board_row(col)
	var sep := HSeparator.new()
	col.add_child(sep)
	_player_board = _board_row(col)

	# --- Игрок: ресурсы, оружие, руны, конец хода
	var player_row := HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 10)
	col.add_child(player_row)
	var stats := VBoxContainer.new()
	stats.custom_minimum_size.x = 200
	stats.add_theme_constant_override("separation", 2)
	player_row.add_child(stats)
	var php := HBoxContainer.new()
	stats.add_child(php)
	_player_hp = _bar("HPBar", php)
	_player_hp_label = _mono(php, "", Palette.HP)
	_res_label = RichTextLabel.new()
	_res_label.bbcode_enabled = true
	_res_label.fit_content = true
	_res_label.scroll_active = false
	_res_label.custom_minimum_size.x = 200
	_res_label.add_theme_font_override("normal_font", Palette.FONT_UI_BOLD)
	_res_label.add_theme_font_size_override("normal_font_size", 13)
	stats.add_child(_res_label)
	_weapons_box = HBoxContainer.new()
	_weapons_box.add_theme_constant_override("separation", 4)
	player_row.add_child(_weapons_box)
	player_row.add_child(VSeparator.new())
	_runes_box = HBoxContainer.new()
	_runes_box.add_theme_constant_override("separation", 4)
	player_row.add_child(_runes_box)
	_artifacts_player = HBoxContainer.new()
	player_row.add_child(_artifacts_player)
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	player_row.add_child(sp)
	var surrender := Button.new()
	surrender.text = ""
	surrender.icon = Palette.icon("x")
	surrender.theme_type_variation = &"GhostButton"
	surrender.tooltip_text = Loc.t("Покинуть бой (засчитывается поражение)")
	surrender.pressed.connect(_on_surrender)
	surrender.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	player_row.add_child(surrender)
	_end_btn = Button.new()
	_end_btn.text = Loc.t("Завершить ход")
	_end_btn.theme_type_variation = &"AccentButton"
	_end_btn.custom_minimum_size = Vector2(150, 44)
	_end_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_end_btn.set_meta("sfx", "")
	_end_btn.pressed.connect(_on_end_turn)
	player_row.add_child(_end_btn)
	for id in state.weapons:
		_weapons_box.add_child(_action_button(XPCalculator.WEAPONS[id], "weapon", id))
	for id in XPCalculator.RUNES:
		_runes_box.add_child(_action_button(XPCalculator.RUNES[id], "rune", id))

	_hand = HBoxContainer.new()
	_hand.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand.add_theme_constant_override("separation", 6)
	_hand.custom_minimum_size.y = CardVisualSize.y * HAND_SCALE + 6
	col.add_child(_hand)

	# --- Журнал справа
	var side_col := VBoxContainer.new()
	side_col.custom_minimum_size.x = 220
	side_col.add_theme_constant_override("separation", 6)
	root.add_child(side_col)
	_hint = Label.new()
	_hint.theme_type_variation = &"MonoLabel"
	_hint.add_theme_color_override("font_color", Palette.ENERGY)
	_hint.add_theme_font_size_override("font_size", 12)
	_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_hint.custom_minimum_size.y = 34
	side_col.add_child(_hint)
	var log_panel := PanelContainer.new()
	log_panel.theme_type_variation = &"CardPanel"
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	side_col.add_child(log_panel)
	_log = RichTextLabel.new()
	_log.bbcode_enabled = true
	_log.scroll_following = true
	_log.add_theme_font_size_override("normal_font_size", 12)
	log_panel.add_child(_log)
	_preview = Label.new()
	_preview.custom_minimum_size = Vector2(220, 0)
	_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_preview.add_theme_font_size_override("font_size", 13)
	_preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	side_col.add_child(_preview)


const CardVisualSize := Vector2(200, 280)


func _board_row(parent: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.custom_minimum_size.y = 122
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	return row


func _bar(variation: String, parent: Control) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.theme_type_variation = StringName(variation)
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(150, 12)
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(bar)
	return bar


func _mono(parent: Control, text: String, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.theme_type_variation = &"MonoLabel"
	l.add_theme_font_size_override("font_size", 13)
	l.add_theme_color_override("font_color", color)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _action_button(info: Dictionary, kind: String, id: String) -> Button:
	var b := Button.new()
	b.icon = Palette.game_icon(info.icon)
	b.add_theme_constant_override("icon_max_width", 22)
	b.custom_minimum_size = Vector2(0, 44)
	b.add_theme_constant_override("h_separation", 4)
	b.set_meta("kind", kind)
	b.set_meta("id", id)
	b.pressed.connect(_on_action.bind(kind, id))
	return b


# ---------------------------------------------------------------- Отрисовка состояния

func _refresh() -> void:
	var p := state.player
	var e := state.enemy
	_enemy_hp.max_value = e.max_hp
	_enemy_hp.value = maxi(e.hp, 0)
	_enemy_hp_label.text = " %d/%d" % [maxi(e.hp, 0), e.max_hp]
	_enemy_intent.text = state.enemy_intent()
	_enemy_info.text = Loc.t("◆ %d/%d  ·  карт в руке: %d  ·  колода: %d") % [e.crystals, e.max_crystals, e.hand.size(), e.deck.size()]
	_player_hp.max_value = p.max_hp
	_player_hp.value = maxi(p.hp, 0)
	_player_hp_label.text = " %d/%d" % [maxi(p.hp, 0), p.max_hp]
	_res_label.text = Loc.t("[color=#7FDBFF]◆ %d/%d[/color]   [color=#C792EA]✦ %d[/color]   [color=#F5C542]⚡ %d/%d[/color]%s\n[color=#8C8CB0]колода %d · сброс %d · ход %d[/color]") % [
		p.crystals, p.max_crystals + p.crystal_bonus, p.mana, p.stamina, p.max_stamina,
		"   [color=#6FB3FF]🛡 %d[/color]" % p.shield if p.shield > 0 else "", p.deck.size(), p.discard.size(), state.turn]

	_tokens.clear()
	_fill_board(_enemy_board, e.board, "enemy")
	_fill_board(_player_board, p.board, "player")
	_fill_artifacts(_artifacts_player, p.artifacts)
	_fill_artifacts(_artifacts_enemy, e.artifacts)
	_fill_hand()

	for b in _weapons_box.get_children() + _runes_box.get_children():
		var kind: String = b.get_meta("kind")
		var id: String = b.get_meta("id")
		if kind == "weapon":
			var cost := state.weapon_cost(id)
			b.text = "%d" % state.weapon_damage(id)
			b.tooltip_text = Loc.t("%s: %d урона, %d выносл.\n%s") % [Loc.t(XPCalculator.WEAPONS[id].name), state.weapon_damage(id), cost, Loc.t(XPCalculator.WEAPONS[id].desc)]
			b.disabled = _busy or state.over or p.stamina < cost
		else:
			var rune: Dictionary = XPCalculator.RUNES[id]
			b.text = "%d✦" % rune.cost
			b.tooltip_text = Loc.t("%s (%d маны)\n%s") % [rune.name, rune.cost, rune.desc]
			b.disabled = _busy or state.over or p.mana < rune.cost
	_end_btn.disabled = _busy or state.over
	_update_hint()
	_apply_highlights()


func _fill_board(row: HBoxContainer, board: Array, side: String) -> void:
	for child in row.get_children():
		child.queue_free()
	if board.is_empty():
		var empty := Label.new()
		empty.text = Loc.t("Поле пусто") if side == "player" else ""
		empty.theme_type_variation = &"DimLabel"
		row.add_child(empty)
	for c in board:
		var t: PanelContainer = TOKEN_SCRIPT.new()
		row.add_child(t)
		t.setup(c, side)
		t.clicked.connect(_on_token_clicked)
		_tokens["%s:%d" % [side, c.uid]] = t


func _fill_artifacts(box: HBoxContainer, artifacts: Array) -> void:
	for child in box.get_children():
		child.queue_free()
	for a in artifacts:
		var ic := TextureRect.new()
		ic.texture = Palette.game_icon(a.get("icon", "gem-pendant"))
		ic.custom_minimum_size = Vector2(34, 34)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		ic.modulate = Color.from_string(a.get("art_color", "#7B68EE"), Palette.ACCENT).lightened(0.3)
		ic.tooltip_text = "%s\n%s" % [a.name, a.description]
		ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		box.add_child(ic)


func _fill_hand() -> void:
	_hide_preview()
	for child in _hand.get_children():
		child.queue_free()
	for i in state.player.hand.size():
		var card: Dictionary = state.player.hand[i]
		var cv := CARD_SCENE.instantiate()
		cv.card_scale = HAND_SCALE
		_hand.add_child(cv)
		var shown := card.duplicate()
		shown.crystal_cost = state.card_cost(state.player, card)
		cv.setup(shown, 0)
		var ok: bool = state.can_play(i).ok and not _busy
		cv.modulate = Color.WHITE if ok else Color(0.55, 0.55, 0.62)
		if _targeting.get("mode") == "card" and _targeting.get("index") == i:
			cv.modulate = Color(1.3, 1.25, 0.8)
		cv.clicked.connect(func(_id): _on_hand_card(i))
		cv.mouse_entered.connect(_show_preview.bind(shown, cv))
		cv.mouse_exited.connect(_hide_preview)


## Крупная копия карты над наведённой картой руки + полный текст в боковой колонке.
func _show_preview(card: Dictionary, source: Control) -> void:
	_hide_preview()
	var cv := CARD_SCENE.instantiate()
	cv.card_scale = PREVIEW_SCALE
	cv.hover_lift = false
	cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(cv)
	cv.setup(card, 0)
	var big: Vector2 = CardVisualSize * PREVIEW_SCALE
	var view := get_viewport_rect().size
	var pos := Vector2(source.global_position.x + source.size.x * 0.5 - big.x * 0.5, source.global_position.y - big.y - 14)
	pos.x = clampf(pos.x, 8, view.x - big.x - 8)
	pos.y = clampf(pos.y, 8, view.y - big.y - 8)
	cv.global_position = pos
	_hover_card = cv
	_preview.text = "%s\n%s" % [card.get("name", ""), card.get("description", "")]


func _hide_preview() -> void:
	if is_instance_valid(_hover_card):
		_hover_card.queue_free()
	_hover_card = null


func _update_hint() -> void:
	if state.over:
		_hint.text = ""
	elif _targeting.is_empty():
		_hint.text = Loc.t("Сыграй карту, ударь оружием или атакуй существом. ПКМ — отмена выбора.")
	else:
		_hint.text = Loc.t("Выбери цель… (ПКМ или Esc — отмена)")


func _apply_highlights() -> void:
	var targets := _current_targets()
	_enemy_panel.add_theme_stylebox_override("panel", Palette.glow_box(Color("#1A1020"), Palette.HP, Color(Palette.HP, 0.5), 12, 12)
		if _ref_listed(targets, {"side": "enemy", "kind": "hero", "uid": -1}) else Palette.box(Color("#1A1020", 0.9), Color(Palette.HP, 0.4), 1, 12, 12, 8))
	for key in _tokens:
		var t = _tokens[key]
		t.set_highlight(_ref_listed(targets, {"side": t.side, "kind": "creature", "uid": t.data.uid}))


func _current_targets() -> Array:
	if _targeting.is_empty():
		return []
	match _targeting.mode:
		"creature":
			return state.valid_attack_targets(state.enemy)
		"weapon":
			return state.valid_attack_targets(state.enemy, _targeting.id == "bow")
	var type: String = _targeting.get("type", "")
	var result: Array = []
	if type in ["enemy_any"]:
		result.append({"side": "enemy", "kind": "hero", "uid": -1})
	if type in ["enemy_any", "enemy_creature"]:
		for c in state.enemy.board:
			result.append({"side": "enemy", "kind": "creature", "uid": c.uid})
	if type == "friendly_creature":
		for c in state.player.board:
			result.append({"side": "player", "kind": "creature", "uid": c.uid})
	return result


static func _ref_listed(list: Array, ref: Dictionary) -> bool:
	for r in list:
		if CombatState._same_ref(r, ref):
			return true
	return false


# ---------------------------------------------------------------- Ввод

func _on_hand_card(i: int) -> void:
	if _busy or state.over:
		return
	var check := state.can_play(i)
	if not check.ok:
		_flash_hint(check.reason)
		Audio.play("error")
		return
	var card: Dictionary = state.player.hand[i]
	var tt := CombatState.target_type(card)
	if tt == "":
		_targeting = {}
		state.play_card(i)
		Audio.play("book_place")
		_after_action()
	else:
		_targeting = {"mode": "card", "index": i, "type": tt}
		Audio.play("select")
		_refresh()


func _on_action(kind: String, id: String) -> void:
	if _busy or state.over:
		return
	if kind == "rune" and not XPCalculator.RUNES[id].has("damage"):
		state.use_rune(id)
		Audio.play("spell")
		_after_action()
		return
	_targeting = {"mode": kind, "id": id, "type": "enemy_any"}
	Audio.play("draw" if kind == "weapon" else "select")
	_refresh()


func _on_token_clicked(token) -> void:
	if _busy or state.over:
		return
	var ref := {"side": token.side, "kind": "creature", "uid": token.data.uid}
	if not _targeting.is_empty():
		_use_target(ref)
	elif token.side == "player":
		if state.can_attack_with(token.data):
			_targeting = {"mode": "creature", "uid": token.data.uid}
			Audio.play("select")
			_refresh()
		else:
			_flash_hint(Loc.t("Это существо пока не может атаковать (атакуют со следующего хода)"))


func _on_enemy_hero_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT and not _targeting.is_empty():
		_use_target({"side": "enemy", "kind": "hero", "uid": -1})


func _use_target(ref: Dictionary) -> void:
	if not _ref_listed(_current_targets(), ref):
		_flash_hint(Loc.t("Неподходящая цель"))
		Audio.play("error")
		return
	var t := _targeting
	_targeting = {}
	match t.mode:
		"card":
			state.play_card(t.index, ref)
			Audio.play("spell")
		"weapon":
			state.weapon_attack(t.id, ref)
			Audio.play("slash")
		"rune":
			state.use_rune(t.id, ref)
			Audio.play("spell")
		"creature":
			state.creature_attack(t.uid, ref)
			Audio.play("hit")
	_after_action()


func _unhandled_input(event: InputEvent) -> void:
	var cancel: bool = event.is_action_pressed("ui_cancel") or (event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT)
	if cancel:
		get_viewport().set_input_as_handled()   # Esc не выходит из боя
		if not _targeting.is_empty():
			_targeting = {}
			_refresh()


func _after_action() -> void:
	_process_events(false)
	_refresh()
	if not state.pending_discover.is_empty():
		_show_discover()
	_check_end()


func _on_end_turn() -> void:
	if _busy or state.over:
		return
	_targeting = {}
	_busy = true
	_refresh()
	Audio.play("whoosh")
	state.end_turn()
	await _process_events(true)
	_busy = false
	_refresh()
	_check_end()


func _on_surrender() -> void:
	if state.over:
		return
	state.over = true
	state.winner = "enemy"
	state.player.hp = 0
	_check_end()


# ---------------------------------------------------------------- События и анимации

func _process_events(animate: bool) -> void:
	for ev in state.take_events():
		match ev.kind:
			"log":
				_log.append_text("%s\n" % ev.text)
			"damage":
				_float_at(ev.target, "-%d" % ev.amount, Palette.HP)
				Audio.play("hit_heavy" if ev.amount >= 5 else "hit", 0.1)
				_shake_target(ev.target)
				if animate:
					await get_tree().create_timer(EVENT_DELAY).timeout
			"heal":
				_float_at(ev.target, "+%d" % ev.amount, Palette.MINT)
			"block":
				_float_at(ev.target, Loc.t("блок"), Color("#6FB3FF"))
				Audio.play("block")
			"dodge":
				_float_at(ev.target, Loc.t("уклон!"), Palette.ENERGY)
			"shield":
				_float_at(ev.target, Loc.t("+%d щит") % ev.amount, Color("#6FB3FF"))
			"death":
				var key := "%s:%d" % [ev.side, ev.uid]
				if _tokens.has(key) and is_instance_valid(_tokens[key]):
					var t = _tokens[key]
					t.create_tween().tween_property(t, "modulate:a", 0.0, 0.3)
				Audio.play("destroy")
			"play":
				if ev.side == "enemy":
					_float_at({"side": "enemy", "kind": "hero"}, "«%s»" % ev.name, Palette.ENERGY)
					Audio.play("book_place")
					if animate:
						await get_tree().create_timer(EVENT_DELAY * 1.5).timeout
						_refresh()
			"steal":
				_float_at({"side": "player", "kind": "hero"}, Loc.t("украдено: %s") % ev.card, Palette.HP)
			"enemy_attack":
				_lunge_enemy()
				if animate:
					await get_tree().create_timer(0.15).timeout
			"turn":
				if ev.side == "player" and animate:
					Audio.play("notify")


func _target_node(ref: Dictionary) -> Control:
	if ref.get("kind") == "hero":
		return _enemy_panel if ref.side == "enemy" else _player_hp
	var key := "%s:%d" % [ref.get("side", ""), ref.get("uid", -1)]
	return _tokens.get(key) if _tokens.has(key) and is_instance_valid(_tokens[key]) else null


func _float_at(ref: Dictionary, text: String, color: Color) -> void:
	var node := _target_node(ref)
	if node == null:
		return
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", Palette.FONT_UI_BOLD)
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("outline_size", 6)
	l.top_level = true
	l.z_index = 60
	add_child(l)
	l.global_position = node.global_position + Vector2(node.size.x / 2.0 - 20 + randf_range(-12, 12), 6)
	var tw := l.create_tween().set_parallel()
	tw.tween_property(l, "global_position:y", l.global_position.y - 40, 0.9).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tw.tween_property(l, "modulate:a", 0.0, 0.6).set_delay(0.4)
	tw.chain().tween_callback(l.queue_free)


func _shake_target(ref: Dictionary) -> void:
	var node := _target_node(ref)
	if node == null or node is ProgressBar:
		return
	var tw := node.create_tween()
	for d in [6.0, -6.0, 3.0, 0.0]:
		tw.tween_property(node, "rotation", deg_to_rad(d), 0.04)


func _lunge_enemy() -> void:
	var tw := _enemy_icon.create_tween()
	tw.tween_property(_enemy_icon, "scale", Vector2(1.3, 1.3), 0.1)
	tw.tween_property(_enemy_icon, "scale", Vector2.ONE, 0.15)


func _flash_hint(text: String) -> void:
	_hint.text = text
	_hint.add_theme_color_override("font_color", Palette.HP)
	get_tree().create_timer(1.6).timeout.connect(func():
		if is_instance_valid(_hint):
			_hint.add_theme_color_override("font_color", Palette.ENERGY)
			_update_hint())


func _show_discover() -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.75)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	center.add_child(box)
	var title := Label.new()
	title.text = Loc.t("Выбери карту")
	title.theme_type_variation = &"TitleLabel"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	box.add_child(row)
	for i in state.pending_discover.size():
		var cv := CARD_SCENE.instantiate()
		row.add_child(cv)
		cv.setup(state.pending_discover[i], 0)
		cv.clicked.connect(func(_id):
			state.choose_discover(i)
			overlay.queue_free()
			Audio.play("card_flip")
			_refresh())


# ---------------------------------------------------------------- Конец боя

func _check_end() -> void:
	if not state.over or _finished:
		return
	_finished = true
	var won := state.winner == "player"
	var rewards := GameManager.apply_combat_result(enemy_data, won, context, state.player.hp)
	SaveSystem.save_all()
	var result := {"won": won, "enemy_id": enemy_data.get("id", ""), "context": context, "hp_left": state.player.hp}
	result.merge(rewards)
	Audio.play_jingle("levelup" if won else "drop")
	_show_result(result)


func _show_result(result: Dictionary) -> void:
	var overlay := Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(overlay)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	var color := Palette.MINT if result.won else Palette.HP
	panel.add_theme_stylebox_override("panel", Palette.glow_box(Color("#0B0B18", 0.97), color, Color(color, 0.35), 20, 16))
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 440
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	var title := Label.new()
	title.text = Loc.t("ПОБЕДА") if result.won else Loc.t("ПОРАЖЕНИЕ")
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_color_override("font_color", color)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(title)
	var text := RichTextLabel.new()
	text.bbcode_enabled = true
	text.fit_content = true
	text.add_theme_font_size_override("normal_font_size", 16)
	var lines: PackedStringArray = []
	if context == "training":
		lines.append(Loc.t("Тренировочный бой — без наград и потерь."))
	elif result.won:
		lines.append(Loc.t("[color=#00D4AA]+%d XP[/color]   [color=#F5C542]+%d золота[/color]") % [result.xp, result.gold])
		for id in result.cards:
			lines.append(Loc.t("Трофей: карта «%s»") % CardDatabase.get_card(id).get("name", id))
		lines.append(Loc.t("[color=#8C8CB0]Осталось HP: %d[/color]") % result.hp_left)
	else:
		lines.append(Loc.t("Ты падаешь без сил. Вылазка прервана — тебя доставят в лагерь, золото останется с тобой."))
	text.text = "[center]%s[/center]" % "\n".join(lines)
	box.add_child(text)
	var btn := Button.new()
	btn.text = Loc.t("Продолжить")
	btn.theme_type_variation = &"AccentButton"
	btn.pressed.connect(func():
		EventBus.combat_finished.emit(result)
		EventBus.back())
	box.add_child(btn)
	btn.grab_focus()
	overlay.modulate.a = 0.0
	overlay.create_tween().tween_property(overlay, "modulate:a", 1.0, 0.3)
