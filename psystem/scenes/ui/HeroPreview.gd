class_name HeroPreview
extends SubViewportContainer
## 3D-превью героя для интерфейса (снаряжение, лавка): подиум, свет, медленный поворот,
## вращение мышью. show_player() — текущий герой с экипировкой, try_item() — примерка предмета.

var rig: HeroRig
var _vp: SubViewport
var _pivot: Node3D
var _dragging := false
var _auto_spin := true
var _yaw := 0.4


func _init() -> void:
	stretch = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(260, 360)


func _ready() -> void:
	_vp = SubViewport.new()
	_vp.own_world_3d = true
	_vp.transparent_bg = true
	_vp.msaa_3d = Viewport.MSAA_2X
	add_child(_vp)
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#8F96B8")
	env.ambient_light_energy = 0.7
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_vp.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30, 25, 0)
	key.light_color = Color("#FFE8CC")
	key.light_energy = 1.3
	_vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 200, 0)
	rim.light_color = Color("#8FB4FF")
	rim.light_energy = 0.9
	_vp.add_child(rim)
	# Подиум
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.75
	cyl.bottom_radius = 0.82
	cyl.height = 0.12
	disc.mesh = cyl
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color("#2A2740")
	dm.metallic = 0.3
	dm.roughness = 0.5
	disc.material_override = dm
	disc.position.y = -0.06
	_vp.add_child(disc)
	var ring := MeshInstance3D.new()
	var tor := TorusMesh.new()
	tor.inner_radius = 0.78
	tor.outer_radius = 0.82
	ring.mesh = tor
	var rm := StandardMaterial3D.new()
	rm.albedo_color = Palette.ACCENT
	rm.emission_enabled = true
	rm.emission = Palette.ACCENT
	rm.emission_energy_multiplier = 1.5
	ring.material_override = rm
	ring.position.y = 0.0
	_vp.add_child(ring)
	_pivot = Node3D.new()
	_vp.add_child(_pivot)
	rig = HeroRig.new()
	_pivot.add_child(rig)
	var cam := Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0, 1.15, 4.4)
	_vp.add_child(cam)
	cam.look_at(Vector3(0, 0.95, 0))
	_pivot.rotation.y = _yaw


func show_player() -> void:
	if rig == null:
		await ready
	rig.apply_look(GameManager.player_data.get("look", Appearance.default_look()))
	rig.apply_equipment(GameManager.hero_outfit())
	rig.play("Sword_Idle" if GameManager.equipped("weapon") != "" else "Idle")


## Произвольный персонаж (NPC): внешность, экипировка, анимация.
func show_custom(look: Dictionary, equipment: Dictionary, anim_name: String = "Idle") -> void:
	if rig == null:
		await ready
	_auto_spin = false
	_yaw = 0.25
	_pivot.rotation.y = _yaw
	rig.apply_look(look)
	rig.apply_equipment(equipment)
	rig.play(anim_name)


## Примерить предмет поверх текущей экипировки (только визуально).
func try_item(item: Dictionary) -> void:
	if rig == null or item.is_empty():
		return
	var info := GameManager.hero_outfit()
	var visual: Dictionary = item.get("visual", {})
	for part in visual:
		info.outfit[part] = visual[part]
		info.variants[visual[part]] = int(item.get("variant", 0))
	match item.get("slot", ""):
		"weapon":
			info.weapon = item.get("model", "")
		"offhand":
			info.offhand = item.get("model", "")
	rig.apply_equipment(info)


func _process(delta: float) -> void:
	if _pivot and _auto_spin and not _dragging:
		_yaw += delta * 0.25
		_pivot.rotation.y = _yaw


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
		if event.pressed:
			_auto_spin = false
	elif event is InputEventMouseMotion and _dragging:
		_yaw += event.relative.x * 0.012
		_pivot.rotation.y = _yaw
