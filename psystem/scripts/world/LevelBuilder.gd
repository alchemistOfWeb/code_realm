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
			var x0 := float(ex - MARGIN)
			var z0 := float(ez - MARGIN)
			var p0 := Vector3(x0, hv[ez * vw + ex], z0)
			var p1 := Vector3(x0 + 1, hv[ez * vw + ex + 1], z0)
			var p2 := Vector3(x0 + 1, hv[(ez + 1) * vw + ex + 1], z0 + 1)
			var p3 := Vector3(x0, hv[(ez + 1) * vw + ex], z0 + 1)
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


## Растительность и руины. Работает по расширенной сетке: лес на склонах вокруг полян и троп, деревья
## по типу ближайшего района; всё ставится на высоту рельефа.
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
	var occupied := {}
	var models_by_kind := {
		"forest": ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5", "Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"],
		"meadow": ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_5"],
		"ruins": ["CommonTree_2", "DeadTree_1", "DeadTree_2", "CommonTree_4", "TwistedTree_1"],
		"riverside": ["CommonTree_1", "CommonTree_3", "Pine_1", "Pine_3", "TwistedTree_2"],
	}
	var density_by_kind := {"forest": 0.5, "meadow": 0.3, "riverside": 0.42, "ruins": 0.33}
	var q := WorldStyle.quality()
	var kind_at := func(x: float, z: float) -> String:
		var rid := OutdoorGenerator.region_at(data, Vector2(x, z))
		for r in data.regions:
			if r.id == rid:
				return r.kind
		return data.kind
	# Деревья на склонах вокруг полян и вдоль троп
	for ez in eh:
		for ex in ew:
			var i := ez * ew + ex
			if eg[i] != OutdoorGenerator.BLOCK:
				continue
			var d := edist[i]
			if d < 3 or d > 8:
				continue   # не ближе 3 м от проходимой зоны: кроны не нависают над тропой и камерой
			var cell := Vector2i(ex / 3, ez / 3)
			if occupied.has(cell):
				continue
			var px := ex - MARGIN + rng.randf()
			var pz := ez - MARGIN + rng.randf()
			var kind: String = kind_at.call(px, pz)
			if rng.randf() > float(density_by_kind.get(kind, 0.4)) * float(q.veg) * (1.2 if d <= 4 else 0.7):
				continue
			occupied[cell] = true
			var models: Array = models_by_kind.get(kind, models_by_kind.forest)
			var model: String = models[rng.randi() % models.size()]
			var s := rng.randf_range(0.75, 1.15) * (0.45 if model.begins_with("Twisted") else 1.0)
			_add(trees_by_model, model, _xf(Vector3(px, height_at(terrain, px, pz) - 0.1, pz), rng.randf() * TAU, s))
	# Лес до горизонта — силуэты на дальних холмах
	var outer := {}
	var outer_count := 0
	for i in int(q.outer_trees) * 4:
		if outer_count >= int(q.outer_trees):
			break
		var px := rng.randf_range(-MARGIN + 2, w + MARGIN - 2)
		var pz := rng.randf_range(-MARGIN + 2, h + MARGIN - 2)
		var ei := (int(pz) + MARGIN) * ew + int(px) + MARGIN
		if eg[ei] != OutdoorGenerator.BLOCK or (edist[ei] >= 0 and edist[ei] < 8):
			continue
		var models: Array = models_by_kind.get(data.kind, models_by_kind.forest)
		var model: String = models[rng.randi() % models.size()]
		_add(outer, model, _xf(Vector3(px, height_at(terrain, px, pz) - 0.1, pz), rng.randf() * TAU, rng.randf_range(0.9, 1.3) * (0.45 if model.begins_with("Twisted") else 1.0)))
		outer_count += 1
	for model in trees_by_model:
		scatter(root, N + model + ".gltf", trees_by_model[model], q.tree_shadows)
	for model in outer:
		scatter(root, N + model + ".gltf", outer[model], false, float(q.view_dist) + 20.0)
	_canopy_colliders(root, trees_by_model, w, h)

	# Кусты и камни у подножия склонов, трава и цветы на полянах, камни на тропах
	var edge_models := ["Bush_Common", "Bush_Common_Flowers", "Bush_Common", "Rock_Medium_1", "Fern_1", "Plant_1_Big"]
	var ground_models := ["Grass_Common_Short", "Grass_Wispy_Short", "Grass_Common_Tall", "Flower_3_Group", "Flower_4_Group", "Clover_1", "Clover_2", "Plant_7", "Pebble_Round_2", "Pebble_Square_3", "Mushroom_Common", "Fern_1"]
	for ez in eh:
		for ex in ew:
			var i := ez * ew + ex
			var v := eg[i]
			var r := rng.randf()
			var px := ex - MARGIN + rng.randf()
			var pz := ez - MARGIN + rng.randf()
			if v == OutdoorGenerator.BLOCK and edist[i] == 1 and r < 0.6 * float(q.veg):
				var m: String = edge_models[rng.randi() % edge_models.size()]
				var big := 0.55 if m.begins_with("Rock") else 1.0
				var foot := _toward_walkable(eg, ew, eh, ex, ez)
				px = ex - MARGIN + 0.5 + foot.x * 0.3
				pz = ez - MARGIN + 0.5 + foot.y * 0.3
				_add(small_by_model, m, _xf(Vector3(px, height_at(terrain, px, pz) - (0.2 if big < 1.0 else 0.05), pz), rng.randf() * TAU, rng.randf_range(0.75, 1.1) * big))
			elif v == OutdoorGenerator.FLOOR and r < 0.07 * float(q.veg) and not _near_entity(data, Vector2i(ex - MARGIN, ez - MARGIN)):
				var m: String = ground_models[rng.randi() % ground_models.size()]
				var s := 0.45 if (m.begins_with("Flower") or m.begins_with("Grass_Common_Tall")) else 0.6
				_add(small_by_model, m, _xf(Vector3(px, height_at(terrain, px, pz), pz), rng.randf() * TAU, s * rng.randf_range(0.8, 1.2)))
			elif v == OutdoorGenerator.PATH and r < 0.04 and not _near_entity(data, Vector2i(ex - MARGIN, ez - MARGIN)):
				var cx := ex - MARGIN + 0.5
				var cz := ez - MARGIN + 0.5
				_add(small_by_model, "RockPath_Round_Small_%d" % (1 + rng.randi() % 3), _xf(Vector3(cx, height_at(terrain, cx, cz), cz), rng.randf() * TAU, rng.randf_range(0.6, 0.9)))
			elif v == OutdoorGenerator.BLOCK and edist[i] == 2 and r < 0.1:
				_add(small_by_model, "Rock_Medium_%d" % (1 + rng.randi() % 3), _xf(Vector3(px, height_at(terrain, px, pz) - 0.3, pz), rng.randf() * TAU, rng.randf_range(0.6, 1.2)))
	for m in small_by_model:
		var big: bool = m.begins_with("Bush") or m.begins_with("Rock")
		scatter(root, N + m + ".gltf", small_by_model[m], big and q.shadows, float(q.view_dist) * (0.8 if big else 0.55))

	var ruins_clearings: Array = data.clearings.filter(func(c): return kind_at.call(c.center.x, c.center.y) == "ruins")
	if not ruins_clearings.is_empty():
		_ruins(root, data, ruins_clearings, rng)
	for r in data.regions:
		if r.kind in ["forest", "riverside"]:
			var c: Vector2 = r.center
			_fireflies(root, Vector3(c.x, height_at(terrain, c.x, c.y) + 1.5, c.y), Vector3(26, 2.5, 26))


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


## Руины: высокие обломки стен и арки по краям полян (граница проходимой зоны), колонны, плиты, лоза, черепки.
static func _ruins(root: Node3D, data: Dictionary, clearings: Array, rng: RandomNumberGenerator) -> void:
	var w: int = data.w
	var terrain: Dictionary = data.terrain
	var by_model := {}
	for c in clearings:
		var n := int(c.radius * 1.2)
		for i in n:
			var a := TAU * i / n + rng.randf_range(-0.15, 0.15)
			if rng.randf() < 0.2:
				continue
			var p: Vector2 = c.center + Vector2(cos(a), sin(a)) * (c.radius + 0.8)
			var cell := Vector2i(p)
			if cell.x < 0 or cell.y < 0 or cell.x >= w or cell.y >= data.h:
				continue
			if data.grid[cell.y * w + cell.x] != OutdoorGenerator.BLOCK:
				continue
			var model: String = ["Wall_UnevenBrick_Straight", "Wall_UnevenBrick_Window_Wide_Round", "Wall_Arch", "Wall_UnevenBrick_Straight", "Corner_Exterior_Brick"][rng.randi() % 5]
			var yaw := -a + PI / 2
			var s := rng.randf_range(0.85, 1.05)
			var gy := height_at(terrain, p.x, p.y) * 0.5 - 0.1
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * rng.randf_range(0.75, 1.15), s)), Vector3(p.x, gy, p.y))
			_add(by_model, model, xf)
			if rng.randf() < 0.3:
				_add(by_model, "Prop_Vine%d" % (1 + rng.randi() % 2), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, gy + 2.7, p.y) + Vector3(cos(a), 0, sin(a)) * -0.3))
		# Плиты пола и черепки внутри поляны
		for i in int(c.radius):
			var a := rng.randf() * TAU
			var r: float = rng.randf() * (c.radius - 1.0)
			var p: Vector2 = c.center + Vector2(cos(a), sin(a)) * r
			if _near_entity(data, Vector2i(p)):
				continue
			_add(by_model, ["Floor_UnevenBrick", "Vase_Rubble_Medium", "Prop_Brick1", "Prop_Brick2"][rng.randi() % 4],
				_xf(Vector3(p.x, height_at(terrain, p.x, p.y) + 0.01, p.y), rng.randf() * TAU, 1.0))
	for m in by_model:
		var dir := V if not m.begins_with("Vase") else P
		scatter(root, dir + m + ".gltf", by_model[m])
	# Колонны Kenney
	var cols: Array = []
	for c in clearings:
		if rng.randf() < 0.6:
			var a := rng.randf() * TAU
			var p: Vector2 = c.center + Vector2(cos(a), sin(a)) * (c.radius - 0.8)
			if not _near_entity(data, Vector2i(p)):
				cols.append(_xf(Vector3(p.x, height_at(terrain, p.x, p.y), p.y), rng.randf() * TAU, 1.6))
	for i in cols.size():
		cols[i] = cols[i].scaled_local(Vector3(1, 1.4, 1))
	scatter(root, D + "column.glb", cols)


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
