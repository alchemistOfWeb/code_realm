extends Node3D
## Dev-просмотрщик моделей: печатает дерево узлов и анимации, делает скриншот.
## Godot --path . res://tools/ModelViewer.tscn -- --model=res://assets/monsters/Bat.glb [--anim=Idle] [--t=0.4]
##   [--ual] (подключить библиотеку UAL) [--monster=Puglin [--role=move|idle|attack]] [--hero=male|female] [--race=elf] [--yaw=30] [--dist=3] [--h=1] --shot=C:/tmp/x.png

func _ready() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	var model: Node3D
	if args.has("monster"):
		# Монстр как в вылазке (MonsterRig) + плоскость земли — проверить, что ноги на земле
		var mr := MonsterRig.create(args.monster)
		add_child(mr)
		mr.play(args.get("role", "move"))
		var ground := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(4, 4)
		ground.mesh = pm
		var gm := StandardMaterial3D.new()
		gm.albedo_color = Color(0.3, 0.5, 0.3)
		ground.material_override = gm
		add_child(ground)
		model = mr
	elif args.has("hero"):
		var look := HeroRig.default_look()
		look.gender = args.hero
		for key in ["race", "hair", "skin", "hair_color", "outfit_variant"]:
			if args.has(key):
				look[key] = args[key].to_int() if args[key].is_valid_int() else args[key]
		for key in ["wrot", "woff", "srot", "soff"]:
			if args.has(key):
				var v: PackedFloat64Array = args[key].split_floats(",")
				var vec := Vector3(v[0], v[1], v[2])
				match key:
					"wrot": HeroRig.weapon_rot = vec
					"woff": HeroRig.weapon_offset = vec
					"srot": HeroRig.shield_rot = vec
					"soff": HeroRig.shield_offset = vec
		var rig := HeroRig.new()
		add_child(rig)
		rig.apply_look(look)
		if args.has("weapon"):
			rig.set_weapon(args.weapon)
		if args.has("offhand"):
			rig.set_offhand(args.offhand)
		model = rig
		if args.has("anim"):
			rig.play(args.anim)
	else:
		model = load(args.get("model", "res://assets/characters/hero_male.glb")).instantiate()
		add_child(model)
		if args.has("scale"):
			model.scale = Vector3.ONE * args.scale.to_float()
	_print_tree(model, 0)
	var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	if ap and args.has("ual") and not args.has("hero"):
		ap.add_animation_library("ual", load(HeroRig.ANIMS).instantiate().find_child("AnimationPlayer", true, false).get_animation_library(""))
	if ap:
		print("anims: ", ap.get_animation_list())
		if args.has("anim") and not args.has("hero"):
			ap.play(args.anim)
	var aabb := _aabb(model)
	print("aabb: ", aabb)
	var yaw: float = deg_to_rad(String(args.get("yaw", "25")).to_float())
	var dist: float = String(args.get("dist", "3.2")).to_float()
	var target := Vector3(0, String(args.get("h", "0.95")).to_float(), 0)
	var cam := Camera3D.new()
	cam.fov = 40
	add_child(cam)
	cam.position = target + Vector3(sin(yaw), 0.25, cos(yaw)) * dist
	cam.look_at(target)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, 30, 0)
	light.shadow_enabled = true
	add_child(light)
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(0.32, 0.38, 0.48)
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = 0.55
	env.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(env)
	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(6, 6)
	floor_mesh.mesh = plane
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.35, 0.42, 0.3)
	floor_mesh.material_override = fm
	add_child(floor_mesh)
	if ap and args.has("anim"):
		await get_tree().process_frame
		ap.seek(args.get("t", "0.4").to_float(), true)
		ap.pause()
	if args.has("hero"):
		await get_tree().process_frame
		print("current: ", ap.current_animation, " playing=", ap.is_playing())
		for ba in model.find_children("*", "BoneAttachment3D", true, false):
			print("mount ", ba.bone_name, " ", ba.global_position, " children=", ba.get_child_count())
			for mi in ba.find_children("*", "MeshInstance3D", true, false):
				print("   mesh ", mi.name, " visible=", mi.is_visible_in_tree(), " aabb=", mi.global_transform * mi.get_aabb())
	if not args.has("shot"):
		get_tree().quit()
		return
	await get_tree().create_timer(0.6).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(args.shot)
	get_tree().quit()


func _print_tree(n: Node, depth: int) -> void:
	if depth > 5:
		return
	var extra := ""
	if n is MeshInstance3D and n.mesh:
		var mats: PackedStringArray = []
		for i in n.mesh.get_surface_count():
			var m: Material = n.mesh.surface_get_material(i)
			mats.append(m.resource_name if m else "-")
		extra = " mats=" + ",".join(mats)
	elif n is Skeleton3D:
		extra = " bones=%d" % n.get_bone_count()
	print("  ".repeat(depth), n.name, " <", n.get_class(), ">", extra)
	for c in n.get_children():
		_print_tree(c, depth + 1)


func _aabb(root: Node) -> AABB:
	var box := AABB()
	var first := true
	for mi in root.find_children("*", "MeshInstance3D", true, false):
		if not mi.visible:
			continue
		var b: AABB = mi.global_transform * mi.get_aabb()
		box = b if first else box.merge(b)
		first = false
	return box
