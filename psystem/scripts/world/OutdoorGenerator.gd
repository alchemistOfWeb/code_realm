class_name OutdoorGenerator
extends RefCounted
## Генерация наземной подлокации (поляна, лес, берег реки, руины). Только данные — 3D строит LevelBuilder.
##
## Сетка 1 клетка = 1 м: 0 — непроходимо (лес, скалы, стены руин), 1 — поляна, 2 — тропа,
## 3 — пропасть или река (смертельно: падение = гибель). Поляны соединены извилистыми тропами (MST).
## Если у подлокации features.platforms — карту рассекает пропасть/река поперёк, перейти её можно
## только прыжками по движущимся платформам.
## Выходы — тропы, уходящие за край карты в сторону соседней подлокации (по её положению на карте
## локации). Переход — когда герой уходит по тропе за край; «указатель» (arrive) — точка появления.

const BLOCK := 0
const FLOOR := 1
const PATH := 2
const CHASM := 3


## node — данные подлокации, neighbors — [{id, name, kind}] соседей, entry — id соседа, откуда пришли.
static func generate(node: Dictionary, neighbors: Array, seed_value: int, entry: String, used: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var f: Dictionary = node.get("features", {})
	var has_chasm: bool = f.get("platforms", false)
	var w := 76 if has_chasm else 64
	var h := 46
	var grid := PackedByteArray()
	grid.resize(w * h)
	grid.fill(BLOCK)
	var chasm := Rect2i()
	if has_chasm:
		var cw := 9
		chasm = Rect2i(int(w * 0.5) - cw / 2, 0, cw, h)

	# --- Поляны (по 3–4 с каждой стороны пропасти)
	var clearings: Array = []
	var target_count := 8 if has_chasm else 6
	for attempt in 600:
		if clearings.size() >= target_count:
			break
		var r := rng.randf_range(3.8, 6.2)
		var c := Vector2(rng.randf_range(r + 3, w - r - 3), rng.randf_range(r + 3, h - r - 3))
		if has_chasm and c.x + r + 2 > chasm.position.x and c.x - r - 2 < chasm.end.x:
			continue
		var ok := true
		for o in clearings:
			if c.distance_to(o.center) < r + o.radius + 4.0:
				ok = false
				break
		if ok:
			clearings.append({"center": c, "radius": r, "side": 0 if (not has_chasm or c.x < chasm.position.x) else 1})
	clearings.sort_custom(func(a, b): return a.center.x < b.center.x)
	if has_chasm and clearings.filter(func(c): return c.side == 1).is_empty():
		clearings.append({"center": Vector2(chasm.end.x + 7, h * 0.5), "radius": 5.0, "side": 1})
	for i in clearings.size():
		clearings[i].id = i

	# --- Тропы: минимальное остовное дерево внутри каждой стороны + одна лишняя петля
	for side in ([0, 1] if has_chasm else [0]):
		var group := clearings.filter(func(c): return c.side == side)
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
			_carve_path(grid, w, h, best[1].center, best[2].center, rng)
			in_tree.append(best[2])
		if group.size() > 3:
			_carve_path(grid, w, h, group[0].center, group[group.size() - 1].center, rng)
	for c in clearings:
		_carve_circle(grid, w, h, c.center, c.radius, rng)

	# --- Переправа: тропы к краям пропасти и цепочка платформ
	var platforms: Array = []
	var cross_y := 0
	if has_chasm:
		cross_y = int(h * 0.5) + rng.randi_range(-6, 6)
		var left := _nearest(clearings.filter(func(c): return c.side == 0), Vector2(chasm.position.x, cross_y))
		var right := _nearest(clearings.filter(func(c): return c.side == 1), Vector2(chasm.end.x, cross_y))
		_carve_path(grid, w, h, left.center, Vector2(chasm.position.x - 2, cross_y), rng)
		_carve_path(grid, w, h, right.center, Vector2(chasm.end.x + 1, cross_y), rng)
		for y in range(cross_y - 2, cross_y + 3):
			for x in range(chasm.position.x - 4, chasm.position.x):
				_put(grid, w, h, x, y, PATH)
			for x in range(chasm.end.x, chasm.end.x + 4):
				_put(grid, w, h, x, y, PATH)
		var span := float(chasm.size.x) + 1.0
		var n := int(ceil(span / 2.6))
		var step := span / (n + 1)
		for i in n:
			var x := chasm.position.x - 0.5 + step * (i + 1)
			var moving := i % 2 == 0 or n <= 2
			var swing := rng.randf_range(1.6, 2.6) * (1 if rng.randf() < 0.5 else -1)
			var a := Vector3(x, 0.0, cross_y + 0.5 - (swing if moving else 0.0))
			var b := Vector3(x, 0.0, cross_y + 0.5 + (swing if moving else 0.0))
			platforms.append({"a": a, "b": b, "period": rng.randf_range(3.6, 5.0), "phase": rng.randf(), "size": Vector3(1.9, 0.4, 1.9)})
		for y in h:
			for x in range(chasm.position.x, chasm.end.x):
				_put(grid, w, h, x, y, CHASM)

	# --- Выходы: тропа от ближайшей поляны к краю карты — в ту сторону, где сосед лежит на карте локации.
	# Раскладка не зависит от того, откуда пришли (исследованная часть карты запоминается);
	# entry влияет только на точку появления — «указатель» у начала тропы.
	var occupied := {}
	var start_c: Dictionary = clearings[0]
	var exits: Array = []
	var used_border: Array = []
	var npos := _pos_of(node)
	for n in neighbors:
		var d := _pos_of(n) - npos
		if d.length() < 0.001:
			d = Vector2(1, 0)
		var border := _border_point(w, h, d.normalized(), chasm, used_border)
		used_border.append(border)
		var out := _outward(w, h, border)
		var perp := Vector2i(-out.y, out.x)
		var side := 0 if (not has_chasm or border.x < chasm.position.x) else 1
		var group := clearings.filter(func(c): return c.side == side)
		if group.is_empty():
			group = clearings
		var from_c := _nearest(group, Vector2(border))
		_carve_path(grid, w, h, from_c.center, Vector2(border - out * 6) + Vector2(0.5, 0.5), rng)
		# Последние метры тропы — прямой проход шириной 3 клетки до самого края
		for k in 8:
			for lat in [-1, 0, 1]:
				var c: Vector2i = border - out * k + perp * lat
				if _in(w, h, c.x, c.y) and grid[c.y * w + c.x] != CHASM:
					grid[c.y * w + c.x] = PATH
		var e := _exit(n, border, node)
		e.dir = out
		e.arrive = border - out * 5
		for k in range(0, 8):
			for lat in [-1, 0, 1]:
				occupied[border - out * k + perp * lat] = true
		exits.append(e)
	var start := Vector2i(start_c.center)
	occupied[start] = true
	for e in exits:
		if e.to == entry:
			start = e.arrive
	if f.get("riddle_gate", false):
		for e in exits:
			if WorldData.NODE_KINDS.get(e.to_kind, {}).get("underground", false):
				e.sealed = true
				break
		if not exits.any(func(e): return e.get("sealed", false)) and exits.size() > 1:
			exits[-1].sealed = true

	var result := {
		"w": w, "h": h, "grid": grid, "kind": node.get("kind", "meadow"), "underground": false,
		"start": start, "clearings": clearings, "exits": exits, "platforms": platforms,
		"chasm": chasm if has_chasm else Rect2i(), "water": node.get("kind") == "riverside",
		"npcs": [], "chests": [], "enemies": [], "boss": {}, "safe": {}, "gates": [], "gate_mode": "none",
		"riddle_id": "", "warden_cell": Vector2i(-1, -1), "rooms": [],
	}
	result.riddle_id = _pick_riddle(rng, used)
	var pool_clearings: Array = clearings.filter(func(c): return c != start_c)
	if pool_clearings.is_empty():
		pool_clearings = clearings

	var far: Array = clearings.duplicate()
	far.sort_custom(func(a, b): return a.center.distance_to(start_c.center) > b.center.distance_to(start_c.center))

	# --- NPC — поближе к старту
	var near: Array = clearings.duplicate()
	near.sort_custom(func(a, b): return a.center.distance_to(start_c.center) < b.center.distance_to(start_c.center))
	var npc_ids: Array = f.get("npcs", [])
	for i in npc_ids.size():
		var c: Dictionary = near[mini(i, near.size() - 1)]
		result.npcs.append({"id": npc_ids[i], "cell": _free_cell(grid, w, h, c, rng, occupied)})

	# --- Сундуки, сейф
	for i in int(f.get("chests", 2)):
		var c: Dictionary = pool_clearings[rng.randi() % pool_clearings.size()]
		result.chests.append(_free_cell(grid, w, h, c, rng, occupied))
	if f.get("safe", false):
		var c: Dictionary = pool_clearings[rng.randi() % pool_clearings.size()]
		result.safe = {"id": _pick_safe(rng, used), "cell": _free_cell(grid, w, h, c, rng, occupied), "reward": "loot"}

	# --- Враги и босс
	var pool: Array = f.get("pool", ["syntax_error"])
	var enemy_clearings := pool_clearings.duplicate()
	if has_chasm:
		enemy_clearings.sort_custom(func(a, b): return a.side > b.side)
	for i in int(f.get("enemies", 3)):
		var c: Dictionary = enemy_clearings[i % enemy_clearings.size()]
		result.enemies.append({"id": pool[rng.randi() % pool.size()], "cell": _free_cell(grid, w, h, c, rng, occupied), "area": _area_of(c)})
	if f.has("boss"):
		var c: Dictionary = far[0]
		result.boss = {"id": f.boss, "cell": _free_cell(grid, w, h, c, rng, occupied), "area": _area_of(c)}
	return result


# ---------------------------------------------------------------- Утилиты

static func _exit(n: Dictionary, cell: Vector2i, node: Dictionary) -> Dictionary:
	var under: bool = WorldData.NODE_KINDS.get(n.get("kind", ""), {}).get("underground", false)
	var kind := "path"
	if under:
		kind = "crypt" if n.get("kind") == "tomb" else ("stairs_down" if n.get("kind") == "dungeon" else "cave")
	return {"to": n.id, "to_name": n.get("name", ""), "to_kind": n.get("kind", ""), "cell": cell, "kind": kind, "sealed": false}


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
				if grid[y * w + x] != PATH:
					grid[y * w + x] = FLOOR


static func _carve_path(grid: PackedByteArray, w: int, h: int, a: Vector2, b: Vector2, rng: RandomNumberGenerator) -> void:
	var mid := (a + b) * 0.5 + (b - a).orthogonal().normalized() * a.distance_to(b) * rng.randf_range(-0.3, 0.3)
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
	for attempt in 40:
		var a := rng.randf() * TAU
		var r: float = rng.randf() * maxf(c.radius - 1.5, 0.5)
		var cell := Vector2i(c.center + Vector2(cos(a), sin(a)) * r)
		if _in(w, h, cell.x, cell.y) and grid[cell.y * w + cell.x] in [FLOOR, PATH] and not occupied.has(cell):
			occupied[cell] = true
			return cell
	return Vector2i(c.center)


static func _pos_of(n: Dictionary) -> Vector2:
	var p: Array = n.get("pos", [0.5, 0.5])
	return Vector2(float(p[0]), float(p[1]))


## Точка на краю карты (клетка с x = 1 / w−2 или y = 1 / h−2) по направлению dir от центра.
## Не ближе 6 клеток к углам, не на пропасти и не ближе 8 клеток к уже занятым выходам.
static func _border_point(w: int, h: int, dir: Vector2, chasm: Rect2i, used: Array) -> Vector2i:
	var c := Vector2(w * 0.5, h * 0.5)
	var tx := INF
	var ty := INF
	if absf(dir.x) > 0.0001:
		tx = ((w - 2 - c.x) if dir.x > 0 else (1 - c.x)) / dir.x
	if absf(dir.y) > 0.0001:
		ty = ((h - 2 - c.y) if dir.y > 0 else (1 - c.y)) / dir.y
	var vertical := tx < ty
	var p := c + dir * minf(tx, ty)
	var cell := Vector2i(roundi(p.x), roundi(p.y))
	if vertical:
		cell.x = w - 2 if dir.x > 0 else 1
	else:
		cell.y = h - 2 if dir.y > 0 else 1
	for attempt in 12:
		if vertical:
			cell.y = clampi(cell.y, 6, h - 7)
		else:
			cell.x = clampi(cell.x, 6, w - 7)
			if chasm.size.x > 0 and cell.x > chasm.position.x - 4 and cell.x < chasm.end.x + 3:
				cell.x = chasm.position.x - 4 if p.x < chasm.position.x + chasm.size.x * 0.5 else chasm.end.x + 3
		var clash := false
		for u in used:
			if Vector2(u).distance_to(Vector2(cell)) < 8.0:
				clash = true
		if not clash:
			break
		var step := 8 * (1 if attempt % 2 == 0 else -1) * (attempt / 2 + 1)
		if vertical:
			cell.y += step
		else:
			cell.x += step
	return cell


## Направление «наружу» для клетки на краю карты.
static func _outward(w: int, h: int, cell: Vector2i) -> Vector2i:
	if cell.x <= 1:
		return Vector2i(-1, 0)
	if cell.x >= w - 2:
		return Vector2i(1, 0)
	if cell.y <= 1:
		return Vector2i(0, -1)
	return Vector2i(0, 1)


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
