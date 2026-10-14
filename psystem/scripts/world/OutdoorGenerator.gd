class_name OutdoorGenerator
extends RefCounted
## Единая поверхность локации: все наземные подлокации — районы одной большой карты, связанные тропами
## по графу локации (пещеры, гробницы и подземелья остаются отдельными уровнями — вход в склоне холма).
## Только данные — 3D строит LevelBuilder, а карта локации рисует по ним топографию.
##
## Сетка 1 клетка = 1 м: 0 — непроходимо (склоны оврага), 1 — поляна, 2 — тропа, 3 — пропасть или река.
## Рельеф: у каждого района своя высота (база плавно перетекает между районами), на полянах — уступы-плато
## с пандусом и каменные глыбы, вокруг — крутые склоны (на них не забраться — герой соскальзывает).
## Район с features.platforms рассечён пропастью/рекой, переправа — прыжками по движущимся платформам.
## У каждого района — указатель (точка быстрого перемещения), их число показывается на карте.

const BLOCK := 0
const FLOOR := 1
const PATH := 2
const CHASM := 3

const W := 184
const H := 108
const MARGIN := 34
const REGION_R := 15.0
## Высота крутых склонов по расстоянию (в клетках) от проходимой зоны: каждый шаг круче 50° — не взобраться.
const HILL := [0.0, 2.1, 3.9, 5.6, 7.0, 8.2, 9.2]

static var _cache: Dictionary = {}


static func generate_surface(loc_id: String) -> Dictionary:
	var key := loc_id + "/" + Loc.lang()
	if _cache.has(key):
		return _cache[key]
	var loc := WorldData.location(loc_id)
	var rng := RandomNumberGenerator.new()
	rng.seed = absi(hash(loc_id)) % 1000003
	var grid := PackedByteArray()
	grid.resize(W * H)
	grid.fill(BLOCK)
	var occupied := {}
	var lift := {}          # клетка → подъём плато над базой
	var data := {
		"w": W, "h": H, "grid": grid, "kind": loc.get("biome", "forest"), "underground": false, "surface": true,
		"location_id": loc_id, "regions": [], "clearings": [], "chests": [], "enemies": [], "bosses": [], "npcs": [],
		"safes": [], "signposts": [], "caves": [], "platforms": [], "chasms": [], "vertical": [], "rocks": [],
		"mesas": [], "start": Vector2i.ZERO, "water": false, "exits": [],
	}

	# --- Районы: центры по положению подлокаций на карте локации
	var regions: Array = []
	var by_id := {}
	for id in loc.order:
		var n: Dictionary = loc.nodes[id]
		if WorldData.is_underground(n):
			continue
		var c := Vector2(16.0 + float(n.pos[0]) * (W - 32), 15.0 + float(n.pos[1]) * (H - 30))
		var r := {"id": id, "name": n.get("name", id), "kind": n.get("kind", "meadow"), "center": c,
			"radius": REGION_R, "clearings": [], "elev": 0.0 if n.get("start", false) else rng.randf_range(0.5, 4.5),
			"features": n.get("features", {}), "chasm": -1}
		regions.append(r)
		by_id[id] = r

	# --- Пропасть/река в районах с платформами: вертикальная полоса через центр района
	for r in regions:
		if not r.features.get("platforms", false):
			continue
		var cw := 9 if r.kind == "riverside" else 7
		var rect := Rect2i(int(r.center.x) - cw / 2, int(r.center.y - REGION_R - 5), cw, int(REGION_R * 2 + 10))
		rect = rect.intersection(Rect2i(1, 1, W - 2, H - 2))
		r.chasm = data.chasms.size()
		data.chasms.append({"rect": rect, "water": r.kind == "riverside", "region": r.id, "level": r.elev, "cross_y": 0})
		if r.kind == "riverside":
			data.water = true

	# --- Поляны района (по обе стороны пропасти, если она есть)
	for r in regions:
		var want := 5
		var chasm_rect := Rect2i()
		if r.chasm >= 0:
			chasm_rect = data.chasms[r.chasm].rect
		for attempt in 800:
			if r.clearings.size() >= want:
				break
			var cr := rng.randf_range(3.6, 5.6)
			var a := rng.randf() * TAU
			var dist := 0.0 if r.clearings.is_empty() else rng.randf() * (REGION_R - cr * 0.5)
			var c: Vector2 = r.center + Vector2(cos(a), sin(a)) * dist
			if c.x - cr < 3 or c.y - cr < 3 or c.x + cr > W - 4 or c.y + cr > H - 4:
				continue
			if chasm_rect.size.x > 0 and c.x + cr + 2 > chasm_rect.position.x and c.x - cr - 2 < chasm_rect.end.x:
				continue
			var ok := true
			for o in data.clearings:
				if c.distance_to(o.center) < cr + o.radius + 2.2:
					ok = false
					break
			if ok:
				var cl := {"center": c, "radius": cr, "region": r.id,
					"side": 0 if chasm_rect.size.x == 0 or c.x < chasm_rect.position.x else 1, "id": data.clearings.size()}
				r.clearings.append(cl)
				data.clearings.append(cl)
		if chasm_rect.size.x > 0:
			for side in [0, 1]:
				if r.clearings.filter(func(c): return c.side == side).is_empty():
					var x: float = chasm_rect.position.x - 6.5 if side == 0 else chasm_rect.end.x + 6.5
					var cl := {"center": Vector2(x, r.center.y), "radius": 4.0, "region": r.id, "side": side, "id": data.clearings.size()}
					r.clearings.append(cl)
					data.clearings.append(cl)
		if r.clearings.is_empty():
			var cl := {"center": r.center, "radius": 5.0, "region": r.id, "side": 0, "id": data.clearings.size()}
			r.clearings.append(cl)
			data.clearings.append(cl)

	# --- Тропы внутри района (остовное дерево по сторонам пропасти)
	for r in regions:
		for side in [0, 1]:
			var group: Array = r.clearings.filter(func(c): return c.side == side)
			if group.size() < 2:
				continue
			var in_tree := [group[0]]
			while in_tree.size() < group.size():
				var best := [INF, null, null]
				for a in in_tree:
					for b in group:
						if b in in_tree:
							continue
						var d: float = a.center.distance_to(b.center)
						if d < best[0]:
							best = [d, a, b]
				_carve_path(grid, W, H, best[1].center, best[2].center, rng)
				in_tree.append(best[2])
	for c in data.clearings:
		_carve_circle(grid, W, H, c.center, c.radius, rng)

	# --- Тропы между районами по связям графа локации
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
			var a := _nearest(r.clearings, o.center)
			var b := _nearest(o.clearings, r.center)
			_carve_path(grid, W, H, a.center, b.center, rng)

	# --- Переправы через пропасти: подходы и цепочка платформ
	for ch in data.chasms:
		var rect: Rect2i = ch.rect
		var r: Dictionary = by_id[ch.region]
		var cross_y: int = clampi(int(r.center.y) + rng.randi_range(-4, 4), rect.position.y + 3, rect.end.y - 4)
		ch.cross_y = cross_y
		var left := _nearest(r.clearings.filter(func(c): return c.side == 0), Vector2(rect.position.x, cross_y))
		var right := _nearest(r.clearings.filter(func(c): return c.side == 1), Vector2(rect.end.x, cross_y))
		_carve_path(grid, W, H, left.center, Vector2(rect.position.x - 2, cross_y), rng)
		_carve_path(grid, W, H, right.center, Vector2(rect.end.x + 1, cross_y), rng)
		for y in range(cross_y - 2, cross_y + 3):
			for x in range(rect.position.x - 4, rect.position.x):
				_put(grid, W, H, x, y, PATH)
			for x in range(rect.end.x, rect.end.x + 4):
				_put(grid, W, H, x, y, PATH)
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				grid[y * W + x] = CHASM
		var span := float(rect.size.x) + 1.0
		var n := int(ceil(span / 2.6))
		var step := span / (n + 1)
		for i in n:
			var x := rect.position.x - 0.5 + step * (i + 1)
			var moving := i % 2 == 0 or n <= 2
			var swing := rng.randf_range(1.6, 2.6) * (1 if rng.randf() < 0.5 else -1)
			var lv: float = ch.level
			data.platforms.append({"a": Vector3(x, lv, cross_y + 0.5 - (swing if moving else 0.0)),
				"b": Vector3(x, lv, cross_y + 0.5 + (swing if moving else 0.0)),
				"period": rng.randf_range(3.6, 5.0), "phase": rng.randf(), "size": Vector3(1.9, 0.4, 1.9)})

	# --- Входы в пещеры: короткая тропа от поляны к склону, вход — в склоне
	for r in regions:
		var sealed_done := false
		for link in loc.nodes[r.id].get("links", []):
			var un: Dictionary = loc.nodes.get(link, {})
			if un.is_empty() or not WorldData.is_underground(un):
				continue
			var d: Vector2 = (Vector2(un.pos[0], un.pos[1]) - Vector2(loc.nodes[r.id].pos[0], loc.nodes[r.id].pos[1])).normalized()
			if d.length() < 0.01:
				d = Vector2.RIGHT
			var target: Vector2 = r.center + d * (REGION_R + 5.0)
			var side := 0
			if r.chasm >= 0:
				side = 0 if target.x < data.chasms[r.chasm].rect.position.x else 1
			var from := _nearest(r.clearings.filter(func(c): return c.side == side), target)
			var tip := Vector2i(clampi(int(target.x), 3, W - 4), clampi(int(target.y), 3, H - 4))
			_carve_path(grid, W, H, from.center, Vector2(tip) + Vector2(0.5, 0.5), rng)
			var out := Vector2i(roundi(d.x), roundi(d.y))
			if out == Vector2i.ZERO:
				out = Vector2i(1, 0)
			var cave := {"to": link, "to_name": un.get("name", link), "to_kind": un.get("kind", "cave"), "region": r.id,
				"cell": tip, "dir": d, "arrive": Vector2i(Vector2(tip) - d * 4.0), "kind": _cave_kind(un.get("kind", "cave")),
				"sealed": false, "riddle_id": ""}
			if r.features.get("riddle_gate", false) and not sealed_done:
				cave.sealed = true
				cave.riddle_id = _pick_riddle(rng, {})
				sealed_done = true
			for k in range(-1, 6):
				var cc := Vector2i(Vector2(tip) - d * k)
				for oy in range(-1, 2):
					for ox in range(-1, 2):
						occupied[cc + Vector2i(ox, oy)] = true
			data.caves.append(cave)

	# --- Указатели (точки быстрого перемещения): по одному на район, у центральной поляны
	for r in regions:
		var main := _nearest(r.clearings, r.center)
		r.main = main.id
		var cell := _free_cell(grid, W, H, {"center": main.center, "radius": main.radius * 0.6}, rng, occupied)
		for oy in range(-1, 2):
			for ox in range(-1, 2):
				occupied[cell + Vector2i(ox, oy)] = true
		var arrive := cell + Vector2i(0, 2)
		if grid[arrive.y * W + arrive.x] == BLOCK:
			arrive = cell
		data.signposts.append({"region": r.id, "name": r.name, "cell": cell, "arrive": arrive})
		if loc.nodes[r.id].get("start", false):
			data.start = arrive

	# --- Плато с пандусом и каменные глыбы — рельеф на полянах (до сундуков и врагов)
	for r in regions:
		var big: Array = r.clearings.filter(func(c): return c.radius >= 4.5 and c.id != r.main)
		big.shuffle()
		if not big.is_empty() and rng.randf() < 0.85:
			var c: Dictionary = big.pop_front()
			_make_mesa(data, grid, c, lift, occupied, rng)
		var rocky: Array = r.clearings.filter(func(cl): return cl.id != r.main)
		for i in mini(rocky.size(), 1 + rng.randi() % 2):
			var c: Dictionary = rocky[rng.randi() % rocky.size()]
			var spot := _free_cell(grid, W, H, c, rng, occupied)
			var yaw := rng.randf() * TAU
			data.rocks.append({"pos": Vector2(spot) + Vector2(0.5, 0.5), "yaw": yaw, "region": r.id})
			for oy in range(-2, 3):
				for ox in range(-2, 3):
					occupied[spot + Vector2i(ox, oy)] = true

	# --- Башни и вышки с ценным сундуком наверху
	for r in regions:
		var vtypes: Array = r.features.get("vertical", ["tower" if r.kind == "ruins" else "stumps"])
		var vpool: Array = r.clearings.filter(func(c): return c.radius >= 4.4 and c.id != r.main and not _disc_busy(occupied, c.center, 2.6))
		vpool.sort_custom(func(a, b): return a.radius > b.radius)
		for t in vtypes:
			if vpool.is_empty():
				break
			var c: Dictionary = vpool.pop_front()
			var yaw := rng.randf() * TAU
			var center: Vector2 = c.center + Vector2(cos(yaw), sin(yaw)) * minf(c.radius - 3.4, 1.2)
			for y in range(int(center.y) - 3, int(center.y) + 4):
				for x in range(int(center.x) - 3, int(center.x) + 4):
					if Vector2(x + 0.5, y + 0.5).distance_to(center) <= 3.2:
						occupied[Vector2i(x, y)] = true
			data.vertical.append({"type": t, "center": center, "yaw": yaw, "height": 5.6 if t == "tower" else 3.2, "region": r.id})

	# --- Жители, сундуки, сейфы, враги, боссы по районам
	var used := {"riddles": [], "safes": []}
	for r in regions:
		var f: Dictionary = r.features
		var others: Array = r.clearings.filter(func(c): return c.id != r.main)
		if others.is_empty():
			others = r.clearings
		var main_c: Dictionary = r.clearings.filter(func(c): return c.id == r.main)[0]
		var npc_ids: Array = f.get("npcs", [])
		for i in npc_ids.size():
			data.npcs.append({"id": npc_ids[i], "cell": _free_cell(grid, W, H, main_c, rng, occupied), "region": r.id})
		for i in int(f.get("chests", 2)):
			var c: Dictionary = others[rng.randi() % others.size()]
			data.chests.append({"cell": _free_cell(grid, W, H, c, rng, occupied), "region": r.id, "index": i})
		if f.get("safe", false):
			var c: Dictionary = others[rng.randi() % others.size()]
			var sid := _pick_safe(rng, used)
			used.safes.append(sid)
			data.safes.append({"id": sid, "cell": _free_cell(grid, W, H, c, rng, occupied), "region": r.id, "reward": "loot"})
		var pool: Array = f.get("pool", ["syntax_error"])
		var enemy_cl := others.duplicate()
		if r.chasm >= 0:
			enemy_cl.sort_custom(func(a, b): return a.side > b.side)
		for i in int(f.get("enemies", 3)):
			var c: Dictionary = enemy_cl[i % enemy_cl.size()]
			data.enemies.append({"id": pool[rng.randi() % pool.size()], "cell": _free_cell(grid, W, H, c, rng, occupied),
				"area": _area_of(c), "region": r.id, "index": i})
		if f.has("boss"):
			var far: Array = others.duplicate()
			far.sort_custom(func(a, b): return a.center.distance_to(main_c.center) > b.center.distance_to(main_c.center))
			var c: Dictionary = far[0]
			data.bosses.append({"id": f.boss, "cell": _free_cell(grid, W, H, c, rng, occupied), "area": _area_of(c), "region": r.id})

	data.regions = regions
	data.lift = lift
	_build_terrain(data)
	_cache[key] = data
	return data


static func _disc_busy(occupied: Dictionary, center: Vector2, radius: float) -> bool:
	for y in range(int(center.y - radius), int(center.y + radius) + 1):
		for x in range(int(center.x - radius), int(center.x + radius) + 1):
			if occupied.has(Vector2i(x, y)) and Vector2(x + 0.5, y + 0.5).distance_to(center) <= radius:
				return true
	return false


static func _cave_kind(kind: String) -> String:
	return "crypt" if kind == "tomb" else ("stairs_down" if kind == "dungeon" else "cave")


## Плато: круг на поляне, поднятый на 1.6–2.6 м (края — крутой обрыв), с пологим пандусом в одну сторону.
static func _make_mesa(data: Dictionary, grid: PackedByteArray, c: Dictionary, lift: Dictionary, occupied: Dictionary, rng: RandomNumberGenerator) -> void:
	var a := rng.randf() * TAU
	var mr := rng.randf_range(2.2, 3.0)
	var center: Vector2 = c.center + Vector2(cos(a), sin(a)) * maxf(c.radius - mr - 0.6, 0.0)
	var height := rng.randf_range(1.6, 2.6)
	var ramp_dir: Vector2 = (c.center - center).normalized() if c.center.distance_to(center) > 0.5 else Vector2(cos(a + PI), sin(a + PI))
	for y in range(int(center.y - mr - 1), int(center.y + mr + 2)):
		for x in range(int(center.x - mr - 1), int(center.x + mr + 2)):
			if not _in(W, H, x, y) or grid[y * W + x] == BLOCK or grid[y * W + x] == CHASM:
				continue
			if Vector2(x + 0.5, y + 0.5).distance_to(center) <= mr:
				lift[Vector2i(x, y)] = height
	# Пандус: 5 клеток наружу от края, высота убывает
	for k in range(1, 7):
		var p: Vector2 = center + ramp_dir * (mr + k - 0.5)
		for lat in [-1, 0, 1]:
			var q := Vector2i(p + ramp_dir.orthogonal() * lat)
			if _in(W, H, q.x, q.y) and grid[q.y * W + q.x] != BLOCK and grid[q.y * W + q.x] != CHASM:
				lift[q] = maxf(float(lift.get(q, 0.0)), height * (1.0 - float(k) / 7.0))
	data.mesas.append({"center": center, "radius": mr, "height": height, "region": c.region})


# ---------------------------------------------------------------- Рельеф

## Расширенная сетка (поля MARGIN вокруг), расстояния до проходимых клеток и высоты вершин.
static func _build_terrain(data: Dictionary) -> void:
	var ew := W + MARGIN * 2
	var eh := H + MARGIN * 2
	var eg := PackedByteArray()
	eg.resize(ew * eh)
	eg.fill(BLOCK)
	var grid: PackedByteArray = data.grid
	for y in H:
		for x in W:
			eg[(y + MARGIN) * ew + x + MARGIN] = grid[y * W + x]
	var edist := block_distance(eg, ew, eh)
	var regions: Array = data.regions
	var noise := FastNoiseLite.new()
	noise.seed = W * 13 + H + regions.size()
	noise.frequency = 0.08
	var base_noise := FastNoiseLite.new()
	base_noise.seed = noise.seed + 7
	base_noise.frequency = 0.035
	var lift: Dictionary = data.lift
	var vw := ew + 1
	var vh := eh + 1
	var hv := PackedFloat32Array()
	hv.resize(vw * vh)
	for vz in vh:
		for vx in vw:
			var wx := float(vx - MARGIN)
			var wz := float(vz - MARGIN)
			var base := _base_height(data, wx, wz) + base_noise.get_noise_2d(wx, wz) * 0.7
			var dmin := 99
			var near_chasm := false
			var top_lift := 0.0
			for o in [Vector2i(-1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 0)]:
				var cx: int = vx + o.x
				var cz: int = vz + o.y
				if cx < 0 or cz < 0 or cx >= ew or cz >= eh:
					continue
				var i := cz * ew + cx
				var v := eg[i]
				if v == CHASM:
					near_chasm = true
					dmin = 0
					continue
				if v == BLOCK:
					dmin = mini(dmin, edist[i] if edist[i] > 0 else 10)
				else:
					dmin = 0
					top_lift = maxf(top_lift, float(lift.get(Vector2i(cx - MARGIN, cz - MARGIN), 0.0)))
			if dmin == 99:
				dmin = 10
			var hgt := base
			if near_chasm:
				hgt = _chasm_level(data, wx, wz, base)
			elif dmin == 0:
				hgt = base + top_lift
			else:
				hgt = base + float(HILL[mini(dmin, HILL.size() - 1)]) + noise.get_noise_2d(wx, wz) * 0.6 * minf(dmin, 3) / 3.0 + maxf(dmin - 6, 0) * 0.6
			hv[vz * vw + vx] = hgt
	data.ext = {"ew": ew, "eh": eh, "grid": eg}
	data.edist = edist
	data.terrain = {"ew": ew, "eh": eh, "hv": hv}


## База рельефа: высоты районов, плавно смешанные по расстоянию; у пропастей — ровно уровень района.
static func _base_height(data: Dictionary, x: float, z: float) -> float:
	var p := Vector2(x, z)
	var wsum := 0.0
	var hsum := 0.0
	for r in data.regions:
		var d: float = p.distance_to(r.center)
		var wgt := 1.0 / pow(maxf(d, 3.0), 2.4)
		wsum += wgt
		hsum += wgt * float(r.elev)
	var h := hsum / maxf(wsum, 0.000001)
	for ch in data.chasms:
		var rect: Rect2i = ch.rect
		var dx := maxf(maxf(rect.position.x - x, x - rect.end.x), 0.0)
		var dz := maxf(maxf(rect.position.y - z, z - rect.end.y), 0.0)
		var d := Vector2(dx, dz).length()
		if d < 8.0:
			h = lerpf(float(ch.level), h, d / 8.0)
	return h


static func _chasm_level(data: Dictionary, x: float, z: float, fallback: float) -> float:
	for ch in data.chasms:
		var rect: Rect2i = ch.rect
		if x >= rect.position.x - 1 and x <= rect.end.x + 1 and z >= rect.position.y - 1 and z <= rect.end.y + 1:
			return float(ch.level)
	return fallback


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

static func _put(grid: PackedByteArray, w: int, h: int, x: int, y: int, v: int) -> void:
	if x > 0 and y > 0 and x < w - 1 and y < h - 1:
		grid[y * w + x] = v


static func _carve_circle(grid: PackedByteArray, w: int, h: int, c: Vector2, r: float, rng: RandomNumberGenerator) -> void:
	var wobble := rng.randf() * TAU
	for y in range(int(c.y - r - 2), int(c.y + r + 3)):
		for x in range(int(c.x - r - 2), int(c.x + r + 3)):
			var d := Vector2(x + 0.5, y + 0.5) - c
			var rr := r * (1.0 + 0.18 * sin(atan2(d.y, d.x) * 3.0 + wobble))
			if d.length() <= rr and _in(w, h, x, y):
				if grid[y * w + x] == BLOCK:
					grid[y * w + x] = FLOOR


static func _carve_path(grid: PackedByteArray, w: int, h: int, a: Vector2, b: Vector2, rng: RandomNumberGenerator) -> void:
	var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * a.distance_to(b) * rng.randf_range(-0.25, 0.25)
	var steps := int(a.distance_to(b) * 2.0) + 2
	for i in steps + 1:
		var t := float(i) / steps
		var p := a.lerp(mid, t).lerp(mid.lerp(b, t), t)
		for dy in range(-1, 2):
			for dx in range(-1, 2):
				var x := int(p.x) + dx
				var y := int(p.y) + dy
				if _in(w, h, x, y) and grid[y * w + x] == BLOCK:
					grid[y * w + x] = PATH


static func _in(w: int, h: int, x: int, y: int) -> bool:
	return x > 0 and y > 0 and x < w - 1 and y < h - 1


static func _nearest(list: Array, p: Vector2) -> Dictionary:
	var best: Dictionary = list[0]
	for c in list:
		if c.center.distance_to(p) < best.center.distance_to(p):
			best = c
	return best


static func _area_of(c: Dictionary) -> Rect2i:
	var r := int(c.radius)
	return Rect2i(int(c.center.x) - r, int(c.center.y) - r, r * 2, r * 2)


static func _free_cell(grid: PackedByteArray, w: int, h: int, c: Dictionary, rng: RandomNumberGenerator, occupied: Dictionary) -> Vector2i:
	for attempt in 60:
		var a := rng.randf() * TAU
		var r: float = rng.randf() * maxf(c.radius - 1.5, 0.5)
		var cell := Vector2i(c.center + Vector2(cos(a), sin(a)) * r)
		if _in(w, h, cell.x, cell.y) and grid[cell.y * w + cell.x] in [FLOOR, PATH] and not occupied.has(cell):
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
