class_name DungeonGenerator
extends RefCounted
## Процедурная генерация подземной подлокации (BSP). Только данные — 3D строит LevelBuilder (вылазка SortieWorld).
##
## Сетка клеток (1 клетка = 1 м): 0 — стена, 1 — пол комнаты, 2 — коридор.
## Комнаты — листья BSP-дерева; соседние поддеревья соединяются L-образными коридорами шириной 2.
## Старт — комната у угла, выход — самая дальняя по BFS. Все входы в комнату выхода закрыты
## решётками: их открывает загадка (gate_mode "riddle") или Страж Моста (gate_mode "warden").

const MAX_FLOORS := 3
const FLOOR_NAMES := ["Ржавые галереи", "Котельные глубины", "Сердце Механизма"]
const NPC_POOL := ["greta", "oracle", "lio", "rzhavchik", "cipher"]
const MIN_LEAF := 9
const WALL := 0
const FLOOR := 1
const CORRIDOR := 2

## used: {"riddles": [], "safes": []} — что уже было в этой вылазке (без повторов).
## opts (подземная подлокация из data/locations.json): npcs, enemies, pool, chests, safe, riddle_gate,
## warden, boss, neighbors [{id, name, kind}], entry (id соседа, откуда пришли). Пустой opts — старый режим.
static func generate(floor_num: int, seed_value: int, used: Dictionary = {}, opts: Dictionary = {}) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var w := 30 + floor_num * 6
	var h := 26 + floor_num * 4
	var grid := PackedByteArray()
	grid.resize(w * h)
	grid.fill(WALL)

	# --- BSP
	var tree := _split(Rect2i(1, 1, w - 2, h - 2), rng, 0)
	var rooms: Array = []
	_make_rooms(tree, rng, rooms)
	for r in rooms:
		var rect: Rect2i = r.rect
		for y in range(rect.position.y, rect.end.y):
			for x in range(rect.position.x, rect.end.x):
				grid[y * w + x] = FLOOR
	_connect(tree, grid, w, rng)

	# --- Старт и выход
	rooms.sort_custom(func(a, b): return a.center.x + a.center.y < b.center.x + b.center.y)
	for i in rooms.size():
		rooms[i].id = i
	var start_room: Dictionary = rooms[0]
	var dist := _bfs(grid, w, h, start_room.center)
	var exit_room: Dictionary = rooms[-1]
	var best := -1
	for r in rooms:
		var d: int = dist.get(r.center, -1)
		if d > best:
			best = d
			exit_room = r

	# --- Решётки на входах в комнату выхода
	var gates: Array = []
	var er: Rect2i = exit_room.rect
	for y in range(er.position.y - 1, er.end.y + 1):
		for x in range(er.position.x - 1, er.end.x + 1):
			if er.has_point(Vector2i(x, y)) or grid[y * w + x] == WALL:
				continue
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				if er.has_point(Vector2i(x, y) + d):
					gates.append(Vector2i(x, y))
					break

	var gated: bool = opts.is_empty() or opts.get("riddle_gate", false) or opts.get("warden", false)
	if not gated:
		gates.clear()
	var result := {
		"w": w, "h": h, "grid": grid, "rooms": rooms, "floor": floor_num, "underground": true, "exits": [],
		"name": FLOOR_NAMES[clampi(floor_num - 1, 0, FLOOR_NAMES.size() - 1)],
		"start": start_room.center, "exit": exit_room.center, "exit_room": exit_room.id,
		"gates": gates, "gate_mode": "riddle", "riddle_id": "", "warden_cell": Vector2i(-1, -1),
		"enemies": [], "npcs": [], "safe": {}, "chests": [], "boss": {},
		"decor": {"columns": [], "barrels": [], "gears": [], "banners": [], "pipes": []},
	}

	var pool: Array = rooms.filter(func(r): return r.id != start_room.id and r.id != exit_room.id)
	pool.shuffle()
	var occupied := {}
	occupied[start_room.center] = true
	occupied[exit_room.center] = true

	# --- Загадка или Страж
	var riddles: Array = RiddleIds.list().filter(func(id): return not id in used.get("riddles", []))
	if riddles.is_empty():
		riddles = RiddleIds.list()
	result.riddle_id = riddles[rng.randi() % riddles.size()]
	var want_warden: bool = opts.get("warden", false) if not opts.is_empty() else (floor_num >= 2 and rng.randf() < 0.45)
	if want_warden and not gates.is_empty():
		result.gate_mode = "warden"
		var g: Vector2i = gates[0]
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var c: Vector2i = g + d
			if _walkable(grid, w, h, c) and not er.has_point(c) and not c in gates:
				result.warden_cell = c
				break
		if result.warden_cell == Vector2i(-1, -1):
			result.gate_mode = "riddle"

	# --- NPC (по одному на комнату)
	var npcs: Array = NPC_POOL.duplicate()
	_shuffle(npcs, rng)
	if opts.has("npcs"):
		npcs = opts.npcs.duplicate()
	var npc_count := mini(2 if not opts.has("npcs") else npcs.size(), pool.size())
	for i in npc_count:
		var room: Dictionary = pool[i]
		var cell := _free_cell(room.rect, rng, occupied)
		result.npcs.append({"id": npcs[i], "cell": cell, "room": room.id})

	# --- Сейф (обязательно, если на этаже Грета)
	var has_greta: bool = result.npcs.any(func(n): return n.id == "greta")
	var want_safe: bool = opts.get("safe", false) if not opts.is_empty() else (has_greta or rng.randf() < 0.75)
	if want_safe or has_greta:
		var safes: Array = SafeIds.list().filter(func(id): return not id in used.get("safes", []))
		if safes.is_empty():
			safes = SafeIds.list()
		var room: Dictionary = pool[npc_count % pool.size()] if not pool.is_empty() else start_room
		result.safe = {"id": safes[rng.randi() % safes.size()], "cell": _free_cell(room.rect, rng, occupied),
			"reward": "valve" if has_greta else "loot"}

	# --- Враги
	var tier := CardDatabase.all_enemies().filter(func(e): return _regular_enemy(e, floor_num))
	if opts.has("pool"):
		tier = CardDatabase.all_enemies().filter(func(e): return e.id in opts.pool)
	var strong := tier.filter(func(e): return int(e.get("floor", 1)) == floor_num)
	var enemy_count := mini(int(opts.get("enemies", 2 + floor_num)), maxi(1, pool.size() * 2 + 1))
	for i in enemy_count:
		var room: Dictionary = pool[(i + 1) % pool.size()] if not pool.is_empty() else start_room
		if room.id == start_room.id and pool.size() > 0:
			continue
		if tier.is_empty():
			break
		var list: Array = strong if (rng.randf() < 0.6 and not strong.is_empty()) else tier
		var e: Dictionary = list[rng.randi() % list.size()]
		result.enemies.append({"id": e.id, "cell": _free_cell(room.rect, rng, occupied), "room": room.id})

	# --- Босс / мини-босс в комнате выхода
	if not opts.is_empty():
		if opts.get("boss", "") != "":
			result.boss = {"id": opts.boss, "cell": _free_cell(er, rng, occupied)}
	elif floor_num >= MAX_FLOORS:
		result.boss = {"id": "corrupted_compiler", "cell": _free_cell(er, rng, occupied)}
	elif floor_num == 2:
		result.boss = {"id": "data_breach", "cell": _free_cell(er, rng, occupied)}

	# --- Выходы в соседние подлокации. Раскладка не зависит от того, откуда пришли (карта запоминается):
	# самый «западный» сосед по карте локации — в стартовой комнате, следующий — главная лестница
	# в комнате выхода (за решёткой / стражем), остальные — в других комнатах. entry — только точка появления.
	var neighbors: Array = opts.get("neighbors", []).duplicate()
	neighbors.sort_custom(func(a, b): return float(a.get("pos", [0, 0])[0]) < float(b.get("pos", [0, 0])[0]))
	var entry: String = opts.get("entry", "")
	var other_rooms := pool.duplicate()
	other_rooms.reverse()
	for i in neighbors.size():
		var cell: Vector2i
		if i == 0:
			cell = _free_cell(start_room.rect, rng, occupied)
		elif i == 1:
			cell = result.exit
		elif not other_rooms.is_empty():
			cell = _free_cell(other_rooms[(i - 2) % other_rooms.size()].rect, rng, occupied)
		else:
			cell = result.exit
		result.exits.append(_exit(neighbors[i], cell))
	for e in result.exits:
		e.arrive = e.cell
		for o in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(2, 0), Vector2i(-2, 0)]:
			if _walkable(grid, w, h, e.cell + o * 2) and _walkable(grid, w, h, e.cell + o):
				e.arrive = e.cell + o * 2
				break
		if entry != "" and e.to == entry:
			result.start = e.arrive

	# --- Сундуки
	var chest_count: int = int(opts.get("chests", 1 + (1 if rng.randf() < 0.5 else 0)))
	for i in chest_count:
		if pool.is_empty():
			break
		var room: Dictionary = pool[rng.randi() % pool.size()]
		result.chests.append(_free_cell(room.rect, rng, occupied))

	# --- Декор
	for r in rooms:
		var rect: Rect2i = r.rect
		if rect.size.x >= 7 and rect.size.y >= 7:
			for c in [rect.position + Vector2i(1, 1), Vector2i(rect.end.x - 2, rect.position.y + 1),
					Vector2i(rect.position.x + 1, rect.end.y - 2), rect.end - Vector2i(2, 2)]:
				if not occupied.has(c):
					result.decor.columns.append(c)
					occupied[c] = true
		for i in rng.randi_range(0, 2):
			var c := _free_cell(rect, rng, occupied)
			result.decor.barrels.append(c)
		# Шестерни и трубы на северной стене комнаты
		for i in rng.randi_range(1, 3):
			var x := rng.randi_range(rect.position.x, rect.end.x - 1)
			var wall := Vector2i(x, rect.position.y - 1)
			if wall.y >= 0 and grid[wall.y * w + wall.x] == WALL:
				if rng.randf() < 0.6:
					result.decor.gears.append({"cell": wall, "size": rng.randf_range(0.45, 0.9)})
				else:
					result.decor.banners.append(wall)
		if rng.randf() < 0.5 and rect.position.y - 1 >= 0:
			result.decor.pipes.append({"from": Vector2i(rect.position.x, rect.position.y - 1), "to": Vector2i(rect.end.x - 1, rect.position.y - 1)})
	return result


# ---------------------------------------------------------------- BSP

static func _split(rect: Rect2i, rng: RandomNumberGenerator, depth: int) -> Dictionary:
	var node := {"rect": rect, "left": null, "right": null, "room": null}
	var can_h := rect.size.y >= MIN_LEAF * 2
	var can_v := rect.size.x >= MIN_LEAF * 2
	if depth > 5 or (not can_h and not can_v):
		return node
	var vertical := can_v and (not can_h or (rect.size.x > rect.size.y if absi(rect.size.x - rect.size.y) > 4 else rng.randf() < 0.5))
	if vertical:
		var cut := rng.randi_range(MIN_LEAF, rect.size.x - MIN_LEAF)
		node.left = _split(Rect2i(rect.position, Vector2i(cut, rect.size.y)), rng, depth + 1)
		node.right = _split(Rect2i(rect.position + Vector2i(cut, 0), Vector2i(rect.size.x - cut, rect.size.y)), rng, depth + 1)
	else:
		var cut := rng.randi_range(MIN_LEAF, rect.size.y - MIN_LEAF)
		node.left = _split(Rect2i(rect.position, Vector2i(rect.size.x, cut)), rng, depth + 1)
		node.right = _split(Rect2i(rect.position + Vector2i(0, cut), Vector2i(rect.size.x, rect.size.y - cut)), rng, depth + 1)
	return node


static func _make_rooms(node: Dictionary, rng: RandomNumberGenerator, rooms: Array) -> void:
	if node.left == null:
		var leaf: Rect2i = node.rect
		var rw := rng.randi_range(5, maxi(5, leaf.size.x - 3))
		var rh := rng.randi_range(5, maxi(5, leaf.size.y - 3))
		rw = mini(rw, leaf.size.x - 2)
		rh = mini(rh, leaf.size.y - 2)
		var rx := leaf.position.x + 1 + rng.randi_range(0, maxi(0, leaf.size.x - rw - 2))
		var ry := leaf.position.y + 1 + rng.randi_range(0, maxi(0, leaf.size.y - rh - 2))
		var rect := Rect2i(rx, ry, rw, rh)
		var room := {"rect": rect, "center": rect.position + rect.size / 2, "id": -1}
		node.room = room
		rooms.append(room)
		return
	_make_rooms(node.left, rng, rooms)
	_make_rooms(node.right, rng, rooms)


static func _rooms_of(node: Dictionary) -> Array:
	if node.left == null:
		return [node.room]
	return _rooms_of(node.left) + _rooms_of(node.right)


static func _connect(node: Dictionary, grid: PackedByteArray, w: int, rng: RandomNumberGenerator) -> void:
	if node.left == null:
		return
	_connect(node.left, grid, w, rng)
	_connect(node.right, grid, w, rng)
	var best_a: Dictionary = {}
	var best_b: Dictionary = {}
	var best_d := 1 << 30
	for a in _rooms_of(node.left):
		for b in _rooms_of(node.right):
			var d: int = (a.center - b.center).length_squared()
			if d < best_d:
				best_d = d
				best_a = a
				best_b = b
	_carve_l(grid, w, best_a.center, best_b.center, rng.randf() < 0.5)


static func _carve_l(grid: PackedByteArray, w: int, a: Vector2i, b: Vector2i, horizontal_first: bool) -> void:
	var corner := Vector2i(b.x, a.y) if horizontal_first else Vector2i(a.x, b.y)
	_carve_line(grid, w, a, corner)
	_carve_line(grid, w, corner, b)


static func _carve_line(grid: PackedByteArray, w: int, a: Vector2i, b: Vector2i) -> void:
	var step := Vector2i(signi(b.x - a.x), signi(b.y - a.y))
	var p := a
	while true:
		for o in [Vector2i.ZERO, Vector2i(1, 0) if step.y != 0 else Vector2i(0, 1)]:
			var c: Vector2i = p + o
			var i := c.y * w + c.x
			if i >= 0 and i < grid.size() and grid[i] == WALL and c.x > 0 and c.x < w - 1 and c.y > 0:
				grid[i] = CORRIDOR
		if p == b:
			break
		p += step


# ---------------------------------------------------------------- Утилиты

static func _exit(n: Dictionary, cell: Vector2i) -> Dictionary:
	var under: bool = WorldData.NODE_KINDS.get(n.get("kind", ""), {}).get("underground", false)
	return {"to": n.id, "to_name": n.get("name", ""), "to_kind": n.get("kind", ""), "cell": cell,
		"kind": "stairs_down" if under else "stairs_up", "sealed": false}


static func _regular_enemy(e: Dictionary, floor_num: int) -> bool:
	return int(e.get("floor", 1)) <= floor_num and not e.get("is_boss", false) and not e.get("is_miniboss", false)


static func _walkable(grid: PackedByteArray, w: int, h: int, c: Vector2i) -> bool:
	return c.x >= 0 and c.y >= 0 and c.x < w and c.y < h and grid[c.y * w + c.x] != WALL


static func _bfs(grid: PackedByteArray, w: int, h: int, from: Vector2i) -> Dictionary:
	var dist := {from: 0}
	var queue: Array = [from]
	while not queue.is_empty():
		var c: Vector2i = queue.pop_front()
		for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if _walkable(grid, w, h, n) and not dist.has(n):
				dist[n] = dist[c] + 1
				queue.append(n)
	return dist


static func _free_cell(rect: Rect2i, rng: RandomNumberGenerator, occupied: Dictionary) -> Vector2i:
	for attempt in 30:
		var c := Vector2i(rng.randi_range(rect.position.x + 1, maxi(rect.position.x + 1, rect.end.x - 2)),
			rng.randi_range(rect.position.y + 1, maxi(rect.position.y + 1, rect.end.y - 2)))
		if not occupied.has(c):
			occupied[c] = true
			return c
	return rect.position + rect.size / 2


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


## Достижимы ли все клетки пола от старта (для тестов).
static func all_reachable(data: Dictionary) -> bool:
	var dist := _bfs(data.grid, data.w, data.h, data.start)
	for y in data.h:
		for x in data.w:
			if data.grid[y * data.w + x] != WALL and not dist.has(Vector2i(x, y)):
				return false
	return true


class RiddleIds:
	static func list() -> Array:
		return load("res://scenes/dungeon/RiddleScreen.gd").all_ids()


class SafeIds:
	static func list() -> Array:
		return load("res://scenes/dungeon/SafeScreen.gd").all_ids()
