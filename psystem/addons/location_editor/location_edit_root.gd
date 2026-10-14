@tool
class_name LocationEditRoot
extends Node3D
## Корень сцены редактирования локации (res://editor_locations/<loc>.tscn) — работает в редакторе Godot.
## Строит поверхность локации так же, как игра (OutdoorGenerator + LevelBuilder), и раскладывает объекты
## узлами-маркерами (LocationMarker): их двигают обычным гизмо Godot, дублируют Ctrl+D, удаляют Delete.
## Рельеф редактируется кистями из дока «Локации» (плагин addons/location_editor). Ctrl+S — сохранить правки
## в res://data/location_edits/<loc>.json (LocationEdits); игра применяет их при генерации.
##
## Узлы мира (рельеф, растительность, постройки) создаются при открытии и в сцену не сохраняются —
## в .tscn лежат только маркеры (и те перестраиваются из файла правок при каждом открытии).

const CHUNK := 32
const MARGIN := OutdoorGenerator.MARGIN
const KIND_NAMES := {
	"region": "Центр района", "sign": "Указатель", "island": "Остров", "cave": "Вход в пещеру", "tower": "Башня",
	"building": "Постройка", "columns": "Уступы из столбов", "chest": "Сундук", "enemy": "Враг", "boss": "Босс",
	"npc": "Житель", "safe": "Сейф", "tree": "Дерево", "pine": "Ель", "dead_tree": "Сухое дерево", "rock": "Камень", "bush": "Куст",
}
## Что можно удалить (указатели, центры районов, пещеры, острова и боссы — только двигать).
const REMOVABLE := ["tower", "building", "columns", "chest", "enemy", "npc", "safe", "tree", "pine", "dead_tree", "rock", "bush"]
const STRUCTURES := ["region", "island", "cave", "tower", "building", "columns"]
const GROUPS := {
	"region": "Районы", "sign": "Районы", "island": "Районы", "cave": "Районы",
	"tower": "Постройки", "building": "Постройки", "columns": "Постройки",
	"chest": "Сундуки", "enemy": "Враги", "boss": "Враги", "npc": "Жители", "safe": "Сундуки",
	"tree": "Растения и камни", "pine": "Растения и камни", "dead_tree": "Растения и камни", "rock": "Растения и камни", "bush": "Растения и камни",
}
const COLORS := {
	"region": Color("#FFFFFF"), "sign": Color("#FFD24A"), "island": Color("#6FB3FF"), "cave": Color("#C9A0FF"),
	"tower": Color("#E0D6C2"), "building": Color("#E8A33D"), "columns": Color("#D0C8B8"), "chest": Color("#FFC94A"),
	"enemy": Color("#FF6B6B"), "boss": Color("#FF3B5C"), "npc": Color("#7FE3C4"), "safe": Color("#7FDBFF"),
}

@export var location_id := "whisper_grove":
	set(v):
		location_id = v
		if is_inside_tree() and Engine.is_editor_hint():
			rebuild.call_deferred()

var data: Dictionary = {}
var edits: Dictionary = {}
var items: Dictionary = {}            # ключ → {kind, pos} сгенерированных объектов (для поиска удалённых)
var _base_hv := PackedFloat32Array()  # рельеф без ручных правок
var _hv := PackedFloat32Array()       # рельеф с правками (живой, для кистей)
var _vw := 0
var _vh := 0
var _world: Node3D
var _terrain: Node3D
var _chunks := {}                     # Vector2i → MeshInstance3D
var _ground_mat: Material
var _ring: MeshInstance3D
var _building := false


func _ready() -> void:
	if Engine.is_editor_hint():
		rebuild.call_deferred()


func _scene_owner() -> Node:
	return owner if owner != null else self


# ---------------------------------------------------------------- Построение

func rebuild() -> void:
	if _building or not is_inside_tree():
		return
	_building = true
	LocationEdits._cache.erase(location_id)
	LocationEdits.invalidate(location_id)
	edits = LocationEdits.load_edits(location_id)
	data = OutdoorGenerator.generate_surface(location_id)
	_vw = int(data.terrain.ew) + 1
	_vh = int(data.terrain.eh) + 1
	_hv = (data.terrain.hv as PackedFloat32Array).duplicate()
	_base_hv = _hv.duplicate()
	for k in edits.get("terrain", {}):
		var i := _vindex_key(k)
		if i >= 0:
			_base_hv[i] -= float(edits.terrain[k])
	for c in get_children():
		if c.owner == null or c is LocationMarker or c.name in GROUPS.values():
			remove_child(c)
			c.queue_free()
	_world = Node3D.new()
	_world.name = "_World"
	add_child(_world)
	LevelBuilder.build(_world, data, WorldData.location(location_id).get("sky", "day"))
	var ground := _world.find_child("Ground", false, false) as MeshInstance3D
	if ground:
		_ground_mat = ground.material_override
		ground.visible = false
	_terrain = Node3D.new()
	_terrain.name = "_Terrain"
	add_child(_terrain)
	_chunks.clear()
	for cz in ceili(float(_vh - 1) / CHUNK):
		for cx in ceili(float(_vw - 1) / CHUNK):
			_build_chunk(Vector2i(cx, cz))
	_structure_proxies()
	_build_markers()
	_ring = MeshInstance3D.new()
	_ring.name = "_BrushRing"
	_ring.visible = false
	add_child(_ring)
	_building = false
	print("Локации: %s построена — объектов %d, правок рельефа %d" % [location_id, items.size(), edits.terrain.size()])


func _vindex_key(k: String) -> int:
	var xz := k.split(",")
	var vx := int(xz[0]) + MARGIN
	var vz := int(xz[1]) + MARGIN
	if vx < 0 or vz < 0 or vx >= _vw or vz >= _vh:
		return -1
	return vz * _vw + vx


## Рельеф кусками CHUNK×CHUNK клеток: кисть перестраивает только затронутые куски.
func _build_chunk(ch: Vector2i) -> void:
	if _chunks.has(ch):
		_chunks[ch].queue_free()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var eg: PackedByteArray = data.ext.grid
	var ew: int = data.ext.ew
	var any := false
	for ez in range(ch.y * CHUNK, mini((ch.y + 1) * CHUNK, _vh - 1)):
		for ex in range(ch.x * CHUNK, mini((ch.x + 1) * CHUNK, _vw - 1)):
			if eg[ez * ew + ex] == OutdoorGenerator.CHASM:
				continue
			var x0 := ex - MARGIN
			var z0 := ez - MARGIN
			var q := [OutdoorGenerator.corner_pos(data.terrain, x0, z0), OutdoorGenerator.corner_pos(data.terrain, x0 + 1, z0),
				OutdoorGenerator.corner_pos(data.terrain, x0 + 1, z0 + 1), OutdoorGenerator.corner_pos(data.terrain, x0, z0 + 1)]
			var hs := [_hv[ez * _vw + ex], _hv[ez * _vw + ex + 1], _hv[(ez + 1) * _vw + ex + 1], _hv[(ez + 1) * _vw + ex]]
			var p: Array = []
			for k in 4:
				p.append(Vector3(q[k].x, hs[k], q[k].y))
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_uv(Vector2(p[k].x, p[k].z))
				st.add_vertex(p[k])
			any = true
	if not any:
		_chunks.erase(ch)
		return
	st.index()
	st.generate_normals()
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = _ground_mat
	_terrain.add_child(mi)
	_chunks[ch] = mi


## Высота рельефа (с живыми правками кистей).
func height_at(x: float, z: float) -> float:
	var fx := x + MARGIN
	var fz := z + MARGIN
	var ix := clampi(int(floor(fx)), 0, _vw - 2)
	var iz := clampi(int(floor(fz)), 0, _vh - 2)
	var tx := clampf(fx - ix, 0.0, 1.0)
	var tz := clampf(fz - iz, 0.0, 1.0)
	var a := lerpf(_hv[iz * _vw + ix], _hv[iz * _vw + ix + 1], tx)
	var b := lerpf(_hv[(iz + 1) * _vw + ix], _hv[(iz + 1) * _vw + ix + 1], tx)
	return lerpf(a, b, tz)


## Пересечение луча (в локальных координатах) с рельефом; Vector3.INF — мимо.
func ray_hit(origin: Vector3, dir: Vector3) -> Vector3:
	if _hv.is_empty():
		return Vector3.INF
	var o := to_local(origin)
	var d := (global_transform.basis.inverse() * dir).normalized()
	var t := 0.0
	var prev := o
	while t < 900.0:
		t += 0.5
		var p := o + d * t
		if p.y <= height_at(p.x, p.z):
			var lo := prev
			var hi := p
			for i in 12:
				var mid := (lo + hi) * 0.5
				if mid.y <= height_at(mid.x, mid.z):
					hi = mid
				else:
					lo = mid
			return hi
		prev = p
	return Vector3.INF


# ---------------------------------------------------------------- Постройки (заглушки)

## Башни, уступы и мосты в игре строит SortieWorld — здесь их упрощённые копии того же размера.
func _structure_proxies() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#B9B2A6")
	for b in data.get("bridges", []):
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b.size
		mi.mesh = bm
		mi.material_override = stone
		mi.position = b.pos - Vector3(0, b.size.y * 0.5, 0)
		mi.rotation = Vector3(b.tilt, b.yaw, 0)
		_world.add_child(mi)


func _proxy_visual(m: Node3D, kind: String, key: String) -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color("#B9B2A6")
	match kind:
		"tower":
			var cyl := CylinderMesh.new()
			cyl.top_radius = 1.5
			cyl.bottom_radius = 1.7
			cyl.height = 8.4
			_mesh(m, cyl, Vector3(0, 3.6, 0), stone)
		"columns":
			for cl in data.columns:
				if "columns:" + cl.region != key:
					continue
				var base_y := height_at(cl.center.x, cl.center.y)
				for c in cl.columns:
					var hex := CylinderMesh.new()
					hex.radial_segments = 6
					hex.rings = 1
					hex.top_radius = c.r
					hex.bottom_radius = c.r * 1.06
					hex.height = float(c.h) + 1.0
					var off: Vector2 = c.pos - cl.center
					_mesh(m, hex, Vector3(off.x, float(c.h) * 0.5 - 0.5 + (base_y - m.position.y), off.y), stone)
		"building":
			var box := BoxMesh.new()
			box.size = Vector3(6, 4, 6)
			_mesh(m, box, Vector3(0, 2, 0), _ghost(COLORS.building))
		"island":
			for ch in data.chasms:
				if "island:" + ch.region == key:
					var disc := CylinderMesh.new()
					disc.top_radius = ch.r_in
					disc.bottom_radius = ch.r_in
					disc.height = 0.3
					_mesh(m, disc, Vector3(0, 0.2, 0), _ghost(COLORS.island))
		"cave":
			var arch := BoxMesh.new()
			arch.size = Vector3(4, 4, 4)
			_mesh(m, arch, Vector3(0, 2, 0), _ghost(COLORS.cave))
		"region":
			var pole := CylinderMesh.new()
			pole.top_radius = 0.12
			pole.bottom_radius = 0.12
			pole.height = 6.0
			_mesh(m, pole, Vector3(0, 3, 0), _ghost(Color.WHITE))
		"sign":
			_post(m, COLORS.sign)
			var board := BoxMesh.new()
			board.size = Vector3(1.2, 0.4, 0.08)
			_mesh(m, board, Vector3(0, 1.7, 0), _ghost(COLORS.sign))
		"chest":
			LevelBuilder.place(m, LevelBuilder.P + "Chest_Wood.gltf", Vector3.ZERO, 0.0, 0.85)
		"enemy", "boss", "npc":
			var cap := CapsuleMesh.new()
			cap.radius = 0.45 if kind != "boss" else 0.8
			cap.height = 1.8 if kind != "boss" else 3.0
			_mesh(m, cap, Vector3(0, cap.height * 0.5, 0), _ghost(COLORS[kind]))
		"safe":
			var sbox := BoxMesh.new()
			sbox.size = Vector3(1, 1, 1)
			_mesh(m, sbox, Vector3(0, 0.5, 0), _ghost(COLORS.safe))
		_:
			var model: String = LevelBuilder.PROP_MODELS.get(kind, "")
			if model != "":
				LevelBuilder.place(m, LevelBuilder.N + model + ".gltf", Vector3.ZERO)


func _post(m: Node3D, col: Color) -> void:
	var post := BoxMesh.new()
	post.size = Vector3(0.15, 2.0, 0.15)
	_mesh(m, post, Vector3(0, 1, 0), _ghost(col))


func _mesh(parent: Node3D, mesh: Mesh, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)


func _ghost(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(col, 0.75)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# ---------------------------------------------------------------- Маркеры

func _build_markers() -> void:
	items.clear()
	var loc := WorldData.location(location_id)
	for r in data.regions:
		var rm := _marker("region:" + r.id, "region", r.center, r.name)
		var n: Dictionary = loc.nodes[r.id]
		var f: Dictionary = n.get("features", {})
		rm.region_name = n.get("name", r.id)
		rm.region_kind = n.get("kind", "meadow")
		rm.links = PackedStringArray(n.get("links", []))
		rm.chests = int(f.get("chests", 2))
		rm.enemies = int(f.get("enemies", 3))
		rm.enemy_pool = PackedStringArray(f.get("pool", []))
		rm.npcs = PackedStringArray(f.get("npcs", []))
		rm.has_safe = bool(f.get("safe", false))
		rm.island = bool(f.get("platforms", false))
		rm.riddle_gate = bool(f.get("riddle_gate", false))
		rm.boss = String(f.get("boss", ""))
	for sg in data.signposts:
		_marker("sign:" + sg.region, "sign", Vector2(sg.cell) + Vector2(0.5, 0.5), sg.name)
	for ch in data.chasms:
		_marker("island:" + ch.region, "island", ch.center, "Остров")
	for cv in data.caves:
		_marker("cave:" + cv.region + ":" + cv.to, "cave", cv.get("mound", Vector2(cv.cell)), cv.to_name)
	for v in data.vertical:
		_marker("tower:" + v.region, "tower", v.center, "Башня")
	for b in data.buildings:
		if b.type != "fence":
			_marker("building:" + b.region, "building", b.center, "Постройка")
	for cl in data.columns:
		_marker("columns:" + cl.region, "columns", cl.center, "Уступы")
	for list_key in ["chests", "enemies", "npcs", "safes", "bosses"]:
		var kind: String = {"chests": "chest", "enemies": "enemy", "npcs": "npc", "safes": "safe", "bosses": "boss"}[list_key]
		for e in data[list_key]:
			var label: String = KIND_NAMES[kind]
			if kind in ["enemy", "boss"]:
				label = _enemy_name(e.id)
			var mk := _marker(OutdoorGenerator.entity_key(list_key, e), kind, Vector2(e.cell) + Vector2(0.5, 0.5), label)
			if kind == "enemy":
				mk.enemy_id = e.id
	for p in data.get("props", []):
		_marker(p.key, p.type, p.pos, KIND_NAMES.get(p.type, p.type))


func _group(kind: String) -> Node3D:
	var gname: String = GROUPS.get(kind, "Прочее")
	var g := get_node_or_null(gname) as Node3D
	if g == null:
		g = Node3D.new()
		g.name = gname
		add_child(g)
		g.owner = _scene_owner()
	return g


func _marker(key: String, kind: String, pos: Vector2, label: String) -> LocationMarker:
	items[key] = {"kind": kind, "pos": pos}
	var m := LocationMarker.new()
	m.key = key
	m.kind = kind
	m.label_text = label
	m.name = (KIND_NAMES.get(kind, kind) + " " + label if label != KIND_NAMES.get(kind, kind) else KIND_NAMES.get(kind, kind)).validate_node_name()
	m.position = Vector3(pos.x, height_at(pos.x, pos.y), pos.y)
	_group(kind).add_child(m, true)
	m.owner = _scene_owner()
	decorate(m)
	return m


## Визуал маркера (не сохраняется в сцену): модель или заглушка и подпись.
func decorate(m: LocationMarker) -> void:
	for c in m.get_children():
		if c.owner == null:
			c.queue_free()
	_proxy_visual(m, m.kind, m.key)
	var l := Label3D.new()
	l.text = m.label_text if m.kind != "enemy" or m.enemy_id == "" else _enemy_name(m.enemy_id)
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = true
	l.fixed_size = true
	l.pixel_size = 0.0012
	l.font_size = 22 if m.kind == "region" else 16
	l.outline_size = 6
	l.modulate = COLORS.get(m.kind, Color("#D8F0C8"))
	l.position.y = {"region": 6.6, "tower": 9.0, "columns": 7.0, "building": 4.6, "boss": 3.4}.get(m.kind, 2.2)
	m.add_child(l)


static func _enemy_name(enemy_id: String) -> String:
	for e in CardDatabase.all_enemies():
		if e.id == enemy_id:
			return e.get("name", enemy_id)
	return enemy_id


func markers() -> Array:
	var out: Array = []
	for g in get_children():
		for c in g.get_children():
			if c is LocationMarker:
				out.append(c)
	return out


## Новый объект (сундук, враг, дерево…) в точке рельефа. Ключ назначается при сохранении.
func new_marker(kind: String, pos: Vector2, enemy_id: String = "") -> LocationMarker:
	var m := LocationMarker.new()
	m.kind = kind
	m.enemy_id = enemy_id
	m.label_text = _enemy_name(enemy_id) if kind == "enemy" else KIND_NAMES.get(kind, kind)
	m.name = ("Новый " + String(KIND_NAMES.get(kind, kind)).to_lower()).validate_node_name()
	m.position = Vector3(pos.x, height_at(pos.x, pos.y), pos.y)
	return m


# ---------------------------------------------------------------- Сохранение

## Собрать правки из маркеров и записать файл. Перемещённые постройки и районы меняют рельеф
## (площадки, дороги) — тогда сцена перестраивается.
func save_edits() -> bool:
	if data.is_empty():
		return false
	var before := JSON.stringify(edits.get("objects", {}))
	var seen := {}
	var structural_moved := false
	var added_keys := {}
	for a in edits.added:
		added_keys[a.key] = a
	var next_add: int = int(edits.get("next_add", edits.added.size()))
	for m in markers():
		var p := Vector2(m.position.x, m.position.z)
		if m.key == "" or seen.has(m.key):
			# Новый объект или копия (Ctrl+D) — добавленный вручную
			var copy_of: String = m.kind
			m.key = "add:%d" % next_add
			next_add += 1
			var entry := {"key": m.key, "type": copy_of, "pos": [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]}
			if copy_of == "enemy":
				entry["enemy"] = m.enemy_id
			if copy_of in LevelBuilder.PROP_MODELS:
				entry["yaw"] = snappedf(m.rotation.y, 0.01)
				entry["scale"] = snappedf(m.scale.x, 0.01)
			if copy_of in ["chest", "enemy"] or copy_of in LevelBuilder.PROP_MODELS:
				edits.added.append(entry)
				added_keys[m.key] = entry
			else:
				push_warning("Локации: «%s» нельзя размножить — копия не сохранится" % m.name)
				m.key = ""
				continue
		seen[m.key] = true
		if added_keys.has(m.key):
			var a: Dictionary = added_keys[m.key]
			a.pos = [snappedf(p.x, 0.01), snappedf(p.y, 0.01)]
			if m.kind == "enemy":
				a["enemy"] = m.enemy_id
			if m.kind in LevelBuilder.PROP_MODELS:
				a["yaw"] = snappedf(m.rotation.y, 0.01)
				a["scale"] = snappedf(m.scale.x, 0.01)
			continue
		var old: Vector2 = items.get(m.key, {}).get("pos", p)
		if m.kind in STRUCTURES and old.distance_to(p) > 0.05:
			structural_moved = true
		LocationEdits.set_pos(edits, m.key, p)
		var o: Dictionary = edits.objects[m.key]
		o.erase("removed")
		if m.kind == "enemy" and m.enemy_id != "":
			o["id"] = m.enemy_id
	edits["next_add"] = next_add
	# Удалённые: сгенерированные объекты без маркера
	for key in items:
		if seen.has(key):
			continue
		if key.begins_with("add:"):
			edits.added = edits.added.filter(func(a): return a.key != key)
			edits.objects.erase(key)
		elif items[key].kind in REMOVABLE:
			LocationEdits.set_removed(edits, key, true)
		else:
			push_warning("Локации: «%s» нельзя удалить (только переместить) — он вернётся" % key)
	edits["pinned"] = true
	var ok := LocationEdits.save_edits(location_id, edits)
	# Свойства районов (Инспектор центра района) — в data/locations.json
	var data_changed := false
	for m in markers():
		if m.kind != "region":
			continue
		var rid: String = m.key.trim_prefix("region:")
		var features := {"chests": m.chests, "enemies": m.enemies, "pool": Array(m.enemy_pool), "npcs": Array(m.npcs),
			"safe": m.has_safe, "platforms": m.island, "riddle_gate": m.riddle_gate, "boss": m.boss}
		if LocationDataFile.update_node(location_id, rid, {"name": m.region_name, "kind": m.region_kind, "links": Array(m.links), "features": features}):
			data_changed = true
	if data_changed:
		OutdoorGenerator.invalidate(location_id)
	if structural_moved or data_changed or _removed_changed(before):
		rebuild.call_deferred()
	else:
		for m in markers():
			m.position.y = height_at(m.position.x, m.position.z)
			items[m.key] = {"kind": m.kind, "pos": Vector2(m.position.x, m.position.z)}
	return ok


func _removed_changed(before_json: String) -> bool:
	var before = JSON.parse_string(before_json)
	for key in edits.objects:
		var was: bool = before is Dictionary and before.get(key, {}).get("removed", false)
		if bool(edits.objects[key].get("removed", false)) != was:
			return true
	return false


func reset_edits() -> void:
	LocationEdits.save_edits(location_id, LocationEdits.empty())
	rebuild()


# ---------------------------------------------------------------- Кисти

func terrain_snapshot() -> Dictionary:
	return {"terrain": edits.get("terrain", {}).duplicate(), "clear": edits.get("clear", {}).duplicate()}


## Вернуть рельеф и растительность к снимку (отмена/повтор кисти).
func restore_terrain(snap: Dictionary) -> void:
	edits.terrain = snap.terrain.duplicate()
	edits.clear = snap.clear.duplicate()
	_hv = _base_hv.duplicate()
	for k in edits.terrain:
		var i := _vindex_key(k)
		if i >= 0:
			_hv[i] += float(edits.terrain[k])
	for ch in _chunks.keys():
		_build_chunk(ch)
	LocationEdits.save_edits(location_id, edits)
	_snap_markers()


## Мазок кисти в точке c (метры) — tool: raise | lower | flatten | smooth | clear_veg | restore_veg.
func apply_brush(tool: String, c: Vector2, radius: float, strength: float, dt: float, level: float) -> void:
	if tool in ["clear_veg", "restore_veg"]:
		for z in range(int(c.y - radius), int(c.y + radius) + 1):
			for x in range(int(c.x - radius), int(c.x + radius) + 1):
				if Vector2(x + 0.5, z + 0.5).distance_to(c) <= radius and x >= 0 and z >= 0 and x < int(data.w) and z < int(data.h):
					if tool == "clear_veg":
						edits.clear["%d,%d" % [x, z]] = true
					else:
						edits.clear.erase("%d,%d" % [x, z])
		return
	var dirty := {}
	for z in range(int(c.y - radius) - 1, int(c.y + radius) + 2):
		for x in range(int(c.x - radius) - 1, int(c.x + radius) + 2):
			var d := Vector2(x, z).distance_to(c)
			if d > radius:
				continue
			var vx := x + MARGIN
			var vz := z + MARGIN
			if vx < 0 or vz < 0 or vx >= _vw or vz >= _vh:
				continue
			var f := pow(1.0 - d / radius, 1.6)
			var i := vz * _vw + vx
			var cur := _hv[i]
			var change := 0.0
			match tool:
				"raise":
					change = strength * 1.5 * dt * f
				"lower":
					change = -strength * 1.5 * dt * f
				"flatten":
					change = (level - cur) * minf(1.0, strength * 3.0 * dt * f)
				"smooth":
					var avg := (_hv[i - 1] + _hv[i + 1] + _hv[i - _vw] + _hv[i + _vw]) * 0.25 if vx > 0 and vz > 0 and vx < _vw - 1 and vz < _vh - 1 else cur
					change = (avg - cur) * minf(1.0, strength * 3.0 * dt * f)
			if absf(change) < 0.0001:
				continue
			_hv[i] += change
			var key := "%d,%d" % [x, z]
			var total := snappedf(float(edits.terrain.get(key, 0.0)) + change, 0.001)
			if absf(total) < 0.002:
				edits.terrain.erase(key)
			else:
				edits.terrain[key] = total
			dirty[Vector2i(vx / CHUNK, vz / CHUNK)] = true
			# Вершина на границе куска есть и у соседнего
			dirty[Vector2i((vx - 1) / CHUNK, (vz - 1) / CHUNK)] = true
	for ch in dirty:
		if ch.x >= 0 and ch.y >= 0:
			_build_chunk(ch)


func _snap_markers() -> void:
	for m in markers():
		m.position.y = height_at(m.position.x, m.position.z)


func end_stroke() -> void:
	_snap_markers()
	LocationEdits.save_edits(location_id, edits)


## Кольцо кисти на рельефе.
func show_ring(center: Vector3, radius: float, color: Color) -> void:
	if _ring == null:
		return
	if center == Vector3.INF:
		_ring.visible = false
		return
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	mat.no_depth_test = true
	for r in [radius, radius * 0.5]:
		im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP, mat)
		for k in 49:
			var a := TAU * k / 48.0
			var x: float = center.x + cos(a) * r
			var z: float = center.z + sin(a) * r
			im.surface_add_vertex(Vector3(x, height_at(x, z) + 0.15, z))
		im.surface_end()
	_ring.mesh = im
	_ring.visible = true
