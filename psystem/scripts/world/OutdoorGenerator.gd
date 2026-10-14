class_name OutdoorGenerator
extends RefCounted
## Единая поверхность локации в духе Gothic: открытая долина с плавными холмами, окружённая горами.
## Наземные подлокации — районы этой долины: у каждого своя высота, ориентир (хутор, лагерь охотников,
## руины), полуразрушенная башня с винтовой лестницей (провалы — перепрыгнуть) и сундуком наверху,
## уступы из каменных столбов (паркур к сундуку на вершине), указатель — точка быстрого перемещения.
## Районы соединены дорогами. Пещеры, гробницы и подземелья — отдельные уровни: вход — проём в скальном
## холме. Район с features.platforms — остров посреди озера или провала, туда ведёт разрушенный каменный
## мост (пролёты с провалами — прыгать). Только данные — 3D строит LevelBuilder, карта локации рисует по ним топографию.
##
## Сетка 1 клетка = 1 м: 0 — непроходимо (слишком крутой склон: горы по краю, скальные холмы),
## 1 — земля, 2 — дорога, 3 — провал или вода. Проходимость определяется уклоном рельефа.

const BLOCK := 0
const FLOOR := 1
const PATH := 2
const CHASM := 3

const W := 232
const H := 140
const MARGIN := 34
## Перепад высот в углах клетки, выше которого она непроходима (~42°).
const STEEP := 0.9
## Ширина гор по краю долины.
const RIM := 9.0

static var _cache: Dictionary = {}


## Сбросить кэш поверхности (после правок в редакторе локаций).
static func invalidate(loc_id: String) -> void:
	for k in _cache.keys():
		if String(k).begins_with(loc_id + "/"):
			_cache.erase(k)


static func generate_surface(loc_id: String) -> Dictionary:
	var key := loc_id + "/" + Loc.lang()
	if _cache.has(key):
		return _cache[key]
	var loc := WorldData.location(loc_id)
	# Ручные правки из редактора локаций: положения объектов, удаления, добавления, рельеф
	var edits := LocationEdits.load_edits(loc_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(loc_id)) % 1000003
	var data := {
		"w": W, "h": H, "kind": loc.get("biome", "forest"), "underground": false, "surface": true, "location_id": loc_id,
		"regions": [], "clearings": [], "chests": [], "enemies": [], "bosses": [], "npcs": [], "safes": [],
		"signposts": [], "caves": [], "platforms": [], "chasms": [], "vertical": [], "rocks": [], "mesas": [],
		"buildings": [], "roads": [], "stamps": [], "pads": [], "columns": [], "bridges": [], "start": Vector2i.ZERO,
		"water": false, "exits": [], "props": [], "veg_clear": edits.get("clear", {}), "edits": edits,
	}

	# --- Районы: центры по положению подлокаций на карте локации
	var regions: Array = []
	var by_id := {}
	for id in loc.order:
		var n: Dictionary = loc.nodes[id]
		if WorldData.is_underground(n):
			continue
		var c := Vector2(30.0 + float(n.pos[0]) * (W - 60), 26.0 + float(n.pos[1]) * (H - 52))
		c = LocationEdits.pos_of(edits, "region:" + id, c)
		var r := {"id": id, "name": n.get("name", id), "kind": n.get("kind", "meadow"), "center": c, "radius": 22.0,
			"elev": 0.0 if n.get("start", false) else rng.randf_range(0.5, 5.0), "features": n.get("features", {}),
			"dirs": []}
		regions.append(r)
		by_id[id] = r
	data.regions = regions

	# --- Дороги между связанными районами (плавные кривые)
	var done := {}
	for r in regions:
		for link in loc.nodes[r.id].get("links", []):
			if not by_id.has(link):
				continue
			var pair: String = r.id + ">" + link if r.id < link else link + ">" + r.id
			if done.has(pair):
				continue
			done[pair] = true
			var o: Dictionary = by_id[link]
			var a: Vector2 = r.center
			var b: Vector2 = o.center
			var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * a.distance_to(b) * rng.randf_range(-0.18, 0.18)
			var pts := PackedVector2Array()
			var steps := int(a.distance_to(b) / 2.0) + 2
			for i in steps + 1:
				var t := float(i) / steps
				pts.append(a.lerp(mid, t).lerp(mid.lerp(b, t), t))
			data.roads.append(pts)
			r.dirs.append((b - a).normalized())
			o.dirs.append((a - b).normalized())

	# --- Острова (features.platforms): озеро (берег реки) или провал вокруг, в стороне от дорог
	for r in regions:
		if not r.features.get("platforms", false):
			continue
		var center: Vector2 = _spot(data, r, rng, 21.0, 25.0, 13.5)
		center.x = clampf(center.x, RIM + 18, W - RIM - 18)
		center.y = clampf(center.y, RIM + 18, H - RIM - 18)
		center = LocationEdits.pos_of(edits, "island:" + r.id, center)
		var dir: Vector2 = (center - r.center).normalized()
		var water: bool = r.kind == "riverside"
		data.chasms.append({"center": center, "r_in": 6.5, "r_out": 13.5, "water": water, "region": r.id,
			"level": r.elev, "rect": Rect2i(int(center.x - 14), int(center.y - 14), 29, 29), "dir": dir})
		if water:
			data.water = true

	# --- Входы в пещеры: скальный холм в стороне от дорог, проём у подножия лицом к району
	for r in regions:
		var sealed_done := false
		for link in loc.nodes[r.id].get("links", []):
			var un: Dictionary = loc.nodes.get(link, {})
			if un.is_empty() or not WorldData.is_underground(un):
				continue
			var want: Vector2 = (Vector2(un.pos[0], un.pos[1]) - Vector2(loc.nodes[r.id].pos[0], loc.nodes[r.id].pos[1])).normalized()
			var mound: Vector2 = LocationEdits.pos_of(edits, "cave:" + r.id + ":" + link, _spot(data, r, rng, 23.0, 27.0, 7.5, want))
			var dir: Vector2 = (mound - r.center).normalized()
			mound.x = clampf(mound.x, RIM + 10, W - RIM - 10)
			mound.y = clampf(mound.y, RIM + 10, H - RIM - 10)
			data.stamps.append({"kind": "mound", "center": mound, "radius": 7.5, "height": 7.5})
			var mouth: Vector2 = mound - dir * 7.6
			var cave := {"to": link, "to_name": un.get("name", link), "to_kind": un.get("kind", "cave"), "region": r.id, "mound": mound,
				"cell": Vector2i(mouth), "dir": dir, "arrive": Vector2i(mouth - dir * 4.0), "kind": _cave_kind(un.get("kind", "cave")),
				"sealed": false, "riddle_id": ""}
			if r.features.get("riddle_gate", false) and not sealed_done:
				cave.sealed = true
				cave.riddle_id = _pick_riddle(rng, {})
				sealed_done = true
			data.caves.append(cave)
			# Тропинка от центра района ко входу
			var pts := PackedVector2Array()
			for i in 12:
				pts.append(r.center.lerp(mouth - dir * 1.0, float(i) / 11.0))
			data.roads.append(pts)

	# --- Ориентиры районов: постройки на выровненных площадках, вышка/башня, валуны
	for r in regions:
		var hub: Vector2 = r.center
		r.hub = hub
		data.clearings.append({"center": hub, "radius": 10.0, "region": r.id, "side": 0, "id": data.clearings.size()})
		var kind: String = r.kind
		# Полуразрушенная башня с винтовой лестницей (часть ступеней обвалилась), наверху сундук
		var tower_c: Vector2 = LocationEdits.pos_of(edits, "tower:" + r.id, _spot(data, r, rng, 11.0, 15.0, 5.0))
		var steps := 16
		var missing: Array = []
		for k in range(3, steps - 2):
			if rng.randf() < 0.22 and not (k - 1) in missing:
				missing.append(k)
		var tower_yaw := rng.randf() * TAU
		if not LocationEdits.is_removed(edits, "tower:" + r.id):
			data.vertical.append({"type": "spiral", "center": tower_c, "yaw": tower_yaw, "height": 7.2,
				"steps": steps, "missing": missing, "region": r.id})
			data.pads.append({"center": tower_c, "radius": 5.0})
		# Постройки ориентира
		var bc: Vector2 = LocationEdits.pos_of(edits, "building:" + r.id, _spot(data, r, rng, 9.0, 12.0, 6.0))
		var b_dir: Vector2 = (bc - hub).normalized()
		var b_kind: String = kind if not LocationEdits.is_removed(edits, "building:" + r.id) else ""
		match b_kind:
			"meadow", "riverside":
				data.buildings.append({"type": "hut", "center": bc, "yaw": atan2(-b_dir.x, -b_dir.y), "region": r.id})
				data.buildings.append({"type": "fence", "center": bc + b_dir * 5.5, "yaw": atan2(-b_dir.x, -b_dir.y), "region": r.id})
				data.pads.append({"center": bc, "radius": 5.0})
			"forest":
				data.buildings.append({"type": "camp", "center": bc, "yaw": rng.randf() * TAU, "region": r.id})
				data.pads.append({"center": bc, "radius": 4.0})
			"ruins":
				data.buildings.append({"type": "ruins", "center": bc, "yaw": rng.randf() * TAU, "region": r.id})
				data.pads.append({"center": bc, "radius": 5.0})
		# Уступы из каменных столбов: запрыгивай выше и выше — на вершине сундук
		var cc: Vector2 = LocationEdits.pos_of(edits, "columns:" + r.id, _spot(data, r, rng, 14.0, 19.0, 5.5))
		var cluster := _column_cluster(cc, rng, r.id)
		if not LocationEdits.is_removed(edits, "columns:" + r.id):
			data.columns.append(cluster)
			data.pads.append({"center": cc, "radius": 5.5})

	# --- Рельеф и проходимость
	_build_terrain(data, rng)

	# --- Указатели, жители, сундуки, сейфы, враги, боссы
	var occupied := {}
	for v in data.vertical:
		_occupy(occupied, v.center, 3.5)
		# Лестница и место перед ней
		var sd := Vector2(sin(v.yaw), cos(v.yaw))
		for k in range(2, 13):
			_occupy(occupied, v.center + sd * k, 1.6)
	for b in data.buildings:
		_occupy(occupied, b.center, 4.0)
	for cl in data.columns:
		_occupy(occupied, cl.center, 5.5)
	for c in data.caves:
		_occupy(occupied, Vector2(c.cell), 2.5)
	var used := {"safes": []}
	for r in regions:
		var hub: Dictionary = {"center": r.hub, "radius": 8.0}
		var area: Dictionary = {"center": r.center, "radius": 20.0}
		var spot := _free_cell(data, hub, rng, occupied)
		_occupy(occupied, Vector2(spot), 1.5)
		var arrive := _free_cell(data, {"center": Vector2(spot) + Vector2(0, 2.5), "radius": 1.5}, rng, occupied)
		data.signposts.append({"region": r.id, "name": r.name, "cell": spot, "arrive": arrive})
		if loc.nodes[r.id].get("start", false):
			data.start = arrive
		var f: Dictionary = r.features
		for npc in f.get("npcs", []):
			data.npcs.append({"id": npc, "cell": _free_cell(data, hub, rng, occupied), "region": r.id})
		for i in int(f.get("chests", 2)):
			data.chests.append({"cell": _free_cell(data, area, rng, occupied), "region": r.id, "index": i})
		if f.get("safe", false):
			var sid := _pick_safe(rng, used)
			used.safes.append(sid)
			data.safes.append({"id": sid, "cell": _free_cell(data, hub, rng, occupied), "region": r.id, "reward": "loot"})
		var pool: Array = f.get("pool", ["syntax_error"])
		for i in int(f.get("enemies", 3)):
			var c := _free_cell(data, {"center": r.center, "radius": 21.0}, rng, occupied, 9.0)
			data.enemies.append({"id": pool[rng.randi() % pool.size()], "cell": c, "area": Rect2i(c - Vector2i(5, 5), Vector2i(10, 10)),
				"region": r.id, "index": i})
		if f.has("boss"):
			var island: Array = data.chasms.filter(func(ch): return ch.region == r.id)
			var bc: Vector2 = island[0].center if not island.is_empty() else r.center + _free_direction(r.dirs, rng) * 17.0
			var cell := _free_cell(data, {"center": bc, "radius": 3.0}, rng, occupied)
			data.bosses.append({"id": f.boss, "cell": cell, "area": Rect2i(cell - Vector2i(4, 4), Vector2i(8, 8)), "region": r.id})
	_roaming_enemies(data, rng, occupied, loc)
	_apply_entity_edits(data, edits, loc)
	_cache[key] = data
	return data


## Правки сущностей (после всей генерации, чтобы не сбивать случайную раскладку остального):
## перемещения, удаления и добавленные вручную сундуки, враги, деревья, камни.
static func _apply_entity_edits(data: Dictionary, edits: Dictionary, loc: Dictionary) -> void:
	for sg in data.signposts:
		var nc := _edit_cell(edits, "sign:" + sg.region, sg.cell)
		var shift: Vector2i = nc - Vector2i(sg.cell)
		if shift != Vector2i.ZERO:
			var was_start: bool = data.start == sg.arrive
			sg.cell = nc
			sg.arrive = Vector2i(sg.arrive) + shift
			if was_start:
				data.start = sg.arrive
	for list_key in ["chests", "enemies", "npcs", "safes", "bosses"]:
		var kept: Array = []
		for e in data[list_key]:
			var key := entity_key(list_key, e)
			if LocationEdits.is_removed(edits, key) and list_key != "bosses":
				continue
			var nc := _edit_cell(edits, key, e.cell)
			var new_id: String = edits.get("objects", {}).get(key, {}).get("id", "")
			if new_id != "" and list_key == "enemies":
				e.id = new_id
			if nc != Vector2i(e.cell):
				if e.has("area"):
					var a: Rect2i = e.area
					e.area = Rect2i(nc - a.size / 2, a.size)
				e.cell = nc
			kept.append(e)
		data[list_key] = kept
	for i in edits.get("added", []).size():
		var a: Dictionary = edits.added[i]
		var key: String = a.get("key", "add:%d" % i)
		if LocationEdits.is_removed(edits, key):
			continue
		var p := LocationEdits.pos_of(edits, key, Vector2(float(a.pos[0]), float(a.pos[1])))
		var cell := Vector2i(clampi(int(floor(p.x)), 1, W - 2), clampi(int(floor(p.y)), 1, H - 2))
		var rid := region_at(data, p)
		var idx := 1000 + int(key.get_slice(":", 1))
		match String(a.type):
			"chest":
				data.chests.append({"cell": cell, "region": rid, "index": idx, "key": key})
			"enemy":
				var pool: Array = loc.nodes[rid].get("features", {}).get("pool", ["syntax_error"])
				var eid: String = a.get("enemy", "")
				if eid == "":
					eid = pool[0]
				data.enemies.append({"id": eid, "cell": cell, "area": Rect2i(cell - Vector2i(5, 5), Vector2i(10, 10)),
					"region": rid, "index": idx, "key": key})
			_:
				data.props.append({"type": a.type, "pos": p, "key": key, "yaw": float(a.get("yaw", float(idx) * 2.4)),
					"scale": float(a.get("scale", 1.0))})


static func _edit_cell(edits: Dictionary, key: String, cell: Vector2i) -> Vector2i:
	var p := LocationEdits.pos_of(edits, key, Vector2(cell) + Vector2(0.5, 0.5))
	return Vector2i(clampi(int(floor(p.x)), 1, W - 2), clampi(int(floor(p.y)), 1, H - 2))


## Ключ сущности в правках редактора.
static func entity_key(list_key: String, e: Dictionary) -> String:
	if e.has("key"):
		return e.key
	match list_key:
		"chests":
			return "chest:%s:%d" % [e.region, int(e.index)]
		"enemies":
			return "enemy:%s:%d" % [e.region, int(e.index)]
		"npcs":
			return "npc:%s:%s" % [e.region, e.id]
		"safes":
			return "safe:%s" % e.region
		"bosses":
			return "boss:%s" % e.region
	return ""


## Бродячие враги по всей долине: между районами не должно быть пустых территорий.
## Сетка с шагом ROAM_STEP, точка — на проходимой клетке не ближе ROAM_GAP к другим врагам и не у старта;
## враг принадлежит ближайшему району (его пул и счёт побед), изредка — парой.
const ROAM_STEP := 20.0
const ROAM_GAP := 13.0


static func _roaming_enemies(data: Dictionary, rng: RandomNumberGenerator, occupied: Dictionary, loc: Dictionary) -> void:
	var by_region := {}
	for e in data.enemies:
		by_region[e.region] = maxi(by_region.get(e.region, 0), int(e.index) + 1)
	var start := Vector2(data.start)
	var y := RIM + ROAM_STEP * 0.5
	while y < H - RIM:
		var x := RIM + ROAM_STEP * 0.5
		while x < W - RIM:
			var p := Vector2(x, y) + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6))
			x += ROAM_STEP
			if p.distance_to(start) < 16.0:
				continue
			var cell := _free_cell(data, {"center": p, "radius": 5.0}, rng, occupied)
			if data.grid[cell.y * W + cell.x] == BLOCK or data.grid[cell.y * W + cell.x] == CHASM:
				continue
			var near := false
			for e in data.enemies:
				if Vector2(cell).distance_to(Vector2(e.cell)) < ROAM_GAP:
					near = true
					break
			for sg in data.signposts:
				if Vector2(cell).distance_to(Vector2(sg.cell)) < 7.0:
					near = true
			if near:
				continue
			var rid := region_at(data, Vector2(cell))
			var pool: Array = loc.nodes[rid].get("features", {}).get("pool", ["syntax_error"])
			var pack := 2 if rng.randf() < 0.3 else 1
			for k in pack:
				var c := cell if k == 0 else _free_cell(data, {"center": Vector2(cell), "radius": 2.5}, rng, occupied, 1.5)
				var idx: int = by_region.get(rid, 0)
				by_region[rid] = idx + 1
				data.enemies.append({"id": pool[rng.randi() % pool.size()], "cell": c,
					"area": Rect2i(c - Vector2i(6, 6), Vector2i(12, 12)), "region": rid, "index": idx, "roaming": true})
		y += ROAM_STEP


## Скопление каменных столбов: путь из столбов, каждый выше предыдущего на ~0.9 м (прыжок поднимает
## на 1.17 м), на вершине — площадка из трёх столбов с сундуком; вокруг — низкие столбы для вида.
static func _column_cluster(center: Vector2, rng: RandomNumberGenerator, region: String) -> Dictionary:
	var path: Array = []
	var a := rng.randf() * TAU
	var rad := 3.6
	var h := 0.0
	for k in 5:
		h += 0.88
		path.append({"pos": center + Vector2(cos(a), sin(a)) * rad, "h": h, "r": rng.randf_range(0.8, 0.95)})
		a += rng.randf_range(0.5, 0.62)
		rad = maxf(rad - 0.45, 1.6)
	var top := h + 0.88
	# Вершина — дальше по ходу, не перекрывая последний уступ
	var last: Vector2 = path[-1].pos
	var prev: Vector2 = path[-2].pos
	var ahead := (last - prev).normalized()
	var summit: Vector2 = last + ahead.rotated(0.35) * 2.3
	var cols: Array = path.duplicate()
	cols.append({"pos": summit, "h": top, "r": 1.15})
	cols.append({"pos": summit + ahead.rotated(1.2) * 1.6, "h": top - rng.randf_range(0.0, 0.3), "r": 0.9})
	var deco: Array = []
	for k in 7:
		var b := rng.randf() * TAU
		var p: Vector2 = center + Vector2(cos(b), sin(b)) * rng.randf_range(3.8, 5.2)
		var ok := true
		for c in cols:
			if p.distance_to(c.pos) < 1.7:
				ok = false
		if ok:
			deco.append({"pos": p, "h": rng.randf_range(0.3, 1.1), "r": rng.randf_range(0.6, 0.9)})
	return {"center": center, "path": path, "summit": summit, "top": top, "columns": cols + deco, "region": region}


## Место для объекта района радиуса radius на расстоянии dmin..dmax от центра: не пересекает провалы, холмы
## пещер, площадки построек, дороги и центры других районов; из подходящих — направление дальше всего от занятых.
## Направление записывается в r.dirs. Если места нет — просто свободное направление.
static func _spot(data: Dictionary, r: Dictionary, rng: RandomNumberGenerator, dmin: float, dmax: float, radius: float,
		want: Vector2 = Vector2.ZERO) -> Vector2:
	var best := Vector2.INF
	var best_score := -INF
	var best_dir := Vector2.ZERO
	for k in 36:
		var a := TAU * k / 36.0 + rng.randf() * 0.08
		var d := Vector2(cos(a), sin(a))
		for dist in [dmin, (dmin + dmax) * 0.5, dmax]:
			var p: Vector2 = r.center + d * dist
			if p.x < RIM + radius + 3 or p.y < RIM + radius + 3 or p.x > W - RIM - radius - 3 or p.y > H - RIM - radius - 3:
				continue
			if not _spot_free(data, r, p, radius):
				continue
			var score := PI
			for u in r.dirs:
				score = minf(score, absf(d.angle_to(u)))
			score -= absf(dist - (dmin + dmax) * 0.5) * 0.01
			if want != Vector2.ZERO:
				score += d.dot(want) * 0.6
			if score > best_score:
				best_score = score
				best = p
				best_dir = d
	if best == Vector2.INF:
		best_dir = _free_direction(r.dirs, rng, want)
		best = r.center + best_dir * (dmin + dmax) * 0.5
	r.dirs.append(best_dir)
	return best


static func _spot_free(data: Dictionary, r: Dictionary, p: Vector2, radius: float) -> bool:
	for ch in data.chasms:
		if p.distance_to(ch.center) < float(ch.r_out) + radius + 2.0:
			return false
	for st in data.stamps:
		if p.distance_to(st.center) < float(st.radius) + radius + 2.0:
			return false
	for pad in data.pads:
		if p.distance_to(pad.center) < float(pad.radius) + radius + 1.5:
			return false
	for o in data.regions:
		if o != r and p.distance_to(o.center) < radius + 12.0:
			return false
	for pts in data.roads:
		for q in pts:
			if p.distance_to(q) < radius + 2.0:
				return false
	return true


## Направление от центра района, наиболее удалённое от уже занятых (дорог, построек); want — желаемое.
static func _free_direction(used: Array, rng: RandomNumberGenerator, want: Vector2 = Vector2.ZERO) -> Vector2:
	var best := Vector2.RIGHT
	var best_score := -INF
	for k in 24:
		var a := TAU * k / 24.0 + rng.randf() * 0.1
		var d := Vector2(cos(a), sin(a))
		var score := PI
		for u in used:
			score = minf(score, absf(d.angle_to(u)))
		if want != Vector2.ZERO:
			score += d.dot(want) * 0.6
		if score > best_score:
			best_score = score
			best = d
	return best


static func _occupy(occupied: Dictionary, center: Vector2, radius: float) -> void:
	for y in range(int(center.y - radius) - 1, int(center.y + radius) + 2):
		for x in range(int(center.x - radius) - 1, int(center.x + radius) + 2):
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				occupied[Vector2i(x, y)] = true


static func _cave_kind(kind: String) -> String:
	return "crypt" if kind == "tomb" else ("stairs_down" if kind == "dungeon" else "cave")


# ---------------------------------------------------------------- Рельеф

## Высоты вершин (с полями MARGIN — горы уходят за край), затем проходимость клеток по уклону.
static func _build_terrain(data: Dictionary, rng: RandomNumberGenerator) -> void:
	var ew := W + MARGIN * 2
	var eh := H + MARGIN * 2
	var vw := ew + 1
	var vh := eh + 1
	var hills := FastNoiseLite.new()
	hills.seed = rng.randi()
	hills.frequency = 0.022
	hills.fractal_octaves = 3
	var detail := FastNoiseLite.new()
	detail.seed = rng.randi()
	detail.frequency = 0.09
	var mountain := FastNoiseLite.new()
	mountain.seed = rng.randi()
	mountain.frequency = 0.05
	# Расстояние до дорог (по вершинам) — полотно дороги ровнее
	var road_d := _road_distance(data, vw, vh)
	var hv := PackedFloat32Array()
	hv.resize(vw * vh)
	for vz in vh:
		for vx in vw:
			var x := float(vx - MARGIN)
			var z := float(vz - MARGIN)
			var base := _base_height(data, x, z)
			var hgt := base + hills.get_noise_2d(x, z) * 3.2 + detail.get_noise_2d(x, z) * 0.35
			# Горы по краю долины: круто вверх (не взобраться)
			var edge := minf(minf(x, z), minf(W - x, H - z))
			if edge < RIM:
				var t := RIM - edge
				hgt += pow(t, 1.55) * 1.35 + maxf(mountain.get_noise_2d(x, z), -0.3) * t * 0.9
			var rd: float = road_d[vz * vw + vx]
			if rd < 4.0 and edge >= RIM:
				hgt = lerpf(base + hills.get_noise_2d(x, z) * 1.6, hgt, clampf((rd - 1.5) / 2.5, 0.0, 1.0))
			hv[vz * vw + vx] = hgt
	# Скальные холмы (входы в пещеры): отвесные края, плоская вершина
	for st in data.stamps:
		_stamp_mound(hv, vw, vh, st)
	# Площадки построек: ровно по средней высоте
	for pad in data.pads:
		_flatten(hv, vw, vh, pad.center, pad.radius)
	# Острова: провал/озеро кольцом, остров и берег — на уровне района
	for ch in data.chasms:
		_flatten(hv, vw, vh, ch.center, ch.r_out + 3.0, float(ch.level))
	# Ручные правки рельефа (кисти редактора): сдвиг высоты вершин
	var tedits: Dictionary = data.edits.get("terrain", {})
	for k in tedits:
		var xz: PackedStringArray = String(k).split(",")
		var vx := int(xz[0]) + MARGIN
		var vz := int(xz[1]) + MARGIN
		if vx >= 0 and vz >= 0 and vx < vw and vz < vh:
			hv[vz * vw + vx] += float(tedits[k])
	# Проходимость: уклон клетки
	var grid := PackedByteArray()
	grid.resize(W * H)
	for y in H:
		for x in W:
			var ex := x + MARGIN
			var ez := y + MARGIN
			var a := hv[ez * vw + ex]
			var b := hv[ez * vw + ex + 1]
			var c := hv[(ez + 1) * vw + ex + 1]
			var d := hv[(ez + 1) * vw + ex]
			var steep := maxf(maxf(a, b), maxf(c, d)) - minf(minf(a, b), minf(c, d)) > STEEP
			var v := BLOCK if steep or x == 0 or y == 0 or x == W - 1 or y == H - 1 else FLOOR
			if v == FLOOR and road_d[ez * vw + ex] < 1.6:
				v = PATH
			grid[y * W + x] = v
	for ch in data.chasms:
		var cc: Vector2 = ch.center
		for y in range(int(cc.y - ch.r_out - 1), int(cc.y + ch.r_out + 2)):
			for x in range(int(cc.x - ch.r_out - 1), int(cc.x + ch.r_out + 2)):
				var dd := Vector2(x + 0.5, y + 0.5).distance_to(cc)
				if dd >= ch.r_in and dd <= ch.r_out and _in(W, H, x, y):
					grid[y * W + x] = CHASM
		# Разрушенный каменный мост: от берега к острову, пролёты с провалами (перепрыгнуть)
		var dir: Vector2 = ch.dir
		var from: float = ch.r_out + 1.2      # от центра острова: начало на берегу
		var to: float = ch.r_in - 1.2         # конец на острове
		var t := from
		var first := true
		while t > to:
			var seg := rng.randf_range(1.6, 2.2) if not first else 2.6
			var end_t := maxf(t - seg, to)
			if end_t - to < 1.4:
				end_t = to
			var mid_t := (t + end_t) * 0.5
			var p: Vector2 = cc - dir * mid_t
			var lv: float = float(ch.level) + (0.0 if first or end_t == to else rng.randf_range(-0.12, 0.22))
			data.bridges.append({"pos": Vector3(p.x, lv, p.y), "size": Vector3(2.0, 0.5, t - end_t), "yaw": atan2(dir.x, dir.y),
				"tilt": 0.0 if first or end_t == to else rng.randf_range(-0.06, 0.06), "chasm": data.chasms.find(ch)})
			first = false
			t = end_t - rng.randf_range(1.0, 1.5)   # провал
	data.grid = grid
	var eg := PackedByteArray()
	eg.resize(ew * eh)
	eg.fill(BLOCK)
	for y in H:
		for x in W:
			eg[(y + MARGIN) * ew + x + MARGIN] = grid[y * W + x]
	data.ext = {"ew": ew, "eh": eh, "grid": eg}
	data.edist = block_distance(eg, ew, eh)
	data.terrain = {"ew": ew, "eh": eh, "hv": hv, "snap": _chasm_snap(data, grid)}
	data.lift = {}


## Края провалов не «лесенкой» по клеткам: углы клеток на границе земли и провала
## сдвигаются на окружность кольца (ближайшую — внешнюю или внутреннюю). Ключ — угол сетки, значение — точка.
static func _chasm_snap(data: Dictionary, grid: PackedByteArray) -> Dictionary:
	var snap := {}
	for ch in data.chasms:
		var cc: Vector2 = ch.center
		for cy in range(int(cc.y - ch.r_out - 2), int(cc.y + ch.r_out + 3)):
			for cx in range(int(cc.x - ch.r_out - 2), int(cc.x + ch.r_out + 3)):
				var has_chasm := false
				var has_land := false
				for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
					var x: int = cx + o.x
					var y: int = cy + o.y
					if not _in(W, H, x, y):
						continue
					if grid[y * W + x] == CHASM:
						has_chasm = true
					else:
						has_land = true
				if not (has_chasm and has_land):
					continue
				var p := Vector2(cx, cy)
				var d := p.distance_to(cc)
				var r: float = ch.r_out if absf(d - ch.r_out) < absf(d - ch.r_in) else ch.r_in
				snap[Vector2i(cx, cy)] = cc + (p - cc).normalized() * r
	return snap


## Положение угла сетки (с учётом сглаживания краёв провалов).
static func corner_pos(terrain: Dictionary, cx: int, cy: int) -> Vector2:
	return terrain.get("snap", {}).get(Vector2i(cx, cy), Vector2(cx, cy))


## База рельефа: высоты районов, плавно смешанные по расстоянию.
static func _base_height(data: Dictionary, x: float, z: float) -> float:
	var p := Vector2(x, z)
	var wsum := 0.0
	var hsum := 0.0
	for r in data.regions:
		var d: float = p.distance_to(r.center)
		var wgt := 1.0 / pow(maxf(d, 4.0), 2.2)
		wsum += wgt
		hsum += wgt * float(r.elev)
	return hsum / maxf(wsum, 0.000001)


## Расстояние от вершин сетки до ближайшей дороги (по точкам полилиний).
static func _road_distance(data: Dictionary, vw: int, vh: int) -> PackedFloat32Array:
	var d := PackedFloat32Array()
	d.resize(vw * vh)
	d.fill(99.0)
	for pts in data.roads:
		for p in pts:
			var cx := int(p.x) + MARGIN
			var cz := int(p.y) + MARGIN
			for z in range(cz - 5, cz + 6):
				for x in range(cx - 5, cx + 6):
					if x < 0 or z < 0 or x >= vw or z >= vh:
						continue
					var dd := Vector2(x - MARGIN, z - MARGIN).distance_to(p)
					if dd < d[z * vw + x]:
						d[z * vw + x] = dd
	return d


static func _stamp_mound(hv: PackedFloat32Array, vw: int, vh: int, st: Dictionary) -> void:
	var c: Vector2 = st.center
	var r: float = st.radius
	var top := -INF
	for z in range(int(c.y - r) - 2, int(c.y + r) + 3):
		for x in range(int(c.x - r) - 2, int(c.x + r) + 3):
			var vx := x + MARGIN
			var vz := z + MARGIN
			if vx >= 0 and vz >= 0 and vx < vw and vz < vh:
				top = maxf(top, hv[vz * vw + vx])
	top += float(st.height)
	for z in range(int(c.y - r) - 2, int(c.y + r) + 3):
		for x in range(int(c.x - r) - 2, int(c.x + r) + 3):
			var vx := x + MARGIN
			var vz := z + MARGIN
			if vx < 0 or vz < 0 or vx >= vw or vz >= vh:
				continue
			var d := Vector2(x, z).distance_to(c)
			var t := clampf((r - d) / 2.2, 0.0, 1.0)   # отвесный край на последних ~2 м радиуса
			hv[vz * vw + vx] = maxf(hv[vz * vw + vx], lerpf(hv[vz * vw + vx], top, t))


static func _flatten(hv: PackedFloat32Array, vw: int, vh: int, c: Vector2, r: float, level: float = INF) -> void:
	var avg := 0.0
	var n := 0
	for z in range(int(c.y - r), int(c.y + r) + 1):
		for x in range(int(c.x - r), int(c.x + r) + 1):
			var vx := x + MARGIN
			var vz := z + MARGIN
			if vx >= 0 and vz >= 0 and vx < vw and vz < vh and Vector2(x, z).distance_to(c) <= r:
				avg += hv[vz * vw + vx]
				n += 1
	var target := avg / maxf(n, 1) if level == INF else level
	for z in range(int(c.y - r) - 4, int(c.y + r) + 5):
		for x in range(int(c.x - r) - 4, int(c.x + r) + 5):
			var vx := x + MARGIN
			var vz := z + MARGIN
			if vx < 0 or vz < 0 or vx >= vw or vz >= vh:
				continue
			var d := Vector2(x, z).distance_to(c)
			var t := clampf((d - r) / 4.0, 0.0, 1.0)   # плавный переход за краем площадки
			hv[vz * vw + vx] = lerpf(target, hv[vz * vw + vx], t)


## Расстояние (в клетках) от каждой непроходимой клетки до ближайшей проходимой (BFS, до 10).
static func block_distance(grid: PackedByteArray, w: int, h: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(w * h)
	dist.fill(-1)
	var queue: Array[Vector2i] = []
	for y in h:
		for x in w:
			var v := grid[y * w + x]
			if v == FLOOR or v == PATH:
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
			if dist[i] == -1 and grid[i] == BLOCK:
				dist[i] = d + 1
				queue.append(n)
	return dist


## Высота рельефа в мировой точке (точно по треугольникам меша земли).
static func height_at(terrain: Dictionary, x: float, z: float) -> float:
	if terrain.is_empty():
		return 0.0
	var ew: int = terrain.ew
	var eh: int = terrain.eh
	var vw := ew + 1
	var fx := clampf(x + MARGIN, 0.0, ew - 0.001)
	var fz := clampf(z + MARGIN, 0.0, eh - 0.001)
	var ix := int(fx)
	var iz := int(fz)
	var ux := fx - ix
	var uz := fz - iz
	var hv: PackedFloat32Array = terrain.hv
	var h00 := hv[iz * vw + ix]
	var h10 := hv[iz * vw + ix + 1]
	var h11 := hv[(iz + 1) * vw + ix + 1]
	var h01 := hv[(iz + 1) * vw + ix]
	if ux >= uz:
		return h00 + (h10 - h00) * ux + (h11 - h10) * uz
	return h00 + (h11 - h01) * ux + (h01 - h00) * uz


## Район, в котором находится точка (ближайший центр).
static func region_at(data: Dictionary, p: Vector2) -> String:
	var best := ""
	var bd := INF
	for r in data.get("regions", []):
		var d: float = p.distance_to(r.center)
		if d < bd:
			bd = d
			best = r.id
	return best


# ---------------------------------------------------------------- Утилиты

static func _in(w: int, h: int, x: int, y: int) -> bool:
	return x > 0 and y > 0 and x < w - 1 and y < h - 1


## Свободная проходимая клетка в круге (по возможности не на дороге); min_r — не ближе к центру.
static func _free_cell(data: Dictionary, c: Dictionary, rng: RandomNumberGenerator, occupied: Dictionary, min_r: float = 0.0) -> Vector2i:
	var grid: PackedByteArray = data.grid
	for attempt in 80:
		var a := rng.randf() * TAU
		var r: float = lerpf(min_r, float(c.radius), rng.randf())
		var cell := Vector2i(Vector2(c.center) + Vector2(cos(a), sin(a)) * r)
		if not _in(W, H, cell.x, cell.y) or occupied.has(cell):
			continue
		var v := grid[cell.y * W + cell.x]
		if v == FLOOR or (v == PATH and attempt > 40):
			occupied[cell] = true
			return cell
	return Vector2i(c.center)


static func _pick_riddle(rng: RandomNumberGenerator, used: Dictionary) -> String:
	var all: Array = load("res://scenes/dungeon/RiddleScreen.gd").all_ids()
	var free := all.filter(func(id): return not id in used.get("riddles", []))
	if free.is_empty():
		free = all
	return free[rng.randi() % free.size()]


static func _pick_safe(rng: RandomNumberGenerator, used: Dictionary) -> String:
	var all: Array = load("res://scenes/dungeon/SafeScreen.gd").all_ids()
	var free := all.filter(func(id): return not id in used.get("safes", []))
	if free.is_empty():
		free = all
	return free[rng.randi() % free.size()]
