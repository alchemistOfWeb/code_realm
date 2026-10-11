class_name HeroRig
extends Node3D
## Взрослый персонаж (герой и NPC): модели Quaternius на общем UE-скелете + анимации Universal Animation Library.
##
## Модель hero_<gender>.glb содержит все варианты частей: одежда Peasant/Ranger, причёски, расовые
## части (уши эльфа, клыки орка, рога тифлинга). Нужные части включаются видимостью.
## Раса задаёт масштаб скелета; голова компенсируется модификатором, чтобы не сплющивалась.

const MODELS := {"male": "res://assets/characters/hero_male.glb", "female": "res://assets/characters/hero_female.glb"}
const ANIMS := "res://assets/characters/ual_anims.glb"
const WEAPONS_DIR := "res://assets/weapons/"
const OUTFIT_TEX := {
	"peasant": ["res://assets/characters/textures/T_Peasant_BaseColor.jpg", "res://assets/characters/textures/T_Peasant_2_BaseColor.jpg"],
	"ranger": ["res://assets/characters/textures/T_Ranger_BaseColor.jpg", "res://assets/characters/textures/T_Ranger_3_BaseColor.jpg"],
}
## Слот экипировки → префикс имени меша после "Outfit_<Набор>_".
const SLOT_PREFIX := {"body": "Body", "arms": "Arms", "legs": "Legs", "feet": "Feet", "head": "Head_Hood", "shoulders": "Acc"}
const DEFAULT_OUTFIT := {"body": "peasant", "arms": "peasant", "legs": "peasant", "feet": "peasant", "head": "", "shoulders": ""}
const RACE_PARTS := ["Race_ElfEar", "Race_OrcTusk", "Race_Horn"]
## Положение оружия в ладони (подобрано по скриншотам): длина клинка вдоль +Y модели оружия.
## Поворот (градусы) и смещение оружия/щита относительно кости кисти.
const WEAPON_SCALE := 0.17
static var weapon_rot := Vector3(90, 0, 0)
static var weapon_offset := Vector3(0.02, 0.075, 0.0)
static var shield_rot := Vector3(0, -90, 0)
static var shield_offset := Vector3(-0.06, 0.02, 0.0)

static var _anim_lib: AnimationLibrary

var look: Dictionary = {}
var outfit: Dictionary = DEFAULT_OUTFIT.duplicate()
## Расцветка комплектов одежды: {"peasant": 0|1, "ranger": 0|1} (из экипировки), иначе look.outfit_variant.
var outfit_variants: Dictionary = {}
var anim: AnimationPlayer
var skeleton: Skeleton3D
var current_anim := ""

var _model: Node3D
var _gender := ""
var _meshes: Dictionary = {}          # имя меша → MeshInstance3D
var _materials: Array = []            # [{mi, surface, kind, mat}]
var _head: HeadScaler
var _weapon_mount: BoneAttachment3D
var _offhand_mount: BoneAttachment3D


## Компенсация масштаба головы после анимации (раса масштабирует весь скелет).
class HeadScaler extends SkeletonModifier3D:
	var bone := -1
	var mul := Vector3.ONE

	func _process_modification_with_delta(_delta: float) -> void:
		var sk := get_skeleton()
		if sk == null or bone < 0 or mul.is_equal_approx(Vector3.ONE):
			return
		sk.set_bone_pose_scale(bone, sk.get_bone_pose_scale(bone) * mul)


static func create(appearance: Dictionary, equipment: Dictionary = {}) -> HeroRig:
	var rig := HeroRig.new()
	rig.apply_look(appearance)
	if not equipment.is_empty():
		rig.apply_equipment(equipment)
	return rig


## Экипировка из GameManager.hero_outfit(): {outfit, variants, weapon, offhand}.
func apply_equipment(info: Dictionary) -> void:
	outfit_variants = info.get("variants", {})
	set_outfit(info.get("outfit", DEFAULT_OUTFIT))
	set_weapon(info.get("weapon", ""))
	set_offhand(info.get("offhand", ""))
	_apply_colors()


static func default_look() -> Dictionary:
	return Appearance.default_look()


static func animation_library() -> AnimationLibrary:
	if _anim_lib == null:
		var inst: Node = load(ANIMS).instantiate()
		var ap: AnimationPlayer = inst.find_child("AnimationPlayer", true, false)
		_anim_lib = ap.get_animation_library("")
		for anim_name in ["Idle", "Walk", "Jog_Fwd", "Sprint", "Idle_Talking", "Crouch_Idle", "Swim_Idle", "Sword_Idle", "Spell_Simple_Idle"]:
			if _anim_lib.has_animation(anim_name):
				_anim_lib.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR
		inst.free()
	return _anim_lib


# ---------------------------------------------------------------- Внешность

func apply_look(new_look: Dictionary) -> void:
	look = Appearance.default_look(new_look.get("gender", "male"))
	look.merge(new_look, true)
	if look.gender != _gender:
		_build_model(look.gender)
	var race := Appearance.race(look.race)
	_model.scale = race.scale
	_head.mul = race.head
	for part in RACE_PARTS:
		var on: bool = part in race.parts
		for side in ["_L", "_R"]:
			if _meshes.has(part + side):
				_meshes[part + side].visible = on
	_update_hair()
	_apply_colors()


func set_outfit(new_outfit: Dictionary) -> void:
	outfit = DEFAULT_OUTFIT.duplicate()
	outfit.merge(new_outfit, true)
	for mesh_name in _meshes:
		if not mesh_name.begins_with("Outfit_"):
			continue
		var parts: PackedStringArray = mesh_name.split("_", true, 2)   # Outfit, Peasant|Ranger, Rest
		var set_name := parts[1].to_lower()
		var visible_now := false
		for slot in SLOT_PREFIX:
			if parts[2].begins_with(SLOT_PREFIX[slot]):
				visible_now = outfit.get(slot, "") == set_name
				break
		_meshes[mesh_name].visible = visible_now
	_update_hair()


func _update_hair() -> void:
	var hooded: bool = outfit.get("head", "") != ""
	for mesh_name in _meshes:
		if mesh_name.begins_with("Hair_"):
			var on: bool = mesh_name == look.get("hair", "") and not hooded
			if mesh_name == "Hair_Beard":
				on = look.get("beard", false) or (look.get("race") == "dwarf" and look.get("gender") == "male")
			_meshes[mesh_name].visible = on


func _apply_colors() -> void:
	var skin := Appearance.skin_color(look)
	var skin_tint := Appearance.tint_for(skin, Appearance.SKIN_BASE)
	var hair_tint := Appearance.tint_for(Appearance.hair_color(look), Appearance.HAIR_BASE)
	var base_variant := clampi(int(look.get("outfit_variant", 0)), 0, Appearance.OUTFIT_VARIANTS - 1)
	for entry in _materials:
		var mat: StandardMaterial3D = entry.mat
		match entry.kind:
			"skin":
				mat.albedo_color = skin_tint
			"ear":
				mat.albedo_color = skin.darkened(0.08)
			"hair":
				mat.albedo_color = hair_tint
			"peasant", "ranger":
				var variant := clampi(int(outfit_variants.get(entry.kind, base_variant)), 0, Appearance.OUTFIT_VARIANTS - 1)
				mat.albedo_texture = load(OUTFIT_TEX[entry.kind][variant])


# ---------------------------------------------------------------- Построение

func _build_model(gender: String) -> void:
	if _model:
		_model.queue_free()
		remove_child(_model)
	_gender = gender
	_meshes.clear()
	_materials.clear()
	_model = load(MODELS[gender]).instantiate()
	add_child(_model)
	skeleton = _model.find_child("Skeleton3D", true, false)
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		_meshes[String(mi.name)] = mi
		_prepare_materials(mi)
	anim = _model.find_child("AnimationPlayer", true, false)
	if anim == null:
		anim = AnimationPlayer.new()
		anim.name = "AnimationPlayer"
		_model.add_child(anim)
	anim.root_node = anim.get_path_to(_model)
	anim.add_animation_library("ual", animation_library())
	_head = HeadScaler.new()
	_head.bone = skeleton.find_bone("Head")
	skeleton.add_child(_head)
	_weapon_mount = _mount("hand_r")
	_offhand_mount = _mount("hand_l")
	set_outfit(outfit)
	current_anim = ""
	play("Idle")


func _prepare_materials(mi: MeshInstance3D) -> void:
	var mesh: Mesh = mi.mesh
	for i in mesh.get_surface_count():
		var base := mesh.surface_get_material(i)
		if not base is StandardMaterial3D:
			continue
		var res_name := String(base.resource_name)
		var kind := ""
		if "Ear_Skin" in res_name:
			kind = "ear"
		elif "Regular" in res_name or "Superhero" in res_name:
			kind = "skin"
		elif "Hair" in res_name or "Eyebrow" in res_name:
			kind = "hair"
		elif "Peasant" in res_name:
			kind = "peasant"
		elif "Ranger" in res_name:
			kind = "ranger"
		if kind == "":
			continue
		var mat: StandardMaterial3D = base.duplicate()
		mi.set_surface_override_material(i, mat)
		_materials.append({"mi": mi, "surface": i, "kind": kind, "mat": mat})


func _mount(bone_name: String) -> BoneAttachment3D:
	var ba := BoneAttachment3D.new()
	ba.bone_name = bone_name
	skeleton.add_child(ba)
	return ba


# ---------------------------------------------------------------- Оружие

## model — имя файла в assets/weapons без расширения ("" — убрать).
func set_weapon(model: String) -> void:
	_attach(_weapon_mount, model, _xform(weapon_rot, weapon_offset))


func set_offhand(model: String) -> void:
	if model.begins_with("Shield"):
		_attach(_offhand_mount, model, _xform(shield_rot, shield_offset))
	else:
		_attach(_offhand_mount, model, _xform(weapon_rot, weapon_offset))


static func _xform(rot_deg: Vector3, offset: Vector3) -> Transform3D:
	return Transform3D(Basis.from_euler(rot_deg * (PI / 180.0)), offset)


func _attach(mount: BoneAttachment3D, model: String, xform: Transform3D) -> void:
	for c in mount.get_children():
		c.queue_free()
	if model == "" or not ResourceLoader.exists(WEAPONS_DIR + model + ".glb"):
		return
	var w: Node3D = load(WEAPONS_DIR + model + ".glb").instantiate()
	w.transform = xform.scaled_local(Vector3.ONE * WEAPON_SCALE)
	mount.add_child(w)


# ---------------------------------------------------------------- Анимации

func play(anim_name: String, blend: float = 0.18, speed: float = 1.0) -> void:
	if anim == null or current_anim == anim_name:
		return
	var key := "ual/" + anim_name
	if not anim.has_animation(key):
		return
	current_anim = anim_name
	anim.play(key, blend, speed)


## Проиграть один раз (атака, взаимодействие); возвращает длительность.
func play_once(anim_name: String, blend: float = 0.1, speed: float = 1.0) -> float:
	var key := "ual/" + anim_name
	if anim == null or not anim.has_animation(key):
		return 0.0
	current_anim = anim_name
	anim.stop()
	anim.play(key, blend, speed)
	return anim.get_animation(key).length / speed


func has_anim(anim_name: String) -> bool:
	return anim != null and anim.has_animation("ual/" + anim_name)


## Высота модели с учётом расы (для подписей над головой).
func height() -> float:
	return 1.85 * Appearance.race(look.get("race", "human")).scale.y
