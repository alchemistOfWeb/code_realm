class_name CharacterRig
extends RefCounted
## Помощники для моделей Kenney: зацикливание анимаций и окраска материалов.

const LOOPED := ["idle", "walk", "sprint", "static"]


static func setup_loops(anim: AnimationPlayer) -> void:
	if anim == null:
		return
	for anim_name in LOOPED:
		if anim.has_animation(anim_name):
			anim.get_animation(anim_name).loop_mode = Animation.LOOP_LINEAR


## Умножить цвет всех материалов модели на tint (текстура сохраняется).
static func tint(root: Node, color: Color, emission: Color = Color.BLACK) -> void:
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for i in mesh.get_surface_count():
			var base := mesh.surface_get_material(i)
			if base is StandardMaterial3D:
				var mat: StandardMaterial3D = base.duplicate()
				mat.albedo_color = mat.albedo_color * color
				if emission != Color.BLACK:
					mat.emission_enabled = true
					mat.emission = emission
					mat.emission_energy_multiplier = 0.6
				mi.set_surface_override_material(i, mat)


## Первый меш внутри импортированной сцены (для MultiMesh).
static func first_mesh(scene: PackedScene) -> Mesh:
	var inst := scene.instantiate()
	var meshes := inst.find_children("*", "MeshInstance3D", true, false)
	var mesh: Mesh = meshes[0].mesh if not meshes.is_empty() else null
	inst.free()
	return mesh
