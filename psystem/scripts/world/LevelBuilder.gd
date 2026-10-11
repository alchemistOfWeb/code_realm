class_name LevelBuilder
extends RefCounted
## Построение 3D-уровня вылазки по данным генератора (OutdoorGenerator / DungeonGenerator).
## Поверхность: рельеф одной сеткой с вырезом под пропасть/реку, обрывы, коллизия, растительность
## и руины через MultiMesh. Подземелья: плитка Kenney (подземелье, гробница) или скалы (пещера).

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
	rng.seed = hash(data.kind) + data.w * 31 + data.h
	var w: int = data.w
	var h: int = data.h
	var grid: PackedByteArray = data.grid
	var chasm: Rect2i = data.chasm
	var kind: String = data.kind
	var env := WorldStyle.environment(sky if kind != "ruins" or sky != "day" else "sunset")
	var we := WorldEnvironment.new()
	we.environment = env[0]
	root.add_child(we)
	root.add_child(env[1])

	# --- Земля одним мешем, без клеток пропасти; за пределами сетки — продолжение рельефа
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for z in range(-MARGIN, h + MARGIN):
		var run_start := -99999
		for x in range(-MARGIN, w + MARGIN + 1):
			var solid_ground := x < w + MARGIN and not _is_chasm(grid, w, h, chasm, x, z)
			if solid_ground and run_start == -99999:
				run_start = x
			elif not solid_ground and run_start != -99999:
				_quad(st, Vector3(run_start, 0, z), Vector3(x, 0, z + 1))
				run_start = -99999
	st.generate_normals()
	var ground_mesh := st.commit()
	var mat := WorldStyle.ground_material(_biome_of(kind))
	var mask := Image.create(w, h, false, Image.FORMAT_L8)
	for y in h:
		for x in w:
			var v := grid[y * w + x]
			mask.set_pixel(x, y, Color.WHITE if v == OutdoorGenerator.PATH else Color.BLACK)
	# Маска тропы в 4× разрешении со сглаживанием — края без «ступенек»
	mask.resize(w * 4, h * 4, Image.INTERPOLATE_CUBIC)
	mat.set_shader_parameter("use_path", true)
	mat.set_shader_parameter("path_tex", ImageTexture.create_from_image(mask))
	mat.set_shader_parameter("path_rect", Vector4(0, 0, w, h))
	var gmi := MeshInstance3D.new()
	gmi.mesh = ground_mesh
	gmi.material_override = mat
	root.add_child(gmi)
	var ground_body := StaticBody3D.new()
	ground_body.collision_layer = 1
	var gcs := CollisionShape3D.new()
	gcs.shape = ground_mesh.create_trimesh_shape()
	ground_body.add_child(gcs)
	root.add_child(ground_body)

	# --- Пропасть / река
	var fall_y := SortiePlayer.FALL_Y
	if chasm.size.x > 0:
		var water: bool = data.get("water", false)
		_build_cliffs(root, chasm, h, water, rng)
		if water:
			var wmi := MeshInstance3D.new()
			var pm := PlaneMesh.new()
			pm.size = Vector2(chasm.size.x, h + MARGIN * 2)
			pm.subdivide_width = 8
			pm.subdivide_depth = 60
			wmi.mesh = pm
			wmi.material_override = WorldStyle.water_material()
			wmi.position = Vector3(chasm.position.x + chasm.size.x * 0.5, -1.0, h * 0.5)
			root.add_child(wmi)
			fall_y = -0.9
		else:
			var abyss := MeshInstance3D.new()
			var am := PlaneMesh.new()
			am.size = Vector2(chasm.size.x + 2, h + MARGIN * 2)
			abyss.mesh = am
			var amat := StandardMaterial3D.new()
			amat.albedo_color = Color("#0C0A12")
			amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			abyss.material_override = amat
			abyss.position = Vector3(chasm.position.x + chasm.size.x * 0.5, -18.0, h * 0.5)
			root.add_child(abyss)
			_mist(root, Vector3(chasm.position.x + chasm.size.x * 0.5, -6.0, h * 0.5), Vector3(chasm.size.x, 3.0, h + 20))

	# --- Стены-границы (невидимые коробки вдоль непроходимых клеток)
	var walls := StaticBody3D.new()
	walls.collision_layer = WALL_LAYER
	root.add_child(walls)
	var dist := _block_distance(grid, w, h)
	for y in h:
		for x in w:
			if grid[y * w + x] == OutdoorGenerator.BLOCK and dist[y * w + x] == 1:
				var cs := CollisionShape3D.new()
				var box := BoxShape3D.new()
				box.size = Vector3(1, 5, 1)
				cs.shape = box
				cs.position = Vector3(x + 0.5, 2.5, y + 0.5)
				walls.add_child(cs)

	# --- Поиск пути
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

	_vegetation(root, data, dist, rng)
	return {"astar": astar, "fall_y": fall_y}


static func _biome_of(kind: String) -> String:
	return {"meadow": "meadow", "forest": "forest", "riverside": "riverside", "ruins": "ruins"}.get(kind, "forest")


static func _is_chasm(grid: PackedByteArray, w: int, h: int, chasm: Rect2i, x: int, z: int) -> bool:
	if chasm.size.x > 0 and x >= chasm.position.x and x < chasm.end.x:
		return true
	if x >= 0 and z >= 0 and x < w and z < h:
		return grid[z * w + x] == OutdoorGenerator.CHASM
	return false


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3) -> void:
	var p0 := Vector3(a.x, 0, a.z)
	var p1 := Vector3(b.x, 0, a.z)
	var p2 := Vector3(b.x, 0, b.z)
	var p3 := Vector3(a.x, 0, b.z)
	for p in [p0, p1, p2, p0, p2, p3]:
		st.set_uv(Vector2(p.x, p.z))
		st.add_vertex(p)


## Обрывы по краям пропасти: вертикальные скальные стены и камни на кромке.
static func _build_cliffs(root: Node3D, chasm: Rect2i, h: int, water: bool, rng: RandomNumberGenerator) -> void:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var depth := 3.0 if water else 22.0
	for side in [0, 1]:
		var x := float(chasm.position.x if side == 0 else chasm.end.x)
		var z0 := float(-MARGIN)
		var z1 := float(h + MARGIN)
		var pts := [Vector3(x, 0, z0), Vector3(x, 0, z1), Vector3(x, -depth, z1), Vector3(x, -depth, z0)]
		var order := [0, 1, 2, 0, 2, 3] if side == 0 else [0, 2, 1, 0, 3, 2]
		for i in order:
			st.set_uv(Vector2(pts[i].z, pts[i].y))
			st.add_vertex(pts[i])
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	var m := WorldStyle.ground_material("cave")
	m.set_shader_parameter("scale", 0.35)
	mi.material_override = m
	root.add_child(mi)
	var rocks: Array = []
	for z in range(-MARGIN, h + MARGIN, 3):
		for side in [0, 1]:
			if rng.randf() < 0.55:
				var x := chasm.position.x - 0.6 if side == 0 else chasm.end.x + 0.6
				rocks.append(_xf(Vector3(x, -0.6, z + rng.randf() * 2.0), rng.randf() * TAU, rng.randf_range(0.35, 0.6)))
	scatter(root, N + "Rock_Medium_%d.gltf" % (1 + rng.randi() % 3), rocks)


static func _mist(root: Node3D, center: Vector3, extent: Vector3) -> void:
	var p := CPUParticles3D.new()
	p.position = center
	p.amount = 40
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
	mat.albedo_color = Color(0.75, 0.8, 0.9, 0.12)
	mat.albedo_texture = WorldStyle._soft_dot()
	quad.material = mat
	p.mesh = quad
	root.add_child(p)


## Расстояние (в клетках) от каждой непроходимой клетки до ближайшей проходимой (BFS).
static func _block_distance(grid: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	var queue: Array[Vector2i] = []
	for y in h:
		for x in w:
			var v := grid[y * w + x]
			if v == OutdoorGenerator.FLOOR or v == OutdoorGenerator.PATH:
				dist[y * w + x] = 0
				queue.append(Vector2i(x, y))
	var head := 0
	while head < queue.size():
		var c: Vector2i = queue[head]
		head += 1
		var d := dist[c.y * w + c.x]
		if d >= 10:
			continue
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, -1), Vector2i(1, -1), Vector2i(-1, 1)]:
			var n: Vector2i = c + o
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			var i := n.y * w + n.x
			if dist[i] == -1 and grid[i] == OutdoorGenerator.BLOCK:
				dist[i] = d + 1
				queue.append(n)
	return dist


static func _xf(pos: Vector3, yaw: float, s: float) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3.ONE * s), pos)


## Растительность и руины по типу подлокации.
static func _vegetation(root: Node3D, data: Dictionary, dist: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	var w: int = data.w
	var h: int = data.h
	var grid: PackedByteArray = data.grid
	var kind: String = data.kind
	var trees_by_model := {}
	var small_by_model := {}
	var occupied := {}
	var tree_models: Array = ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_4", "CommonTree_5", "Pine_1", "Pine_2", "Pine_3", "Pine_4", "Pine_5"]
	match kind:
		"meadow":
			tree_models = ["CommonTree_1", "CommonTree_2", "CommonTree_3", "CommonTree_5"]
		"ruins":
			tree_models = ["CommonTree_2", "DeadTree_1", "DeadTree_2", "CommonTree_4", "TwistedTree_1"]
		"riverside":
			tree_models = ["CommonTree_1", "CommonTree_3", "Pine_1", "Pine_3", "TwistedTree_2"]
	var density: float = {"forest": 0.55, "meadow": 0.32, "riverside": 0.45, "ruins": 0.35}.get(kind, 0.45)
	# Деревья по кромке и в глубине леса
	for y in h:
		for x in w:
			var d := dist[y * w + x]
			if d < 2 or d > 9:
				continue
			if rng.randf() > density * (1.2 if d <= 4 else 0.7):
				continue
			var cell := Vector2i(x / 2, y / 2)
			if occupied.has(cell):
				continue
			occupied[cell] = true
			var model: String = tree_models[rng.randi() % tree_models.size()]
			var s := rng.randf_range(0.75, 1.15) * (0.45 if model.begins_with("Twisted") else 1.0)
			if not trees_by_model.has(model):
				trees_by_model[model] = []
			trees_by_model[model].append(_xf(Vector3(x + rng.randf(), 0, y + rng.randf()), rng.randf() * TAU, s))
	# Лес за пределами сетки — силуэты до горизонта
	for i in 260:
		var p := Vector3(rng.randf_range(-MARGIN + 2, w + MARGIN - 2), 0, rng.randf_range(-MARGIN + 2, h + MARGIN - 2))
		if p.x >= -1 and p.x <= w and p.z >= -1 and p.z <= h:
			continue
		var ch: Rect2i = data.chasm
		if ch.size.x > 0 and p.x > ch.position.x - 2 and p.x < ch.end.x + 2:
			continue
		var model: String = tree_models[rng.randi() % tree_models.size()]
		if not trees_by_model.has(model):
			trees_by_model[model] = []
		trees_by_model[model].append(_xf(p, rng.randf() * TAU, rng.randf_range(0.9, 1.3) * (0.45 if model.begins_with("Twisted") else 1.0)))
	for model in trees_by_model:
		scatter(root, N + model + ".gltf", trees_by_model[model])

	# Кусты на кромке, трава и цветы на полянах
	var edge_models := ["Bush_Common", "Bush_Common_Flowers", "Fern_1", "Plant_1_Big"]
	var ground_models := ["Grass_Common_Short", "Grass_Wispy_Short", "Grass_Common_Tall", "Flower_3_Group", "Flower_4_Group", "Clover_1", "Clover_2", "Plant_7", "Pebble_Round_2", "Pebble_Square_3"]
	if kind == "forest":
		ground_models += ["Mushroom_Common", "Fern_1", "Plant_1"]
	elif kind == "meadow":
		ground_models += ["Flower_3_Single", "Flower_4_Single", "Flower_3_Group", "Flower_4_Group"]
	elif kind == "riverside":
		ground_models += ["Grass_Wispy_Tall", "Grass_Wispy_Tall", "Pebble_Round_4"]
	for y in h:
		for x in w:
			var i := y * w + x
			var v := grid[i]
			var r := rng.randf()
			if v == OutdoorGenerator.BLOCK and dist[i] == 1 and r < 0.55:
				_add(small_by_model, edge_models[rng.randi() % edge_models.size()], _xf(Vector3(x + rng.randf(), 0, y + rng.randf()), rng.randf() * TAU, rng.randf_range(0.6, 1.0)))
			elif v == OutdoorGenerator.FLOOR and r < 0.07 and not _near_entity(data, Vector2i(x, y)):
				var m: String = ground_models[rng.randi() % ground_models.size()]
				var s := 0.45 if (m.begins_with("Flower") or m.begins_with("Grass_Common_Tall")) else 0.6
				_add(small_by_model, m, _xf(Vector3(x + rng.randf(), 0, y + rng.randf()), rng.randf() * TAU, s * rng.randf_range(0.8, 1.2)))
			elif v == OutdoorGenerator.PATH and r < 0.05:
				_add(small_by_model, "RockPath_Round_Small_%d" % (1 + rng.randi() % 3), _xf(Vector3(x + 0.5, 0.0, y + 0.5), rng.randf() * TAU, rng.randf_range(0.6, 0.9)))
			elif v == OutdoorGenerator.BLOCK and dist[i] == 2 and r < 0.08:
				_add(small_by_model, "Rock_Medium_%d" % (1 + rng.randi() % 3), _xf(Vector3(x + rng.randf(), -0.2, y + rng.randf()), rng.randf() * TAU, rng.randf_range(0.5, 0.9)))
	for m in small_by_model:
		scatter(root, N + m + ".gltf", small_by_model[m], m.begins_with("Bush") or m.begins_with("Rock"))

	if kind == "ruins":
		_ruins(root, data, dist, rng)
	if kind == "forest" or kind == "riverside":
		_fireflies(root, Vector3(w * 0.5, 1.5, h * 0.5), Vector3(w, 2.5, h))


static func _add(dict: Dictionary, model: String, xf: Transform3D) -> void:
	if not dict.has(model):
		dict[model] = []
	dict[model].append(xf)


static func _near_entity(data: Dictionary, c: Vector2i) -> bool:
	if c.distance_to(data.start) < 2.5:
		return true
	for e in data.exits:
		if c.distance_to(e.cell) < 2.5:
			return true
	return false


## Руины: обломки стен и арки по краям полян, колонны, плиты, лоза, черепки.
static func _ruins(root: Node3D, data: Dictionary, dist: PackedInt32Array, rng: RandomNumberGenerator) -> void:
	var w: int = data.w
	var by_model := {}
	for c in data.clearings:
		var n := int(c.radius * 1.2)
		for i in n:
			var a := TAU * i / n + rng.randf_range(-0.15, 0.15)
			if rng.randf() < 0.35:
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
			var xf := Transform3D(Basis(Vector3.UP, yaw).scaled(Vector3(s, s * rng.randf_range(0.55, 1.0), s)), Vector3(p.x, -0.1, p.y))
			_add(by_model, model, xf)
			if rng.randf() < 0.3:
				_add(by_model, "Prop_Vine%d" % (1 + rng.randi() % 2), Transform3D(Basis(Vector3.UP, yaw), Vector3(p.x, 2.6, p.y) + Vector3(cos(a), 0, sin(a)) * -0.3))
		# Плиты пола и черепки внутри поляны
		for i in int(c.radius):
			var a := rng.randf() * TAU
			var r: float = rng.randf() * (c.radius - 1.0)
			var p: Vector2 = c.center + Vector2(cos(a), sin(a)) * r
			if _near_entity(data, Vector2i(p)):
				continue
			_add(by_model, ["Floor_UnevenBrick", "Vase_Rubble_Medium", "Prop_Brick1", "Prop_Brick2"][rng.randi() % 4],
				_xf(Vector3(p.x, 0.01, p.y), rng.randf() * TAU, 1.0))
	for m in by_model:
		var dir := V if not m.begins_with("Vase") else P
		scatter(root, dir + m + ".gltf", by_model[m])
	# Колонны Kenney
	var cols: Array = []
	for c in data.clearings:
		if rng.randf() < 0.6:
			var a := rng.randf() * TAU
			var p: Vector2 = c.center + Vector2(cos(a), sin(a)) * (c.radius - 0.8)
			if not _near_entity(data, Vector2i(p)):
				cols.append(_xf(Vector3(p.x, 0, p.y), rng.randf() * TAU, 1.6))
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
static func scatter(root: Node3D, path: String, transforms: Array, shadows: bool = true) -> void:
	if transforms.is_empty():
		return
	var sc := scene(path)
	if sc == null:
		return
	var inst: Node3D = sc.instantiate()
	for mi in inst.find_children("*", "MeshInstance3D", true, false):
		var local := MonsterRig._local_xform(inst, mi)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mi.mesh
		mm.instance_count = transforms.size()
		for i in transforms.size():
			mm.set_instance_transform(i, transforms[i] * local)
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
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
