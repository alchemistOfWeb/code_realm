extends CharacterBody3D
## Порченый автоматон: PATROL → ALERT («!», 0.8 с) → CHASE (путь по сетке AStarGrid2D) → RETURN.
## Касание игрока — карточный бой (DungeonWorld слушает сигнал contact).

signal contact(enemy)

enum State { PATROL, ALERT, CHASE, RETURN, FROZEN }

const MODEL := preload("res://assets/models/dungeon/character-orc.glb")
const VISION_RANGE := 6.5
const LOSE_RANGE := 10.0
const PATROL_SPEED := 1.3
const CHASE_SPEED := 2.9
const CONTACT_DIST := 0.85

var enemy_data: Dictionary = {}
var state := State.PATROL
var origin: Vector3
var room_rect: Rect2i
var astar: AStarGrid2D
var player: Node3D
var is_boss := false

var _target: Vector3
var _path: Array = []
var _repath := 0.0
var _alert_t := 0.0
var _model: Node3D
var _anim: AnimationPlayer
var _alert_label: Label3D
var _cur_anim := ""


func setup(data: Dictionary, pos: Vector3, rect: Rect2i, grid_astar: AStarGrid2D, player_node: Node3D) -> void:
	enemy_data = data
	position = pos
	origin = pos
	room_rect = rect
	astar = grid_astar
	player = player_node
	is_boss = data.get("is_boss", false) or data.get("is_miniboss", false)
	_target = _random_patrol_point()


func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.26
	capsule.height = 0.8
	shape.shape = capsule
	shape.position.y = 0.4
	add_child(shape)
	collision_layer = 2
	collision_mask = 1
	_model = MODEL.instantiate()
	if is_boss:
		_model.scale = Vector3.ONE * 1.6
	add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false)
	CharacterRig.setup_loops(_anim)
	var color := Color.from_string(enemy_data.get("color", "#C0392B"), Palette.HP)
	CharacterRig.tint(_model, Color(0.75, 0.7, 0.62).lerp(color, 0.45), color.darkened(0.5))
	# Светящееся «ядро» автоматона
	var core := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 0.07
	sphere.height = 0.14
	core.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color.lightened(0.3)
	mat.emission_energy_multiplier = 3.0
	core.material_override = mat
	core.position = Vector3(0, (1.25 if is_boss else 0.95), 0)
	add_child(core)
	var light := OmniLight3D.new()
	light.light_color = color
	light.light_energy = 0.8
	light.omni_range = 2.0
	light.position = core.position
	add_child(light)
	var name_label := Label3D.new()
	name_label.text = enemy_data.get("name", "?")
	name_label.font_size = 40
	name_label.outline_size = 10
	name_label.modulate = color.lightened(0.4)
	name_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	name_label.position = Vector3(0, 1.3 if not is_boss else 1.8, 0)
	name_label.pixel_size = 0.004
	name_label.no_depth_test = true
	add_child(name_label)
	_alert_label = Label3D.new()
	_alert_label.text = "!"
	_alert_label.font_size = 96
	_alert_label.outline_size = 16
	_alert_label.modulate = Palette.ENERGY
	_alert_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_alert_label.position = Vector3(0, 1.6 if not is_boss else 2.2, 0)
	_alert_label.pixel_size = 0.005
	_alert_label.no_depth_test = true
	_alert_label.visible = false
	add_child(_alert_label)
	_play("idle")


func _physics_process(delta: float) -> void:
	if state == State.FROZEN or player == null:
		return
	var dist := global_position.distance_to(player.global_position)
	match state:
		State.PATROL:
			if dist < VISION_RANGE and _sees_player():
				state = State.ALERT
				_alert_t = 0.8
				_alert_label.visible = true
				Audio.play("gear", 0.2)
				_play("idle")
				return
			if global_position.distance_to(_target) < 0.3:
				_target = _random_patrol_point()
			_move_toward(_target, PATROL_SPEED, delta)
		State.ALERT:
			_alert_t -= delta
			_face(player.global_position)
			if _alert_t <= 0.0:
				state = State.CHASE
		State.CHASE:
			if dist > LOSE_RANGE:
				state = State.RETURN
				_alert_label.visible = false
				_path.clear()
				return
			_repath -= delta
			if _repath <= 0.0 or _path.is_empty():
				_repath = 0.4
				_path = _grid_path(player.global_position)
			_follow_path(CHASE_SPEED, delta, player.global_position)
		State.RETURN:
			_repath -= delta
			if _repath <= 0.0 or _path.is_empty():
				_repath = 0.6
				_path = _grid_path(origin)
			_follow_path(PATROL_SPEED * 1.4, delta, origin)
			if global_position.distance_to(origin) < 0.4:
				state = State.PATROL
	if state in [State.CHASE, State.ALERT] and dist < CONTACT_DIST:
		freeze()
		contact.emit(self)


func freeze() -> void:
	state = State.FROZEN
	velocity = Vector3.ZERO
	_play("idle")


func resume() -> void:
	state = State.RETURN
	_alert_label.visible = false


func die() -> void:
	state = State.FROZEN
	collision_layer = 0
	_alert_label.visible = false
	if _anim and _anim.has_animation("die"):
		_anim.play("die")
	var tw := create_tween()
	tw.tween_interval(0.9)
	tw.tween_property(self, "scale", Vector3(1, 0.05, 1), 0.4)
	tw.tween_callback(queue_free)


func _sees_player() -> bool:
	# Видимость по сетке: проверяем клетки вдоль линии
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
		pts.append(Vector3(ids[i].x + 0.5, 0, ids[i].y + 0.5))
	return pts


func _follow_path(speed: float, delta: float, final: Vector3) -> void:
	if _path.is_empty():
		_move_toward(final, speed, delta)
		return
	var next: Vector3 = _path[0]
	if Vector2(global_position.x, global_position.z).distance_to(Vector2(next.x, next.z)) < 0.25:
		_path.pop_front()
		if _path.is_empty():
			return
		next = _path[0]
	_move_toward(next, speed, delta)


func _move_toward(point: Vector3, speed: float, _delta: float) -> void:
	var d := point - global_position
	d.y = 0
	if d.length() < 0.05:
		velocity = Vector3.ZERO
		_play("idle")
		return
	var dir := d.normalized()
	velocity = dir * speed
	move_and_slide()
	_face(global_position + dir)
	_play("sprint" if speed > 2.0 else "walk")


func _face(point: Vector3) -> void:
	var d := point - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		_model.rotation.y = lerp_angle(_model.rotation.y, atan2(d.x, d.z), 0.25)


func _random_patrol_point() -> Vector3:
	var x := randf_range(room_rect.position.x + 1.0, room_rect.end.x - 1.0)
	var z := randf_range(room_rect.position.y + 1.0, room_rect.end.y - 1.0)
	return Vector3(x, 0, z)


func _play(anim_name: String) -> void:
	if _cur_anim == anim_name or _anim == null or not _anim.has_animation(anim_name):
		return
	_cur_anim = anim_name
	_anim.play(anim_name, 0.2)
