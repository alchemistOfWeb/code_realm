class_name LevelBuilder
extends RefCounted
## Построение 3D-уровня вылазки по данным генератора (OutdoorGenerator / DungeonGenerator).
## Поверхность: единый рельеф локации (крутые склоны вместо стен), пропасти и реки с обрывами,
## каменные глыбы, растительность и руины через MultiMesh. Подземелья: плитка Kenney (подземелье, гробница) или скалы (пещера).

const N := "res://assets/world/nature/"
const P := "res://assets/world/props/"
const V := "res://assets/world/village/"
const D := "res://assets/models/dungeon/"
## Слои коллизии: 1 — мир (игрок ходит), 3 (значение 4) — препятствия для камеры.
const WALL_LAYER := 1 | 4
const MARGIN := 34
## Во сколько раз вытянуть стены Kenney по высоте под взрослых персонажей.
const WALL_HEIGHT := 2.3

static var _scenes: Dictionary = {}


static func scene(path: String) -> PackedScene:
	if not _scenes.has(path):
		_scenes[path] = load(path) if ResourceLoader.exists(path) else null
	return _scenes[path]


## Возвращает {"astar", "fall_y", "spawn_y"}.
static func build(root: Node3D, data: Dictionary, sky: String) -> Dictionary:
	if data.get("underground", false):
		return _build_underground(root, data)
	return _build_outdoor(root, data, sky)


# ================================================================ Поверхность

static func _build_outdoor(root: Node3D, data: Dictionary, sky: String) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(data.get("location_id", "x"))) % 100003
	var w: int = data.w
	var h: int = data.h
	var grid: PackedByteArray = data.grid
	var env := WorldStyle.environment(sky)
	var we := WorldEnvironment.new()
	we.environment = env[0]
	root.add_child(we)
	root.add_child(env[1])

	# --- Рельеф из генератора: расширенная сетка, высоты вершин
	var ext: Dictionary = data.ext
	var ew: int = ext.ew
	var eh: int = ext.eh
	var eg: PackedByteArray = ext.grid
	var terrain: Dictionary = data.terrain
	var hv: PackedFloat32Array = terrain.hv
	var vw := ew + 1

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Склоны — отдельно для камеры (слой 4): она не уходит внутрь холма, а ровная земля ей не мешает
	var cam_faces := PackedVector3Array()
	for ez in eh:
		for ex in ew:
			if eg[ez * ew + ex] == OutdoorGenerator.CHASM:
				continue
			var x0 := ex - MARGIN
			var z0 := ez - MARGIN
			var q0 := OutdoorGenerator.corner_pos(terrain, x0, z0)
			var q1 := OutdoorGenerator.corner_pos(terrain, x0 + 1, z0)
			var q2 := OutdoorGenerator.corner_pos(terrain, x0 + 1, z0 + 1)
			var q3 := OutdoorGenerator.corner_pos(terrain, x0, z0 + 1)
			var p0 := Vector3(q0.x, hv[ez * vw + ex], q0.y)
			var p1 := Vector3(q1.x, hv[ez * vw + ex + 1], q1.y)
			var p2 := Vector3(q2.x, hv[(ez + 1) * vw + ex + 1], q2.y)
			var p3 := Vector3(q3.x, hv[(ez + 1) * vw + ex], q3.y)
			for p in [p0, p1, p2, p0, p2, p3]:
				st.set_uv(Vector2(p.x, p.z))
				st.add_vertex(p)
			var lo := minf(minf(p0.y, p1.y), minf(p2.y, p3.y))
			var hi := maxf(maxf(p0.y, p1.y), maxf(p2.y, p3.y))
			if hi - lo > 1.2:
				cam_faces.append_array(PackedVector3Array([p0, p1, p2, p0, p2, p3]))
	st.index()
	st.generate_normals()
	var ground_mesh := st.commit()
	var mat := WorldStyle.ground_material(_biome_of(data.kind))
	var mask := Image.create(ew, eh, false, Image.FORMAT_L8)
	for ez in eh:
		for ex in ew:
			mask.set_pixel(ex, ez, Color.WHITE if eg[ez * ew + ex] == OutdoorGenerator.PATH else Color.BLACK)
	mask.resize(ew * 4, eh * 4, Image.INTERPOLATE_CUBIC)
	mat.set_shader_parameter("use_path", true)
	mat.set_shader_parameter("path_tex", ImageTexture.create_from_image(mask))
	mat.set_shader_parameter("path_rect", Vector4(-MARGIN, -MARGIN, ew, eh))
	var gmi := MeshInstance3D.new()
	gmi.mesh = ground_mesh
	gmi.material_override = mat
	gmi.name = "Ground"
	root.add_child(gmi)
	# Невидимых стен нет: крутые склоны (> 50°) физически не дают подняться — герой соскальзывает
	var ground_body := StaticBody3D.new()
	ground_body.collision_layer = 1
	var gcs := CollisionShape3D.new()
	gcs.shape = ground_mesh.create_trimesh_shape()
	ground_body.add_child(gcs)
	root.add_child(ground_body)
	if not cam_faces.is_empty():
		var cam_body := StaticBody3D.new()
		cam_body.collision_layer = 4
		cam_body.collision_mask = 0
		var ccs := CollisionShape3D.new()
		var cshape := ConcavePolygonShape3D.new()
		cshape.set_faces(cam_faces)
		ccs.shape = cshape
		cam_body.add_child(ccs)
		root.add_child(cam_body)

	# --- Пропасти и реки: стены по всему контуру, дно / вода
	for ch in data.chasms:
		_build_chasm(root, data, ch, rng)

	# --- Поиск пути: проходимые клетки без крутых участков (стены плато, края)
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	for y in h:
		for x in w:
			var v := grid[y * w + x]
			if v == OutdoorGenerator.BLOCK or v == OutdoorGenerator.CHASM:
				astar.set_point_solid(Vector2i(x, y), true)
				continue
			var ex := x + MARGIN
			var ez := y + MARGIN
			var a := hv[ez * vw + ex]
			var b := hv[ez * vw + ex + 1]
			var c := hv[(ez + 1) * vw + ex + 1]
			var d := hv[(ez + 1) * vw + ex]
			if maxf(maxf(a, b), maxf(c, d)) - minf(minf(a, b), minf(c, d)) > 0.9:
				astar.set_point_solid(Vector2i(x, y), true)

	_rock_formations(root, data, rng)
	_vegetation(root, data, rng)
	return {"astar": astar, "fall_y": -1000.0}


## Пропасть или река: скальные стены по всему контуру (от поверхности до дна, темнеют книзу, без тумана —
## чтобы не просвечивал цвет неба), тёмное дно или вода, дымка.
static func _build_chasm(root: Node3D, data: Dictionary, ch: Dictionary, rng: RandomNumberGenerator) -> void:
	var rect: Rect2i = ch.rect
	var water: bool = ch.water
	var level: float = ch.level
	var depth := 3.0 if water else 22.0
	var top := Color("#6E655A") if not water else Color("#5A5E52")
	var terrain: Dictionary = data.terrain
	var grid: PackedByteArray = data.grid
	var w: int = data.w
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var jit := {}
	var jfn := func(p: Vector2) -> float:
		var k := Vector2i(roundi(p.x * 2), roundi(p.y * 2))
		if not jit.has(k):
			jit[k] = rng.randf_range(-0.25, 0.25)
		return jit[k]
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			for o in [Vector2i(-1, 0), Vector2i(1, 0), Vector2i(0, -1), Vector2i(0, 1)]:
				var n: Vector2i = Vector2i(x, y) + o
				var outside: bool = n.x < 0 or n.y < 0 or n.x >= w or n.y >= data.h or grid[n.y * w + n.x] != OutdoorGenerator.CHASM
				if not outside:
					continue
				# Ребро клетки между пропастью и землёй
				var e0: Vector2
				var e1: Vector2
				if o == Vector2i(-1, 0):
					e0 = Vector2(x, y + 1)
					e1 = Vector2(x, y)
				elif o == Vector2i(1, 0):
					e0 = Vector2(x + 1, y)
					e1 = Vector2(x + 1, y + 1)
				elif o == Vector2i(0, -1):
					e0 = Vector2(x, y)
					e1 = Vector2(x + 1, y)
				else:
					e0 = Vector2(x + 1, y + 1)
					e1 = Vector2(x, y + 1)
				var t0 := OutdoorGenerator.height_at(terrain, e0.x, e0.y)
				var t1 := OutdoorGenerator.height_at(terrain, e1.x, e1.y)
				e0 = OutdoorGenerator.corner_pos(terrain, int(e0.x), int(e0.y))
				e1 = OutdoorGenerator.corner_pos(terrain, int(e1.x), int(e1.y))
				if e0.distance_to(e1) < 0.05:
					continue
				var rows := [0.0, 1.2, 3.0, 6.0, 11.0, depth] if not water else [0.0, 1.0, depth]
				for r in rows.size() - 1:
					var y0: float = rows[r]
					var y1: float = rows[r + 1]
					var j0: float = 0.0 if r == 0 else jfn.call(e0 + Vector2(r, 0))
					var j1: float = jfn.call(e0 + Vector2(r + 1, 0))
					var k0: float = 0.0 if r == 0 else jfn.call(e1 + Vector2(r, 0))
					var k1: float = jfn.call(e1 + Vector2(r + 1, 0))
					var inward := Vector2(o).normalized() * -1.0
					var a0 := Vector3(e0.x + inward.x * j0, (t0 if r == 0 else level - y0), e0.y + inward.y * j0)
					var a1 := Vector3(e1.x + inward.x * k0, (t1 if r == 0 else level - y0), e1.y + inward.y * k0)
					var b1 := Vector3(e1.x + inward.x * k1, level - y1, e1.y + inward.y * k1)
					var b0 := Vector3(e0.x + inward.x * j1, level - y1, e0.y + inward.y * j1)
					var c0 := top.lerp(Color.BLACK, clampf(y0 / 9.0, 0, 1))
					var c1 := top.lerp(Color.BLACK, clampf(y1 / 9.0, 0, 1))
					for pc in [[a0, c0], [a1, c0], [b1, c1], [a0, c0], [b1, c1], [b0, c1]]:
						st.set_color(pc[1])
						st.add_vertex(pc[0])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.disable_fog = true
	mi.material_override = m
	root.add_child(mi)
	var center := Vector3(rect.position.x + rect.size.x * 0.5, 0, rect.position.y + rect.size.y * 0.5)
	if water:
		var wmi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(rect.size.x, rect.size.y)
		pm.subdivide_width = 8
		pm.subdivide_depth = 30
		wmi.mesh = pm
		wmi.material_override = WorldStyle.water_material()
		wmi.position = Vector3(center.x, level - 1.0, center.z)
		root.add_child(wmi)
	else:
		var abyss := MeshInstance3D.new()
		var am := PlaneMesh.new()
		am.size = Vector2(rect.size.x + 1, rect.size.y + 1)
		abyss.mesh = am
		var amat := StandardMaterial3D.new()
		amat.albedo_color = Color("#050408")
		amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		amat.disable_fog = true   # иначе туман красит дно в цвет неба — «дыра в мир»
		abyss.material_override = amat
		abyss.position = Vector3(center.x, level - depth + 2.0, center.z)
		root.add_child(abyss)
		_mist(root, Vector3(center.x, level - 6.0, center.z), Vector3(rect.size.x, 3.0, rect.size.y))


## Каменные глыбы на полянах: малая → средняя → большая, по ним можно забраться (коллизия по форме камня).
static func _rock_formations(root: Node3D, data: Dictionary, rng: RandomNumberGenerator) -> void:
	var terrain: Dictionary = data.terrain
	var sc := scene(N + "Rock_Medium_1.gltf")
	if sc == null:
		return
	for rk in data.get("rocks", []):
		var base: Vector2 = rk.pos
		var dir := Vector2(cos(rk.yaw), sin(rk.yaw))
		# Шаги: масштаб и высота каждой глыбы (верх ~0.8 м выше предыдущего)
		var sizes := [0.75, 1.35, 2.0]
		for i in sizes.size():
			var p: Vector2 = base + dir * (i * 1.25 - 1.25)
			var y := OutdoorGenerator.height_at(terrain, p.x, p.y)
			var model := "Rock_Medium_%d" % (1 + (i + rng.randi()) % 3)
			var rock := place(root, N + model + ".gltf", Vector3(p.x, y - 0.15 * sizes[i], p.y), rng.randf() * TAU, sizes[i])
			var body := StaticBody3D.new()
			body.collision_layer = 1 | 4
			rock.add_child(body)
			for mi in rock.find_children("*", "MeshInstance3D", true, false):
				var cs := CollisionShape3D.new()
				cs.shape = (mi as MeshInstance3D).mesh.create_convex_shape(true, false)
				cs.transform = MonsterRig._local_xform(rock, mi)
				body.add_child(cs)


static func _biome_of(kind: String) -> String:
	return {"meadow": "meadow", "forest": "forest", "riverside": "riverside", "ruins": "ruins"}.get(kind, "forest")


static func height_at(terrain: Dictionary, x: float, z: float) -> float:
	return OutdoorGenerator.height_at(terrain, x, z)


static func _mist(root: Node3D, center: Vector3, extent: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = center
	p.amount = 30
	p.lifetime = 8.0
	p.preprocess = 8.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extent * 0.5
	p.direction = Vector3(0, 1, 0)
	p.spread = 30
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.2
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 4.0
	p.scale_amount_max = 8.0
	var quad := QuadMesh.new()
	quad.size = Vector2(1, 1)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(0.45, 0.45, 0.52, 0.07)
	mat.disable_fog = true
	mat.albedo_texture = WorldStyle._soft_dot()
	quad.material = mat
	p.mesh = quad
	root.add_child(p)


static func _xf(pos: Vector3, yaw: float, s: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos)


## Растительность долины: леса у лесных районов, редкие деревья на лугах; деревья растут только на
## нормальной земле — не на скальных склонах, холмах и не вплотную к камням. Стволы и камни — с коллизией.
## Всё ставится на высоту рельефа, в стороне от дорог и построек.
## Модели для объектов, добавленных в редакторе локаций (тип → модель Stylized Nature).
const PROP_MODELS := {"tree": "CommonTree_1", "pine": "Pine_2", "dead_tree": "DeadTree_1", "rock": "Rock_Medium_2", "bush": "Bush_Common_Flowers"}


static func _vegetation(root: Node3D, data: Dictionary, rng: RandomNumberGenerator) -> void:
	var w: int = data.w
	var h: int = data.h
	var ext: Dictionary = data.ext
	var ew: int = ext.ew
	var eh: int = ext.eh
	var eg: PackedByteArray = ext.grid
	var edist: PackedInt32Array = data.edist
	var terrain: Dictionary = data.terrain
	var trees_by_model := {}
	var small_by_model := {}
	var rocks_by_model := {}
	var occupied := {}
	var models_by_kind := {
		"forest": ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5", "Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"],
		"meadow": ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_5"],
		"ruins": ["CommonTree_2", "DeadTree_1", "DeadTree_2", "CommonTree_4", "TwistedTree_1"],
		"riverside": ["CommonTree_1", "CommonTree_3", "Pine_1", "Pine_3", "TwistedTree_2"],
	}
	# Плотность деревьев на проходимой земле (вероятность на клетку) у центра района данного типа
	var land_density := {"forest": 0.05, "meadow": 0.006, "riverside": 0.016, "ruins": 0.01}
	var q := WorldStyle.quality()
	var keep_clear := _keep_clear_map(data)
	var region_of := func(x: float, z: float) -> Dictionary:
		var rid := OutdoorGenerator.region_at(data, Vector2(x, z))
		for r in data.regions:
			if r.id == rid:
				return r
		return {}
	var trunks: Array = []   # [позиция, радиус] — коллизия стволов
	for ez in eh:
		for ex in ew:
			var i := ez * ew + ex
			var v := eg[i]
			var px := ex - MARGIN + rng.randf()
			var pz := ez - MARGIN + rng.randf()
			var r: Dictionary = region_of.call(px, pz)
			var kind: String = r.get("kind", data.kind)
			var chance := 0.0
			if v == OutdoorGenerator.FLOOR:
				var gx := ex - MARGIN
				var gz := ez - MARGIN
				if keep_clear.has(Vector2i(gx, gz)):
					continue
				var dist_c: float = Vector2(px, pz).distance_to(r.get("center", Vector2.ZERO))
				# Чаща гуще на окраинах района, у центра — поляна
				chance = float(land_density.get(kind, 0.01)) * clampf((dist_c - 9.0) / 10.0, 0.0, 1.0) * (1.6 if dist_c > 22.0 else 1.0)
			if chance <= 0.0 or rng.randf() > chance * float(q.veg) * 1.25:
				continue
			var cell := Vector2i(ex / 2, ez / 2)
			if occupied.has(cell) or edist[i] != 0 or _near_block(eg, ew, eh, ex, ez):
				continue
			occupied[cell] = true
			var models: Array = models_by_kind.get(kind, models_by_kind.forest)
			var model: String = models[rng.randi() % models.size()]
			var s := rng.randf_range(0.75, 1.15) * (0.45 if model.begins_with("Twisted") else 1.0)
			var gy := height_at(terrain, px, pz)
			_add(trees_by_model, model, _xf(Vector3(px, gy - 0.15, pz), rng.randf() * TAU, s))
			trunks.append([Vector3(px, gy, pz), 0.3 * s * (1.6 if model.begins_with("Twisted") else 1.0)])
	# Деревья, камни и кусты, поставленные вручную в редакторе локаций
	for p in data.get("props", []):
		var pos: Vector2 = p.pos
		var gy := height_at(terrain, pos.x, pos.y)
		var s: float = p.get("scale", 1.0)
		var model: String = PROP_MODELS.get(p.type, "")
		if model == "":
			continue
		match String(p.type):
			"rock":
				_add(rocks_by_model, model, _xf(Vector3(pos.x, gy - 0.25, pos.y), p.yaw, 0.8 * s))
			"bush":
				_add(small_by_model, model, _xf(Vector3(pos.x, gy - 0.05, pos.y), p.yaw, s))
			_:
				_add(trees_by_model, model, _xf(Vector3(pos.x, gy - 0.15, pos.y), p.yaw, s))
				trunks.append([Vector3(pos.x, gy, pos.y), 0.3 * s])
	for model in trees_by_model:
		scatter(root, N + model + ".gltf", trees_by_model[model], q.tree_shadows)
	_canopy_colliders(root, trees_by_model, w, h)
	var trunk_body := StaticBody3D.new()
	trunk_body.collision_layer = 1
	root.add_child(trunk_body)
	for t in trunks:
		var cs := CollisionShape3D.new()
		var cyl := CylinderShape3D.new()
		cyl.radius = t[1]
		cyl.height = 4.0
		cs.shape = cyl
		cs.position = t[0] + Vector3(0, 1.5, 0)
		trunk_body.add_child(cs)

	# Кусты у подножия склонов, трава и цветы, камни (с коллизией), камешки на дорогах
	var edge_models := ["Bush_Common", "Bush_Common_Flowers", "Bush_Common", "Fern_1", "Plant_1_Big"]
	var ground_models := ["Grass_Common_Short", "Grass_Wispy_Short", "Grass_Common_Tall", "Flower_3_Group", "Flower_4_Group", "Clover_1", "Clover_2", "Plant_7", "Pebble_Round_2", "Pebble_Square_3", "Mushroom_Common", "Fern_1"]
	for ez in eh:
		for ex in ew:
			var i := ez * ew + ex
			var v := eg[i]
			var r := rng.randf()
			var px := ex - MARGIN + rng.randf()
			var pz := ez - MARGIN + rng.randf()
			if v == OutdoorGenerator.BLOCK and edist[i] == 1 and r < 0.5 * float(q.veg):
				var m: String = edge_models[rng.randi() % edge_models.size()]
				var foot := _toward_walkable(eg, ew, eh, ex, ez)
				px = ex - MARGIN + 0.5 + foot.x * 0.3
				pz = ez - MARGIN + 0.5 + foot.y * 0.3
				_add(small_by_model, m, _xf(Vector3(px, height_at(terrain, px, pz) - 0.05, pz), rng.randf() * TAU, rng.randf_range(0.75, 1.1)))
			elif v == OutdoorGenerator.FLOOR and r < 0.07 * float(q.veg) and not _near_entity(data, Vector2i(ex - MARGIN, ez - MARGIN)) and not data.get("veg_clear", {}).has("%d,%d" % [ex - MARGIN, ez - MARGIN]):
				var m: String = ground_models[rng.randi() % ground_models.size()]
				var s := 0.45 if (m.begins_with("Flower") or m.begins_with("Grass_Common_Tall")) else 0.6
				_add(small_by_model, m, _xf(Vector3(px, height_at(terrain, px, pz), pz), rng.randf() * TAU, s * rng.randf_range(0.8, 1.2)))
			elif v == OutdoorGenerator.FLOOR and r > 0.9965 and not keep_clear.has(Vector2i(ex - MARGIN, ez - MARGIN)) and not occupied.has(Vector2i(ex / 2, ez / 2)):
				# Одиночные камни в поле — препятствие с коллизией
				_add(rocks_by_model, "Rock_Medium_%d" % (1 + rng.randi() % 3), _xf(Vector3(px, height_at(terrain, px, pz) - 0.25, pz), rng.randf() * TAU, rng.randf_range(0.5, 0.9)))
			elif v == OutdoorGenerator.PATH and r < 0.03 and not _near_entity(data, Vector2i(ex - MARGIN, ez - MARGIN)):
				var cx := ex - MARGIN + 0.5
				var cz := ez - MARGIN + 0.5
				_add(small_by_model, "RockPath_Round_Small_%d" % (1 + rng.randi() % 3), _xf(Vector3(cx, height_at(terrain, cx, cz) - 0.02, cz), rng.randf() * TAU, rng.randf_range(0.6, 0.9)))
			elif v == OutdoorGenerator.BLOCK and edist[i] >= 1 and edist[i] <= 3 and r < 0.06 and not occupied.has(Vector2i(ex / 2, ez / 2)):
				_add(rocks_by_model, "Rock_Medium_%d" % (1 + rng.randi() % 3), _xf(Vector3(px, height_at(terrain, px, pz) - 0.3, pz), rng.randf() * TAU, rng.randf_range(0.6, 1.2)))
	for m in small_by_model:
		var big: bool = m.begins_with("Bush")
		scatter(root, N + m + ".gltf", small_by_model[m], big and q.shadows, float(q.view_dist) * (0.8 if big else 0.55))
	for m in rocks_by_model:
		scatter(root, N + m + ".gltf", rocks_by_model[m], q.shadows, float(q.view_dist) * 0.9)
		_rock_bodies(root, N + m + ".gltf", rocks_by_model[m])

	_buildings(root, data, rng)
	for r in data.regions:
		if r.kind in ["forest", "riverside"]:
			var c: Vector2 = r.center
			_fireflies(root, Vector3(c.x, height_at(terrain, c.x, c.y) + 1.5, c.y), Vector3(26, 2.5, 26))


## Клетки, где не растут деревья и не лежат камни: дороги (с обочиной), центры районов, площадки построек,
## входы в пещеры, острова.
static func _keep_clear_map(data: Dictionary) -> Dictionary:
	var keep := {}
	var grid: PackedByteArray = data.grid
	var w: int = data.w
	for y in data.h:
		for x in w:
			if grid[y * w + x] == OutdoorGenerator.PATH:
				for oy in range(-2, 3):
					for ox in range(-2, 3):
						keep[Vector2i(x + ox, y + oy)] = true
	var spots: Array = []
	for r in data.regions:
		spots.append([r.center, 9.0])
	for pad in data.pads:
		spots.append([pad.center, float(pad.radius) + 1.5])
	for c in data.caves:
		spots.append([Vector2(c.cell), 4.0])
	for ch in data.chasms:
		spots.append([ch.center, float(ch.r_out) + 2.0])
	for rk in data.rocks:
		spots.append([rk.pos, 4.0])
	for cl in data.get("columns", []):
		spots.append([cl.center, 6.5])
	for st in data.get("stamps", []):
		spots.append([st.center, float(st.radius) + 2.5])
	for s in spots:
		var c: Vector2 = s[0]
		var rad: float = s[1]
		for y in range(int(c.y - rad), int(c.y + rad) + 1):
			for x in range(int(c.x - rad), int(c.x + rad) + 1):
				if Vector2(x + 0.5, y + 0.5).distance_to(c) <= rad:
					keep[Vector2i(x, y)] = true
	# Кисть редактора «убрать растительность»
	for k in data.get("veg_clear", {}):
		var xz: PackedStringArray = String(k).split(",")
		keep[Vector2i(int(xz[0]), int(xz[1]))] = true
	return keep


## Рядом (в 1 клетке) непроходимый крутой склон — дерево «врастало» бы в скалу.
static func _near_block(eg: PackedByteArray, ew: int, eh: int, ex: int, ez: int) -> bool:
	for oy in range(-1, 2):
		for ox in range(-1, 2):
			var x := ex + ox
			var z := ez + oy
			if x < 0 or z < 0 or x >= ew or z >= eh or eg[z * ew + x] == OutdoorGenerator.BLOCK:
				return true
	return false


static var _convex_cache: Dictionary = {}


## Коллизия камней MultiMesh: выпуклая оболочка меша на каждый экземпляр (одна форма на модель).
static func _rock_bodies(root: Node3D, path: String, transforms: Array) -> void:
	if not _convex_cache.has(path):
		var sc := scene(path)
		if sc == null:
			return
		var inst: Node3D = sc.instantiate()
		var parts: Array = []
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			parts.append([(mi as MeshInstance3D).mesh.create_convex_shape(true, false), MonsterRig._local_xform(inst, mi)])
		inst.free()
		_convex_cache[path] = parts
	var body := StaticBody3D.new()
	body.collision_layer = 1
	root.add_child(body)
	for xf in transforms:
		for part in _convex_cache[path]:
			var cs := CollisionShape3D.new()
			cs.shape = part[0]
			cs.transform = xf * part[1]
			body.add_child(cs)


# ---------------------------------------------------------------- Постройки

static func _buildings(root: Node3D, data: Dictionary, rng: RandomNumberGenerator) -> void:
	var terrain: Dictionary = data.terrain
	for b in data.get("buildings", []):
		var c: Vector2 = b.center
		var node := Node3D.new()
		node.position = Vector3(c.x, height_at(terrain, c.x, c.y), c.y)
		node.rotation.y = b.yaw
		root.add_child(node)
		var body := StaticBody3D.new()
		body.collision_layer = 1 | 4
		node.add_child(body)
		match b.type:
			"hut":
				_hut(node, body)
			"fence":
				_fence(node, body, rng)
			"camp":
				_camp(node, body, rng)
			"ruins":
				_ruined_temple(node, body, rng)


static func _box_shape(body: StaticBody3D, size: Vector3, pos: Vector3, yaw: float = 0.0) -> void:
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	cs.position = pos
	cs.rotation.y = yaw
	body.add_child(cs)


## Хижина 4×4 м: стены из модулей деревни (дверь — к центру района), крыша, пол, фундамент уходит в землю.
static func _hut(node: Node3D, body: StaticBody3D) -> void:
	# Фундамент: каменный цоколь чуть ниже земли — дом не висит на уклоне
	var base := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(4.4, 0.8, 4.4)
	base.mesh = bm
	var stone := StandardMaterial3D.new()
	stone.albedo_texture = load(V + "T_UnevenBrick_BaseColor.png")
	stone.uv1_triplanar = true
	stone.uv1_scale = Vector3(0.5, 0.5, 0.5)
	base.material_override = stone
	base.position.y = -0.25
	node.add_child(base)
	_box_shape(body, Vector3(4.4, 0.8, 4.4), Vector3(0, -0.25, 0))
	for i in 4:
		for j in 2:
			var model := "Wall_Plaster_Straight"
			if i == 0 and j == 1:
				model = "Wall_Plaster_Door_Round"
			elif i == 2 and j == 0:
				model = "Wall_Plaster_Window_Wide_Round"
			var yaw := PI * 0.5 * i
			var local := Vector3(-1.0 + j * 2.0, 0.15, 2.0 - 0.09).rotated(Vector3.UP, yaw)
			place(node, V + model + ".gltf", local, yaw)
		var yaw2 := PI * 0.5 * i
		if i == 0:
			# Дверной проём: стена слева от двери и узкая справа
			_box_shape(body, Vector3(2.4, 3.1, 0.4), Vector3(-0.8, 1.7, 1.8).rotated(Vector3.UP, yaw2), yaw2)
			_box_shape(body, Vector3(0.45, 3.1, 0.4), Vector3(1.78, 1.7, 1.8).rotated(Vector3.UP, yaw2), yaw2)
		else:
			_box_shape(body, Vector3(4.0, 3.1, 0.4), Vector3(0, 1.7, 1.8).rotated(Vector3.UP, yaw2), yaw2)
	for corner in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		place(node, V + "Corner_Exterior_Wood.gltf", Vector3(corner.x * 2.0, 0.15, corner.y * 2.0))
	for fx in [-1, 1]:
		for fz in [-1, 1]:
			place(node, V + "Floor_WoodDark.gltf", Vector3(fx, 0.17, fz))
	place(node, V + "Roof_RoundTiles_4x4.gltf", Vector3(0, 3.25, 0))
	_box_shape(body, Vector3(5.2, 0.6, 5.2), Vector3(0, 3.6, 0))


## Изгородь из секций на столбиках (огород у хижины), с проходом посередине.
static func _fence(node: Node3D, body: StaticBody3D, rng: RandomNumberGenerator) -> void:
	for i in 5:
		if i == 2:
			continue
		var x := -4.0 + i * 2.0
		place(node, V + ("Prop_WoodenFence_Single.gltf" if i % 2 == 0 else "Prop_WoodenFence_Extension1.gltf"), Vector3(x, 0, 0), rng.randf_range(-0.04, 0.04))
		_box_shape(body, Vector3(2.0, 0.9, 0.2), Vector3(x, 0.45, 0))
	place(node, P + "Barrel_Apples.gltf", Vector3(-3.0, 0, -1.4), rng.randf() * TAU)
	place(node, P + "Crate_Wooden.gltf", Vector3(3.2, 0, -1.2), rng.randf() * TAU)


## Лагерь охотников: костёр, брёвна-скамьи, ящики, бочка.
static func _camp(node: Node3D, body: StaticBody3D, rng: RandomNumberGenerator) -> void:
	WorldStyle.make_campfire(node, Vector3.ZERO)
	for k in 3:
		var a := TAU * k / 3.0 + rng.randf() * 0.4
		var log := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.22
		cm.bottom_radius = 0.24
		cm.height = 1.8
		log.mesh = cm
		var bark := StandardMaterial3D.new()
		bark.albedo_texture = load(N + "Bark_NormalTree.png")
		bark.uv1_triplanar = true
		log.material_override = bark
		log.position = Vector3(cos(a) * 2.2, 0.2, sin(a) * 2.2)
		log.rotation = Vector3(0, -a, PI * 0.5)
		node.add_child(log)
		_box_shape(body, Vector3(0.45, 0.45, 1.8), log.position, -a + PI * 0.5)
	place(node, P + "Crate_Wooden.gltf", Vector3(3.2, 0, 1.0), rng.randf() * TAU)
	place(node, P + "Barrel.gltf", Vector3(-3.0, 0, 1.6), rng.randf() * TAU)
	_box_shape(body, Vector3(1.0, 1.0, 1.0), Vector3(3.2, 0.5, 1.0))
	_box_shape(body, Vector3(0.9, 1.2, 0.9), Vector3(-3.0, 0.6, 1.6))


## Руины храма: обломки стен по периметру 8×8 м с проёмами, колонны, плиты пола.
static func _ruined_temple(node: Node3D, body: StaticBody3D, rng: RandomNumberGenerator) -> void:
	for side in 4:
		var yaw := PI * 0.5 * side
		for j in 4:
			if j == 1 or (j == 2 and rng.randf() < 0.5):
				continue   # проёмы и обрушенные секции
			var local := Vector3(-3.0 + j * 2.0, -0.1, 4.0).rotated(Vector3.UP, yaw)
			var wall := place(node, V + "Wall_UnevenBrick_Straight.gltf", local, yaw)
			var hs := rng.randf_range(0.45, 1.0)
			wall.scale = Vector3(1, hs, 1)
			_box_shape(body, Vector3(2.0, 3.1 * hs, 0.45), local + Vector3(0, 1.55 * hs, 0), yaw)
	for corner in [Vector2(1, 1), Vector2(1, -1), Vector2(-1, 1), Vector2(-1, -1)]:
		var col := place(node, D + "column.glb", Vector3(corner.x * 2.2, 0, corner.y * 2.2), rng.randf() * TAU, 1.6)
		col.scale = Vector3(1.6, 1.6 * 1.4, 1.6)
		_box_shape(body, Vector3(0.8, 3.5, 0.8), Vector3(corner.x * 2.2, 1.75, corner.y * 2.2))
	for i in 6:
		place(node, V + "Floor_UnevenBrick.gltf", Vector3(rng.randf_range(-2.5, 2.5), 0.02, rng.randf_range(-2.5, 2.5)), rng.randf() * TAU)


## Направление (в клетках) к ближайшей проходимой соседней клетке — для кустов у подножия склона.
static func _toward_walkable(eg: PackedByteArray, ew: int, eh: int, ex: int, ez: int) -> Vector2:
	var acc := Vector2.ZERO
	for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var x: int = ex + o.x
		var z: int = ez + o.y
		if x >= 0 and z >= 0 and x < ew and z < eh and eg[z * ew + x] in [OutdoorGenerator.FLOOR, OutdoorGenerator.PATH]:
			acc += Vector2(o)
	return acc.normalized() if acc.length() > 0.01 else Vector2.ZERO


## Кроны деревьев — препятствие только для камеры (слой 4): пружина камеры не заходит в листву.
static func _canopy_colliders(root: Node3D, trees_by_model: Dictionary, w: int, h: int) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 4
	body.collision_mask = 0
	root.add_child(body)
	for model in trees_by_model:
		for xf in trees_by_model[model]:
			var p: Vector3 = xf.origin
			if p.x < -6 or p.z < -6 or p.x > w + 6 or p.z > h + 6:
				continue
			var s: float = xf.basis.get_scale().x * (2.2 if model.begins_with("Twisted") else 1.0)
			var cs := CollisionShape3D.new()
			var cyl := CylinderShape3D.new()
			cyl.radius = 1.9 * s
			cyl.height = 6.0 * s
			cs.shape = cyl
			cs.position = p + Vector3(0, 4.2 * s, 0)
			body.add_child(cs)


static func _add(dict: Dictionary, model: String, xf: Transform3D) -> void:
	if not dict.has(model):
		dict[model] = []
	dict[model].append(xf)


static func _near_entity(data: Dictionary, c: Vector2i) -> bool:
	for sp in data.get("signposts", []):
		if c.distance_to(sp.cell) < 2.5:
			return true
	for e in data.get("caves", []):
		if c.distance_to(e.cell) < 2.5 or c.distance_to(e.arrive) < 2.5:
			return true
	return false


static func _fireflies(root: Node3D, center: Vector3, extent: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = center
	p.amount = 70
	p.lifetime = 6.0
	p.preprocess = 6.0
	p.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	p.emission_box_extents = extent * 0.5
	p.direction = Vector3(0, 1, 0)
	p.spread = 180
	p.initial_velocity_min = 0.05
	p.initial_velocity_max = 0.25
	p.gravity = Vector3.ZERO
	p.scale_amount_min = 0.05
	p.scale_amount_max = 0.09
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0))
	curve.add_point(Vector2(0.5, 1))
	curve.add_point(Vector2(1, 0))
	p.scale_amount_curve = curve
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	sm.radial_segments = 6
	sm.rings = 3
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(1.0, 0.95, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.9, 0.4)
	mat.emission_energy_multiplier = 3.0
	sm.material = mat
	p.mesh = sm
	root.add_child(p)


# ================================================================ MultiMesh

## Много копий модели одним MultiMesh на каждый её меш (деревья, трава, камни, стены).
## Экземпляры группируются по чанкам CHUNK×CHUNK м: MultiMesh отсекается по камере только целиком,
## поэтому один MultiMesh на всю карту рисовался бы всегда. view_dist — дальность прорисовки чанка.
const CHUNK := 14.0


static func scatter(root: Node3D, path: String, transforms: Array, shadows: bool = true, view_dist: float = -1.0) -> void:
	if transforms.is_empty():
		return
	var sc := scene(path)
	if sc == null:
		return
	if view_dist < 0.0:
		view_dist = WorldStyle.quality().view_dist
	var chunks := {}
	for xf in transforms:
		var key := Vector2i(floori(xf.origin.x / CHUNK), floori(xf.origin.z / CHUNK))
		if not chunks.has(key):
			chunks[key] = []
		chunks[key].append(xf)
	var inst: Node3D = sc.instantiate()
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var local := MonsterRig._local_xform(inst, mi)
		for key in chunks:
			var list: Array = chunks[key]
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.mesh = mi.mesh
			mm.instance_count = list.size()
			for i in list.size():
				mm.set_instance_transform(i, list[i] * local)
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			if view_dist > 0.0:
				mmi.visibility_range_end = view_dist
				mmi.visibility_range_end_margin = 6.0
				mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
			root.add_child(mmi)
	inst.free()


static func place(root: Node3D, path: String, pos: Vector3, yaw: float = 0.0, s: float = 1.0) -> Node3D:
	var sc := scene(path)
	if sc == null:
		return Node3D.new()
	var n: Node3D = sc.instantiate()
	n.position = pos
	n.rotation.y = yaw
	n.scale = Vector3.ONE * s
	root.add_child(n)
	return n


# ================================================================ Подземелья

static func _build_underground(root: Node3D, data: Dictionary) -> Dictionary:
	var kind: String = data.get("kind", "dungeon")
	var env := WorldStyle.environment("cave")
	var e: Environment = env[0]
	match kind:
		"cave":
			e.ambient_light_color = Color("#5A5A7A")
			e.fog_light_color = Color("#0E0C18")
		"tomb":
			e.ambient_light_color = Color("#56607A")
			e.fog_light_color = Color("#0C0E14")
		_:
			e.ambient_light_color = Color("#6A5A4A")
	var we := WorldEnvironment.new()
	we.environment = e
	root.add_child(we)
	root.add_child(env[1])
	var w: int = data.w
	var h: int = data.h
	var grid: PackedByteArray = data.grid
	var astar := AStarGrid2D.new()
	astar.region = Rect2i(0, 0, w, h)
	astar.cell_size = Vector2(1, 1)
	astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_ONLY_IF_NO_OBSTACLES
	astar.update()
	var walls_body := StaticBody3D.new()
	walls_body.collision_layer = WALL_LAYER
	root.add_child(walls_body)
	var floors: Array = []
	var details: Array = []
	var walls: Array = []
	var rng := RandomNumberGenerator.new()
	rng.seed = w * 977 + h
	for y in h:
		for x in w:
			var v := grid[y * w + x]
			if v != DungeonGenerator.WALL:
				if (x * 7 + y * 13) % 9 == 0:
					details.append(Transform3D(Basis(), Vector3(x + 0.5, 0, y + 0.5)))
				else:
					floors.append(Transform3D(Basis(), Vector3(x + 0.5, 0, y + 0.5)))
			else:
				astar.set_point_solid(Vector2i(x, y), true)
				if _near_floor(grid, w, h, x, y):
					walls.append(Vector3(x + 0.5, 0, y + 0.5))
					var cs := CollisionShape3D.new()
					var box := BoxShape3D.new()
					box.size = Vector3(1, 3, 1)
					cs.shape = box
					cs.position = Vector3(x + 0.5, 1.5, y + 0.5)
					walls_body.add_child(cs)
	var ground := StaticBody3D.new()
	ground.collision_layer = 1
	var gshape := CollisionShape3D.new()
	gshape.shape = WorldBoundaryShape3D.new()
	ground.add_child(gshape)
	root.add_child(ground)

	if kind == "cave":
		# Пол — стилизованная земля, стены — скалы
		var floor_mi := MeshInstance3D.new()
		var pm := PlaneMesh.new()
		pm.size = Vector2(w, h)
		floor_mi.mesh = pm
		floor_mi.position = Vector3(w * 0.5, 0, h * 0.5)
		floor_mi.material_override = WorldStyle.ground_material("cave")
		root.add_child(floor_mi)
		var rocks := {}
		for p in walls:
			_add(rocks, "Rock_Medium_%d" % (1 + rng.randi() % 3), Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(rng.randf_range(0.45, 0.6), rng.randf_range(0.9, 1.5), rng.randf_range(0.45, 0.6))), p + Vector3(0, -0.2, 0)))
		for m in rocks:
			scatter(root, N + m + ".gltf", rocks[m])
		_cave_glow(root, data, rng)
	else:
		var tint := Color(0.62, 0.56, 0.5) if kind == "dungeon" else Color(0.55, 0.58, 0.66)
		var wall_tint := Color(0.78, 0.64, 0.48) if kind == "dungeon" else Color(0.62, 0.64, 0.72)
		_tiles(root, D + "floor.glb", floors, tint)
		_tiles(root, D + "floor-detail.glb", details, tint * 1.05)
		var wall_xf: Array = []
		for p in walls:
			wall_xf.append(Transform3D(Basis().scaled(Vector3(1, WALL_HEIGHT, 1)), p))   # плитка Kenney рассчитана на маленьких героев
		_tiles(root, D + "wall.glb", wall_xf, wall_tint)
		if kind == "tomb":
			_tomb_props(root, data, rng)
	# Свет комнат
	for r in data.rooms:
		var rect: Rect2i = r.rect
		var light := OmniLight3D.new()
		light.position = Vector3(rect.position.x + rect.size.x / 2.0, 2.6, rect.position.y + rect.size.y / 2.0)
		light.light_color = {"cave": Color("#7FA8FF"), "tomb": Color("#9FB8E8")}.get(kind, Color("#FFB070"))
		light.light_energy = 1.2
		light.omni_range = maxf(rect.size.x, rect.size.y) * 0.85
		light.omni_attenuation = 0.9
		root.add_child(light)
	return {"astar": astar, "fall_y": -20.0}


static func _tiles(root: Node3D, path: String, transforms: Array, tint: Color) -> void:
	if transforms.is_empty():
		return
	var sc := scene(path)
	if sc == null:
		return
	var mesh := CharacterRig.first_mesh(sc)
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = transforms.size()
	for i in transforms.size():
		mm.set_instance_transform(i, transforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	var base := mesh.surface_get_material(0)
	if base is StandardMaterial3D:
		var mat: StandardMaterial3D = base.duplicate()
		mat.albedo_color = tint
		mmi.material_override = mat
	root.add_child(mmi)


static func _near_floor(grid: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and ny >= 0 and nx < w and ny < h and grid[ny * w + nx] != DungeonGenerator.WALL:
				return true
	return false


## Пещера: светящиеся грибы и кристаллы в комнатах.
static func _cave_glow(root: Node3D, data: Dictionary, rng: RandomNumberGenerator) -> void:
	var shrooms: Array = []
	for r in data.rooms:
		var rect: Rect2i = r.rect
		for i in rng.randi_range(2, 4):
			var p := Vector3(rng.randf_range(rect.position.x + 0.5, rect.end.x - 0.5), 0, rng.randf_range(rect.position.y + 0.5, rect.end.y - 0.5))
			if Vector2i(int(p.x), int(p.z)).distance_to(data.start) < 2:
				continue
			shrooms.append(_xf(p, rng.randf() * TAU, rng.randf_range(0.8, 1.4)))
			if i == 0:
				var l := OmniLight3D.new()
				l.light_color = Color("#5FE0C8") if rng.randf() < 0.5 else Color("#B07CFF")
				l.light_energy = 0.9
				l.omni_range = 3.0
				l.position = p + Vector3(0, 0.6, 0)
				root.add_child(l)
		# Кристалл
		if rng.randf() < 0.5:
			var cp := Vector3(rect.position.x + 0.7, 0, rect.position.y + 0.7)
			var crystal := MeshInstance3D.new()
			var prism := PrismMesh.new()
			prism.size = Vector3(0.35, 1.1, 0.35)
			crystal.mesh = prism
			var cm := StandardMaterial3D.new()
			cm.albedo_color = Color("#9AD8FF")
			cm.emission_enabled = true
			cm.emission = Color("#58B8FF")
			cm.emission_energy_multiplier = 1.6
			crystal.material_override = cm
			crystal.position = cp + Vector3(0, 0.55, 0)
			crystal.rotation = Vector3(rng.randf_range(-0.3, 0.3), rng.randf() * TAU, rng.randf_range(-0.3, 0.3))
			root.add_child(crystal)
	scatter(root, N + "Mushroom_Common.gltf", shrooms, false)


## Гробница: свечи, вазы, цепи.
static func _tomb_props(root: Node3D, data: Dictionary, rng: RandomNumberGenerator) -> void:
	for r in data.rooms:
		var rect: Rect2i = r.rect
		for corner in [rect.position + Vector2i(1, 1), rect.end - Vector2i(2, 2)]:
			if rng.randf() < 0.7 and Vector2i(corner).distance_to(data.start) > 2:
				place(root, P + "CandleStick_Triple.gltf", Vector3(corner.x + 0.5, 0, corner.y + 0.5), rng.randf() * TAU, 1.4)
				var l := OmniLight3D.new()
				l.light_color = Color("#FFC27A")
				l.light_energy = 0.8
				l.omni_range = 3.5
				l.position = Vector3(corner.x + 0.5, 0.9, corner.y + 0.5)
				root.add_child(l)
		if rng.randf() < 0.6:
			place(root, P + ["Vase_2.gltf", "Vase_4.gltf", "Chain_Coil.gltf"][rng.randi() % 3], Vector3(rect.end.x - 1.5, 0, rect.position.y + 1.5), rng.randf() * TAU)
