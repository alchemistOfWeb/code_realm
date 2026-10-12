class_name MonsterRig
extends Node3D
## Монстр Quaternius: модель масштабируется до нужного роста, анимации сопоставлены общим ролям
## (idle / move / attack / death / hit). Imp и Puglin — на UE-скелете, используют анимации UAL.

const DIR := "res://assets/monsters/"
## height — рост в метрах, fly — высота полёта над землёй, yaw — поворот модели (лицом к +Z).
const MODELS := {
	"Bat": {"height": 0.75, "fly": 1.1, "anims": {"idle": "Flying", "move": "Flying", "attack": "Attack", "death": "Death", "hit": "Hit"}},
	"Dragon": {"height": 2.3, "fly": 0.4, "anims": {"idle": "Flying", "move": "Flying", "attack": "Attack", "death": "Death", "hit": "Hit"}},
	"Skeleton": {"height": 1.75, "anims": {"idle": "Idle", "move": "Running", "attack": "Attack", "death": "Death"}},
	"Slime": {"height": 0.75, "yaw": -90, "anims": {"idle": "Idle", "move": "Walk", "attack": "Attack", "death": "Death"}},
	"Frog": {"height": 0.6, "anims": {"idle": "Idle", "move": "Jump", "attack": "Attack", "death": "Death"}},
	"Rat": {"height": 0.5, "anims": {"idle": "Idle", "move": "Run", "attack": "Attack", "death": "Death"}},
	"Snake": {"height": 0.8, "anims": {"idle": "Idle", "move": "Walk", "attack": "Attack"}},
	"Spider": {"height": 0.75, "anims": {"idle": "Idle", "move": "Walk", "attack": "Attack", "death": "Death"}},
	"Wasp": {"height": 0.7, "fly": 0.9, "yaw": -90, "anims": {"idle": "Flying", "move": "Flying", "attack": "Attack", "death": "Death"}},
	"Imp": {"height": 1.35, "ual": true, "anims": {"idle": "ual/Idle", "move": "ual/Jog_Fwd", "attack": "ual/Punch_Cross", "death": "ual/Death01", "hit": "ual/Hit_Chest"}},
	"Puglin": {"height": 1.1, "ual": true, "anims": {"idle": "ual/Idle", "move": "ual/Walk", "attack": "ual/Sword_Attack", "death": "ual/Death01", "hit": "ual/Hit_Chest"}},
}

var model_name := ""
var cfg: Dictionary = {}
var anim: AnimationPlayer
var _model: Node3D
var _current := ""
## Библиотеки UAL для монстров без позиционных треков (общая на все UAL-модели).
static var _ual_rot_only: AnimationLibrary


static func create(model: String, size_mul: float = 1.0, tint: Color = Color.WHITE) -> MonsterRig:
	var r := MonsterRig.new()
	r.build(model, size_mul, tint)
	return r


func build(model: String, size_mul: float, tint: Color) -> void:
	model_name = model if MODELS.has(model) else "Slime"
	cfg = MODELS[model_name]
	_model = load(DIR + model_name + ".glb").instantiate()
	add_child(_model)
	_model.rotation.y = deg_to_rad(cfg.get("yaw", 0.0))
	var h := _rest_height(_model)
	var s: float = cfg.height * size_mul / maxf(h, 0.01)
	_model.scale = Vector3.ONE * s
	_model.position.y = cfg.get("fly", 0.0)
	anim = _model.find_child("AnimationPlayer", true, false)
	if cfg.get("ual", false):
		if anim == null:
			anim = AnimationPlayer.new()
			_model.add_child(anim)
			anim.root_node = anim.get_path_to(_model)
		anim.add_animation_library("ual", _rotation_only_library())
	if anim:
		for role in ["idle", "move"]:
			var a: String = cfg.anims.get(role, "")
			if anim.has_animation(a):
				anim.get_animation(a).loop_mode = Animation.LOOP_LINEAR
	if tint != Color.WHITE:
		CharacterRig.tint(_model, tint)
	play("idle")


func height() -> float:
	return cfg.get("height", 1.0) * scale.y + cfg.get("fly", 0.0)


func play(role: String, blend: float = 0.15) -> void:
	if anim == null or _current == role:
		return
	var a: String = cfg.anims.get(role, cfg.anims.idle)
	if not anim.has_animation(a):
		return
	_current = role
	anim.play(a, blend)


func play_once(role: String) -> float:
	if anim == null:
		return 0.0
	var a: String = cfg.anims.get(role, "")
	if not anim.has_animation(a):
		return 0.0
	_current = role
	anim.stop()
	anim.play(a, 0.08)
	return anim.get_animation(a).length


## Анимации UAL сняты с манекена человеческого роста: их позиционные треки ставят таз на его высоту,
## и низкие монстры (Puglin — гоблин) парят над землёй. Оставляем только повороты костей —
## кости остаются на своих местах из позы покоя, ноги стоят на земле.
static func _rotation_only_library() -> AnimationLibrary:
	if _ual_rot_only:
		return _ual_rot_only
	var src := HeroRig.animation_library()
	_ual_rot_only = AnimationLibrary.new()
	for name in src.get_animation_list():
		var a: Animation = src.get_animation(name).duplicate(true)
		for t in range(a.get_track_count() - 1, -1, -1):
			if a.track_get_type(t) == Animation.TYPE_POSITION_3D:
				a.remove_track(t)
		_ual_rot_only.add_animation(name, a)
	return _ual_rot_only


## Рост модели в позе покоя (по AABB мешей).
static func _rest_height(root: Node3D) -> float:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (root.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb() if root.is_inside_tree() else _local_xform(root, mi) * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box.size.y if not first else 1.0


static func _local_xform(root: Node3D, n: Node3D) -> Transform3D:
	var t := Transform3D.IDENTITY
	var cur: Node = n
	while cur != null and cur != root:
		if cur is Node3D:
			t = (cur as Node3D).transform * t
		cur = cur.get_parent()
	return t
