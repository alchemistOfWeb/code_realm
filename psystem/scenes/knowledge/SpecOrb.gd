extends Control
## Светящаяся сфера специализации на главном экране (WorldTree).

signal pressed()

var spec_id: String = ""
## Базовый масштаб (WorldTree уменьшает сферы в маленьком окне)
var base_scale: float = 1.0:
	set(value):
		base_scale = value
		scale = Vector2.ONE * value

@onready var orb: ColorRect = $Orb
@onready var icon_rect: TextureRect = $Icon
@onready var name_label: Label = $NameLabel
@onready var count_label: Label = $CountLabel

var _mat: ShaderMaterial
var _hover_tween: Tween


func _ready() -> void:
	_mat = orb.material
	mouse_entered.connect(_set_hover.bind(true))
	mouse_exited.connect(_set_hover.bind(false))


## Сфера специализации из ContentParser.
func setup(sid: String) -> void:
	spec_id = sid
	var meta := ContentParser.get_spec_meta(sid)
	name_label.text = meta.get("name", sid)
	tooltip_text = "%s\n\n%s" % [meta.get("name", sid), meta.get("description", "")]
	var color := ContentParser.get_spec_color(sid)
	_mat.set_shader_parameter("orb_color", color)
	_mat.set_shader_parameter("seed", float(sid.hash() % 1000) / 100.0)
	if ResourceLoader.exists(meta.get("icon", "")):
		icon_rect.texture = load(meta.icon)
	refresh()


## Произвольная сфера (например, центральное «Ядро знаний»).
func setup_custom(title: String, color: Color, icon_name: String, tooltip: String) -> void:
	name_label.text = title
	tooltip_text = tooltip
	_mat.set_shader_parameter("orb_color", color)
	_mat.set_shader_parameter("seed", 4.2)
	icon_rect.texture = Palette.icon(icon_name)


func set_progress(learned: int, total: int, count_text: String = "") -> void:
	var ratio := float(learned) / maxf(total, 1)
	_mat.set_shader_parameter("progress", ratio)
	count_label.text = count_text if count_text != "" else "%d / %d · %d%%" % [learned, total, roundi(ratio * 100)]
	count_label.add_theme_color_override("font_color", Palette.MINT if learned > 0 else Palette.TEXT_DIM)


func refresh() -> void:
	if spec_id != "":
		set_progress(GameManager.count_learned(spec_id), ContentParser.count_nodes(spec_id))


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if Rect2(Vector2.ZERO, size).has_point(event.position):
			Audio.play("open")
			pressed.emit()
			accept_event()


func _set_hover(on: bool) -> void:
	if on:
		Audio.play_hover()
	if _hover_tween:
		_hover_tween.kill()
	_hover_tween = create_tween().set_parallel()
	_hover_tween.tween_method(func(v: float): _mat.set_shader_parameter("hover", v),
		_mat.get_shader_parameter("hover"), 1.0 if on else 0.0, 0.25)
	_hover_tween.tween_property(self, "scale", Vector2.ONE * base_scale * (1.07 if on else 1.0), 0.25) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
