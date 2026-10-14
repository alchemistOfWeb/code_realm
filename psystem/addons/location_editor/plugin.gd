@tool
extends EditorPlugin
## Редактор локаций в редакторе Godot: док «Локации» + кисти рельефа во вьюпорте 3D.
## Сцены локаций — res://editor_locations/<loc>.tscn (корень LocationEditRoot). Правки — data/location_edits.

const SCENES_DIR := "res://editor_locations/"
const BRUSHES := {
	"raise": ["Поднять", Color("#FFD24A")], "lower": ["Опустить", Color("#6FB3FF")],
	"flatten": ["Выровнять", Color("#FFB04A")], "smooth": ["Сгладить", Color("#9FD8FF")],
	"clear_veg": ["Убрать растительность", Color("#FF7A7A")], "restore_veg": ["Вернуть растительность", Color("#7FCB5A")],
}
const ADD := [["chest", "Сундук"], ["enemy", "Враг"], ["tree", "Дерево"], ["pine", "Ель"], ["dead_tree", "Сухое дерево"],
	["rock", "Камень"], ["bush", "Куст"]]

var _dock: Control
var _loc_select: OptionButton
var _new_select: OptionButton
var _enemy_select: OptionButton
var _tool_buttons := {}
var _tool := "select"
var _radius := 4.0
var _strength := 1.0
var _painting := false
var _paint_root: LocationEditRoot
var _before := {}
var _level := 0.0
var _last_hit := Vector3.INF
var _last_paint := 0


func _enter_tree() -> void:
	_dock = _build_dock()
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, _dock)
	set_process(true)


func _exit_tree() -> void:
	if _dock:
		remove_control_from_docks(_dock)
		_dock.queue_free()
		_dock = null


func _root() -> LocationEditRoot:
	return EditorInterface.get_edited_scene_root() as LocationEditRoot


# ---------------------------------------------------------------- Док

func _build_dock() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "Локации"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 4)
	scroll.add_child(box)

	_label(box, "Локация", true)
	_loc_select = OptionButton.new()
	box.add_child(_loc_select)
	_refresh_locations()
	_button(box, "Открыть сцену локации", _open_scene, "Открывает (или создаёт) res://editor_locations/<локация>.tscn")
	var row := HBoxContainer.new()
	box.add_child(row)
	_button(row, "Сохранить", func(): _with_root(func(r): r.save_edits()), "То же, что Ctrl+S: записать правки в data/location_edits/<локация>.json")
	_button(row, "Перестроить", func(): _with_root(func(r): r.rebuild()), "Перестроить мир по сохранённым правкам (растительность, постройки)")
	_button(box, "▶ Играть отсюда", _play_here, "Запустить игру: вылазка у выбранного объекта (или в центре экрана), без траты энергии")
	_button(box, "Сбросить правки", _confirm_reset, "Удалить все ручные правки локации — вернуть процедурную раскладку")

	_label(box, "Новая локация", true)
	_new_select = OptionButton.new()
	_new_select.tooltip_text = "Локации карты мира «в разработке»"
	box.add_child(_new_select)
	_refresh_new_locations()
	_button(box, "Создать по шаблону", _create_location, "4 района (ворота, чаща с островом, руины с сейфом, сердце с боссом) и пещера; враги — из локации близкого уровня. Дальше всё правится здесь")

	_label(box, "Добавить в центр экрана", true)
	var grid := GridContainer.new()
	grid.columns = 2
	box.add_child(grid)
	for a in ADD:
		_button(grid, a[1], _add_object.bind(a[0]), "")
	_enemy_select = OptionButton.new()
	_enemy_select.tooltip_text = "Тип врага: для новых врагов и для выбранных маркеров врагов"
	for e in CardDatabase.all_enemies():
		_enemy_select.add_item(e.get("name", e.id))
		_enemy_select.set_item_metadata(_enemy_select.item_count - 1, e.id)
	_enemy_select.item_selected.connect(_on_enemy_selected)
	box.add_child(_enemy_select)

	_label(box, "Кисти рельефа (ЛКМ во вьюпорте)", true)
	var tools := GridContainer.new()
	tools.columns = 2
	box.add_child(tools)
	_tool_button(tools, "select", "Выбор (без кисти)")
	for t in BRUSHES:
		_tool_button(tools, t, BRUSHES[t][0])
	_slider(box, "Радиус", 1.0, 16.0, _radius, func(v): _radius = v)
	_slider(box, "Сила", 0.2, 4.0, _strength, func(v): _strength = v)

	_label(box, "Как пользоваться", true)
	var help := Label.new()
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.custom_minimum_size.x = 200
	help.text = """• Объекты — узлы в группах «Районы», «Постройки», «Сундуки», «Враги»… Двигай гизмо (W), копируй Ctrl+D, удаляй Delete. Высота берётся с рельефа.
• Указатели, центры районов, входы в пещеры, острова и боссов можно только двигать.
• Центр района — от него идут дороги; башня, постройка, уступы, остров, холм пещеры выравнивают под собой рельеф.
• Кисть: выбери её и води по рельефу с зажатой ЛКМ. Выровнять — до высоты точки, где начал. Ctrl+Z отменяет мазок.
• Ctrl+S — сохранить правки; игра сразу их видит. Растительность и постройки обновляются кнопкой «Перестроить» (или сами после переноса построек).
• Первое сохранение закрепляет все объекты на местах — правка одного не перемешает остальные."""
	box.add_child(help)
	_select_tool("select")
	return scroll


func _label(parent: Control, text: String, bold: bool) -> void:
	var l := Label.new()
	l.text = text
	if bold:
		l.add_theme_color_override("font_color", Color("#B7A8FF"))
	parent.add_child(l)


func _button(parent: Control, text: String, cb: Callable, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.tooltip_text = tip
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _tool_button(parent: Control, id: String, text: String) -> void:
	var b := Button.new()
	b.text = text
	b.toggle_mode = true
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.pressed.connect(_select_tool.bind(id))
	parent.add_child(b)
	_tool_buttons[id] = b


func _slider(parent: Control, text: String, lo: float, hi: float, value: float, cb: Callable) -> void:
	var row := HBoxContainer.new()
	var l := Label.new()
	l.text = text
	l.custom_minimum_size.x = 56
	row.add_child(l)
	var s := HSlider.new()
	s.min_value = lo
	s.max_value = hi
	s.step = 0.1
	s.value = value
	s.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	s.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	s.value_changed.connect(cb)
	row.add_child(s)
	parent.add_child(row)


func _select_tool(id: String) -> void:
	_tool = id
	for t in _tool_buttons:
		_tool_buttons[t].set_pressed_no_signal(t == id)
	var root := _root()
	if root == null:
		return
	if id == "select":
		root.show_ring(Vector3.INF, 0, Color.WHITE)
	else:
		# Кисть работает, когда выбран узел сцены локации
		EditorInterface.get_selection().clear()
		EditorInterface.get_selection().add_node(root)


func _with_root(cb: Callable) -> void:
	var root := _root()
	if root == null:
		push_warning("Локации: открой сцену локации (кнопка «Открыть сцену локации»)")
		return
	cb.call(root)


# ---------------------------------------------------------------- Действия

func _open_scene() -> void:
	var loc_id: String = _loc_select.get_item_metadata(_loc_select.selected)
	var path := SCENES_DIR + loc_id + ".tscn"
	if not ResourceLoader.exists(path):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENES_DIR))
		var root := LocationEditRoot.new()
		root.name = "Локация_" + loc_id
		root.location_id = loc_id
		var ps := PackedScene.new()
		ps.pack(root)
		ResourceSaver.save(ps, path)
		root.free()
		EditorInterface.get_resource_filesystem().scan()
	EditorInterface.open_scene_from_path(path)


func _refresh_locations(select_id: String = "") -> void:
	_loc_select.clear()
	for loc_id in WorldData.implemented_locations():
		_loc_select.add_item("%s (%s)" % [WorldData.location_info(loc_id).get("name", loc_id), loc_id])
		_loc_select.set_item_metadata(_loc_select.item_count - 1, loc_id)
		if loc_id == select_id:
			_loc_select.select(_loc_select.item_count - 1)


func _refresh_new_locations() -> void:
	_new_select.clear()
	for l in LocationDataFile.wip_locations():
		_new_select.add_item("%s · ур. %d · %s" % [l.get("name", l.id), int(l.get("level", 1)), l.get("biome", "")])
		_new_select.set_item_metadata(_new_select.item_count - 1, l.id)


func _create_location() -> void:
	if _new_select.item_count == 0:
		return
	var loc_id: String = _new_select.get_item_metadata(_new_select.selected)
	var err := LocationDataFile.create_from_template(loc_id)
	if err != "":
		push_error("Локации: " + err)
		return
	print("Локации: создана %s — data/locations.json, статус на карте мира «open»" % loc_id)
	_refresh_locations(loc_id)
	_refresh_new_locations()
	_open_scene()


func _center_hit(root: LocationEditRoot) -> Vector3:
	var vp := EditorInterface.get_editor_viewport_3d(0)
	var cam := vp.get_camera_3d()
	var c := vp.get_visible_rect().size * 0.5
	var hit := root.ray_hit(cam.project_ray_origin(c), cam.project_ray_normal(c))
	if hit == Vector3.INF:
		var s: Vector2i = root.data.start
		hit = Vector3(s.x + 0.5, 0, s.y + 0.5)
	return hit


func _add_object(kind: String) -> void:
	var root := _root()
	if root == null or root.data.is_empty():
		push_warning("Локации: открой сцену локации")
		return
	var hit := _center_hit(root)
	var enemy_id := ""
	if kind == "enemy" and _enemy_select.item_count > 0:
		enemy_id = _enemy_select.get_item_metadata(_enemy_select.selected)
	var m := root.new_marker(kind, Vector2(hit.x, hit.z), enemy_id)
	var group := root._group(kind)
	var ur := get_undo_redo()
	ur.create_action("Добавить: " + m.name)
	ur.add_do_method(group, "add_child", m, true)
	ur.add_do_method(m, "set_owner", root)
	ur.add_do_method(root, "decorate", m)
	ur.add_do_reference(m)
	ur.add_undo_method(group, "remove_child", m)
	ur.commit_action()
	EditorInterface.get_selection().clear()
	EditorInterface.get_selection().add_node(m)
	_select_tool("select")


func _on_enemy_selected(i: int) -> void:
	var root := _root()
	if root == null:
		return
	var id: String = _enemy_select.get_item_metadata(i)
	var ur := get_undo_redo()
	var any := false
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is LocationMarker and n.kind == "enemy":
			if not any:
				ur.create_action("Сменить врага")
				any = true
			ur.add_do_property(n, "enemy_id", id)
			ur.add_undo_property(n, "enemy_id", n.enemy_id)
			ur.add_do_method(root, "decorate", n)
			ur.add_undo_method(root, "decorate", n)
	if any:
		ur.commit_action()


func _confirm_reset() -> void:
	var root := _root()
	if root == null:
		push_warning("Локации: открой сцену локации")
		return
	var dialog := ConfirmationDialog.new()
	dialog.title = "Сбросить правки?"
	dialog.dialog_text = "Все ручные правки локации «%s» (объекты, рельеф, растительность) будут удалены." % root.location_id
	dialog.confirmed.connect(func():
		root.reset_edits()
		dialog.queue_free())
	dialog.canceled.connect(dialog.queue_free)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()


func _play_here() -> void:
	var root := _root()
	if root == null or root.data.is_empty():
		push_warning("Локации: открой сцену локации")
		return
	root.save_edits()
	var p := _center_hit(root)
	for n in EditorInterface.get_selection().get_selected_nodes():
		if n is LocationMarker:
			p = n.position + Vector3(1.5, 0, 1.5)
			break
	var key := "editor/run/main_run_args"
	var old: String = ProjectSettings.get_setting(key, "")
	ProjectSettings.set_setting(key, "-- --screen=sortie:%s --spawn=%d,%d" % [root.location_id, int(p.x), int(p.z)])
	EditorInterface.play_main_scene()
	await get_tree().create_timer(3.0).timeout
	ProjectSettings.set_setting(key, old)


# ---------------------------------------------------------------- Кисти во вьюпорте

func _handles(object: Object) -> bool:
	return object is Node and _root() != null


func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	var root := _root()
	if root == null or not BRUSHES.has(_tool) or root.data.is_empty():
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		_last_hit = root.ray_hit(camera.project_ray_origin(mm.position), camera.project_ray_normal(mm.position))
		root.show_ring(_last_hit, _radius, BRUSHES[_tool][1])
		return EditorPlugin.AFTER_GUI_INPUT_STOP if _painting else EditorPlugin.AFTER_GUI_INPUT_PASS
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		var mb := event as InputEventMouseButton
		if mb.pressed:
			_last_hit = root.ray_hit(camera.project_ray_origin(mb.position), camera.project_ray_normal(mb.position))
			if _last_hit == Vector3.INF:
				return EditorPlugin.AFTER_GUI_INPUT_PASS
			_painting = true
			_paint_root = root
			_before = root.terrain_snapshot()
			_level = _last_hit.y
			_last_paint = Time.get_ticks_msec()
			root.apply_brush(_tool, Vector2(_last_hit.x, _last_hit.z), _radius, _strength, 0.05, _level)
			return EditorPlugin.AFTER_GUI_INPUT_STOP
		elif _painting:
			_finish_stroke()
			return EditorPlugin.AFTER_GUI_INPUT_STOP
	return EditorPlugin.AFTER_GUI_INPUT_PASS


func _process(_delta: float) -> void:
	if not _painting or not is_instance_valid(_paint_root):
		return
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_stroke()
		return
	var now := Time.get_ticks_msec()
	var dt := minf((now - _last_paint) / 1000.0, 0.1)
	_last_paint = now
	if _last_hit != Vector3.INF and dt > 0.0:
		_paint_root.apply_brush(_tool, Vector2(_last_hit.x, _last_hit.z), _radius, _strength, dt, _level)


func _finish_stroke() -> void:
	_painting = false
	if not is_instance_valid(_paint_root):
		return
	_paint_root.end_stroke()
	var after := _paint_root.terrain_snapshot()
	var ur := get_undo_redo()
	ur.create_action("Кисть: " + BRUSHES.get(_tool, ["?"])[0], UndoRedo.MERGE_DISABLE, _paint_root)
	ur.add_do_method(_paint_root, "restore_terrain", after)
	ur.add_undo_method(_paint_root, "restore_terrain", _before)
	ur.commit_action(false)


## Ctrl+S (и запуск игры из редактора) — записать правки открытой локации.
func _apply_changes() -> void:
	var root := _root()
	if root != null and not root.data.is_empty():
		root.save_edits()
