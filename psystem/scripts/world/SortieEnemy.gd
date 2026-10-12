class_name SortieEnemy
extends CharacterBody3D
## Враг вылазки: PATROL → ALERT («!», 0.8 с) → CHASE (путь по сетке AStarGrid2D) → RETURN.
## Касание игрока — карточный бой (SortieWorld слушает сигнал contact). Ходит только по
## проходимым клеткам, поэтому никогда не падает в пропасть.

signal contact(enemy)

enum State { PATROL, ALERT, CHASE, RETURN, FROZEN }

const VISION_RANGE := 7.5
const LOSE_RANGE := 12.0
const PATROL_SPEED := 1.4
const CHASE_SPEED := 3.3
const CONTACT_DIST := 1.1

var enemy_data: Dictionary = {}
var index := 0                 # номер врага на уровне (для сохранения побед)
var state := State.PATROL
var origin: Vector3
var area: Rect2i
var astar: AStarGrid2D
var player: Node3D
var is_boss := false

var _rig: MonsterRig
var _target: Vector3
var _path: Array = []
var _repath := 0.0
var _alert_t := 0.0
var _alert_label: Label3D
var _y := 0.0


func setup(data: Dictionary, pos: Vector3, patrol_area: Rect2i, grid_astar: AStarGrid2D, player_node: Node3D) -> void:
	enemy_data = data
	position = pos
	origin = pos
	_y = pos.y
	area = patrol_area
	astar = grid_astar
	player = player_node
	is_boss = data.get("is_boss", false) or data.get("is_miniboss", false)
	_target = _random_patrol_point()


func _ready() -> void:
	collision_layer = 2
	collision_mask = 0
	var tint := Color.from_string(enemy_data.get("model_tint", "#FFFFFF"), Color.WHITE)
	var size_mul: float = float(enemy_data.get("model_size", 1.0)) * (1.25 if is_boss and not enemy_data.has("model_size") else 1.0)
	_rig = MonsterRig.create(enemy_data.get("model", "Slime"), size_mul, tint)
	add_child(_rig)
	if not WorldStyle.quality().shadows:
		add_child(WorldStyle.blob_shadow(0.4 * size_mul))
	var h := _rig.height()
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 0.4 if not is_boss else 0.8
	cyl.height = maxf(h, 0.6)
	shape.shape = cyl
	shape.position.y = cyl.height * 0.5
	add_child(shape)
	var color := Color.from_string(enemy_data.get("color", "#C0392B"), Palette.HP)
	var title := Label3D.new()
	title.text = "%s\n%s" % [Loc.f(enemy_data, "name"), Loc.f(enemy_data, "title")]
	title.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	title.font_size = 34
	title.outline_size = 10
	title.modulate = color.lightened(0.45)
	title.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	title.position = Vector3(0, h + 0.45, 0)
	title.pixel_size = 0.004
	title.no_depth_test = true
	add_child(title)
	_alert_label = Label3D.new()
	_alert_label.text = "!"
	_alert_label.font_size = 96
	_alert_label.outline_size = 16
	_alert_label.modulate = Color("#FF3B3B")
	_alert_label.outline_modulate = Color(0.15, 0, 0, 1)
	_alert_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert_label.position = Vector3(0, h + 0.95, 0)
	_alert_label.pixel_size = 0.005
	_alert_label.no_depth_test = true
	_alert_label.visible = false
	add_child(_alert_label)
	if is_boss:
		var aura := OmniLight3D.new()
		aura.light_color = color
		aura.light_energy = 1.4
		aura.omni_range = 4.5
		aura.position.y = h * 0.6
		add_child(aura)


func _physics_process(delta: float) -> void:
	if state == State.FROZEN or player == null or not is_instance_valid(player):
		return
	var dist := global_position.distance_to(player.global_position)
	match state:
		State.PATROL:
			if dist < VISION_RANGE * (1.3 if is_boss else 1.0) and _sees_player():
				state = State.ALERT
				_alert_t = 0.8
				_alert_label.visible = true
				Audio.play("gear", 0.2)
				_rig.play("idle")
				return
			if _flat_dist(_target) < 0.3:
				_target = _random_patrol_point()
			_move_toward(_target, PATROL_SPEED)
		State.ALERT:
			_alert_t -= delta
			_face(player.global_position)
			if _alert_t <= 0.0:
				state = State.CHASE
		State.CHASE:
			if dist > LOSE_RANGE or player.global_position.y < -1.0:
				state = State.RETURN
				_alert_label.visible = false
				_path.clear()
				return
			_repath -= delta
			if _repath <= 0.0 or _path.is_empty():
				_repath = 0.4
				_path = _grid_path(player.global_position)
			_follow_path(CHASE_SPEED * (0.85 if is_boss else 1.0), player.global_position)
		State.RETURN:
			_repath -= delta
			if _repath <= 0.0 or _path.is_empty():
				_repath = 0.6
				_path = _grid_path(origin)
			_follow_path(PATROL_SPEED * 1.4, origin)
			if _flat_dist(origin) < 0.4:
				state = State.PATROL
	var reach := CONTACT_DIST + (0.6 if is_boss else 0.0)
	if state in [State.CHASE, State.ALERT] and dist < reach and absf(player.global_position.y - global_position.y) < 1.5:
		freeze()
		_rig.play_once("attack")
		contact.emit(self)


func freeze() -> void:
	state = State.FROZEN
	velocity = Vector3.ZERO


func resume() -> void:
	state = State.RETURN
	_alert_label.visible = false
	_rig.play("idle")


func die() -> void:
	state = State.FROZEN
	collision_layer = 0
	_alert_label.visible = false
	var t := _rig.play_once("death")
	var tw := create_tween()
	tw.tween_interval(maxf(t, 0.6))
	tw.tween_property(self, "scale", Vector3(1, 0.05, 1), 0.4)
	tw.tween_callback(queue_free)


func _flat_dist(p: Vector3) -> float:
	return Vector2(global_position.x, global_position.z).distance_to(Vector2(p.x, p.z))


func _sees_player() -> bool:
	var a := Vector2(global_position.x, global_position.z)
	var b := Vector2(player.global_position.x, player.global_position.z)
	var steps := int(a.distance_to(b) * 2.0) + 1
	for i in steps:
		var p := a.lerp(b, float(i) / steps)
		var cell := Vector2i(int(floor(p.x)), int(floor(p.y)))
		if astar.is_in_boundsv(cell) and astar.is_point_solid(cell):
			return false
	return true


func _grid_path(to: Vector3) -> Array:
	var from_cell := Vector2i(int(floor(global_position.x)), int(floor(global_position.z)))
	var to_cell := Vector2i(int(floor(to.x)), int(floor(to.z)))
	if not astar.is_in_boundsv(from_cell) or not astar.is_in_boundsv(to_cell) or astar.is_point_solid(to_cell):
		return []
	var ids := astar.get_id_path(from_cell, to_cell, true)
	var pts: Array = []
	for i in range(1, ids.size()):
		pts.append(Vector3(ids[i].x + 0.5, _y, ids[i].y + 0.5))
	return pts


func _follow_path(speed: float, final: Vector3) -> void:
	if _path.is_empty():
		var c := Vector2i(int(floor(final.x)), int(floor(final.z)))
		if astar.is_in_boundsv(c) and not astar.is_point_solid(c):
			_move_toward(final, speed)
		else:
			_rig.play("idle")
		return
	var next: Vector3 = _path[0]
	if _flat_dist(next) < 0.25:
		_path.pop_front()
		if _path.is_empty():
			return
		next = _path[0]
	_move_toward(next, speed)


func _move_toward(point: Vector3, speed: float) -> void:
	var d := point - global_position
	d.y = 0
	if d.length() < 0.05:
		velocity = Vector3.ZERO
		_rig.play("idle")
		return
	var dir := d.normalized()
	var next := global_position + dir * speed * get_physics_process_delta_time()
	var cell := Vector2i(int(floor(next.x)), int(floor(next.z)))
	if astar.is_in_boundsv(cell) and astar.is_point_solid(cell):
		_rig.play("idle")
		return
	global_position = Vector3(next.x, _y, next.z)
	_face(global_position + dir)
	_rig.play("move")


func _face(point: Vector3) -> void:
	var d := point - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		_rig.rotation.y = lerp_angle(_rig.rotation.y, atan2(d.x, d.z), 0.25)


func _random_patrol_point() -> Vector3:
	for i in 12:
		var c := Vector2i(randi_range(area.position.x, area.end.x - 1), randi_range(area.position.y, area.end.y - 1))
		if astar.is_in_boundsv(c) and not astar.is_point_solid(c):
			return Vector3(c.x + 0.5, _y, c.y + 0.5)
	return origin
