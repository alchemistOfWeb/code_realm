class_name CampScene
extends Node3D
## 3D-фон главного меню и создания героя: поляна у костра в стиле King's Bounty / WoW —
## сочная трава, деревья Stylized Nature, тёплый закатный свет, герой у костра.

const N := "res://assets/world/nature/"
const P := "res://assets/world/props/"

var hero: HeroRig
var camera: Camera3D
var _fire_light: OmniLight3D
var _t := 0.0
var _orbit := true
var _cam_target := Vector3(0, 1.0, 0)
var _cam_yaw := 0.35
var _cam_dist := 5.2
var _cam_height := 1.6
var _hero_yaw := 0.0


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_props()
	hero = HeroRig.new()
	add_child(hero)
	hero.rotation.y = _hero_yaw
	camera = Camera3D.new()
	camera.fov = 42
	add_child(camera)
	_update_camera()


## preset: "menu" — общий план с медленным облётом, "creator" — крупный план героя.
func set_view(preset: String) -> void:
	match preset:
		"creator":
			_orbit = false
			_cam_target = Vector3(-0.75, 1.0, 0)
			_cam_dist = 3.6
			_cam_height = 1.25
			_cam_yaw = -0.2
			var fill := OmniLight3D.new()
			fill.position = Vector3(0.4, 1.8, 2.2)
			fill.light_color = Color("#FFE6C8")
			fill.light_energy = 1.2
			fill.omni_range = 5.0
			add_child(fill)
		_:
			_orbit = true
			_cam_target = Vector3(0.6, 1.0, 0)
			_cam_dist = 5.6
			_cam_height = 1.7
	_update_camera()


func show_hero(look: Dictionary, equipment: Dictionary = {}) -> void:
	hero.visible = not look.is_empty()
	if look.is_empty():
		return
	hero.apply_look(look)
	if not equipment.is_empty():
		hero.apply_equipment(equipment)
	else:
		hero.apply_equipment({"outfit": HeroRig.DEFAULT_OUTFIT, "variants": {}, "weapon": "Sword_2", "offhand": ""})


func rotate_hero(delta_yaw: float) -> void:
	_hero_yaw += delta_yaw
	hero.rotation.y = _hero_yaw


func _process(delta: float) -> void:
	_t += delta
	if _fire_light:
		_fire_light.light_energy = 2.2 + sin(_t * 9.0) * 0.25 + sin(_t * 23.0) * 0.15
	if _orbit:
		_cam_yaw = 0.35 + sin(_t * 0.07) * 0.35
	_update_camera()


func _update_camera() -> void:
	if camera == null:
		return
	camera.position = _cam_target + Vector3(sin(_cam_yaw) * _cam_dist, _cam_height - _cam_target.y + 0.45, cos(_cam_yaw) * _cam_dist)
	camera.look_at(_cam_target, Vector3.UP)


func _build_environment() -> void:
	var parts := WorldStyle.environment("sunset")
	var we := WorldEnvironment.new()
	we.environment = parts[0]
	add_child(we)
	add_child(parts[1])


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(80, 80)
	plane.subdivide_width = 40
	plane.subdivide_depth = 40
	ground.mesh = plane
	ground.material_override = WorldStyle.grass_material()
	add_child(ground)


func _build_props() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	# Кольцо деревьев вокруг поляны
	var trees := ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "Pine_1", "Pine_2", "Pine_3", "TwistedTree_1"]
	for i in 26:
		var a := TAU * i / 26.0 + rng.randf_range(-0.1, 0.1)
		var r := rng.randf_range(9.0, 16.0)
		if a > 0.7 and a < 2.4:   # просвет в сторону камеры — вид вдаль
			r += 9.0
		_place(N + trees[rng.randi() % trees.size()] + ".gltf", Vector3(cos(a) * r, 0, sin(a) * r), rng.randf() * TAU, rng.randf_range(0.9, 1.4))
	# Кусты, трава, цветы, камни
	var small := ["Bush_Common", "Bush_Common_Flowers", "Grass_Common_Tall", "Grass_Wispy_Tall", "Flower_3_Group", "Flower_4_Group", "Fern_1", "Plant_1", "Clover_1"]
	for i in 110:
		var a := rng.randf() * TAU
		var r := rng.randf_range(2.6, 13.0)
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		if _in_view(pos):
			continue
		_place(N + small[rng.randi() % small.size()] + ".gltf", pos, rng.randf() * TAU, rng.randf_range(0.55, 0.9))
	for i in 7:
		var a := rng.randf() * TAU
		var r := rng.randf_range(4.5, 9.0)
		var pos := Vector3(cos(a) * r, 0, sin(a) * r)
		if _in_view(pos):
			continue
		_place(N + "Rock_Medium_%d.gltf" % (1 + i % 3), pos, rng.randf() * TAU, rng.randf_range(0.6, 1.2))
	# Лагерь: костёр, бочки, ящики, бревно
	var fire_pos := Vector3(1.6, 0, 1.2)
	WorldStyle.make_campfire(self, fire_pos)
	_fire_light = OmniLight3D.new()
	_fire_light.position = fire_pos + Vector3(0, 0.8, 0)
	_fire_light.light_color = Color("#FF9A3C")
	_fire_light.omni_range = 7.0
	_fire_light.shadow_enabled = false
	add_child(_fire_light)
	_place(P + "Barrel.gltf", Vector3(-1.8, 0, -1.4), 0.3, 1.0)
	_place(P + "Crate_Wooden.gltf", Vector3(-2.5, 0, -0.6), 0.8, 1.0)
	_place(P + "Bag.gltf", Vector3(-1.6, 0, -0.5), 1.2, 1.0)
	_place(P + "WeaponStand.gltf", Vector3(-1.2, 0, -2.4), 0.2, 1.0)
	_place(P + "Lantern_Wall.gltf", Vector3(2.8, 0, -1.2), 0.0, 1.0)
	_place(N + "DeadTree_3.gltf", Vector3(3.6, 0, -2.4), 1.0, 0.5)


## Сектор между героем и камерой (камера облетает со стороны +Z) — держим свободным.
func _in_view(pos: Vector3) -> bool:
	return pos.z > -1.5 and absf(pos.x - 0.8) < pos.z * 0.9 + 3.0 and pos.length() < 12.0


func _place(path: String, pos: Vector3, rot: float, scale_mul: float) -> Node3D:
	if not ResourceLoader.exists(path):
		return null
	var n: Node3D = load(path).instantiate()
	n.position = pos
	n.rotation.y = rot
	n.scale = Vector3.ONE * scale_mul
	add_child(n)
	return n
