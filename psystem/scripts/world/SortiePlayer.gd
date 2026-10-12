class_name SortiePlayer
extends CharacterBody3D
## Герой в вылазке: камера от третьего лица (как в WoW), WASD относительно камеры,
## Shift — бег (тратит выносливость), Space — прыжок (с «койот-таймом» и буфером), падение ниже FALL_Y — гибель.
## Камера: ПКМ/СКМ — вращение, колесо — приближение, Q/R — поворот.

signal fell()

const WALK_SPEED := 3.0
const RUN_SPEED := 4.6
const SPRINT_SPEED := 7.0
const JUMP_VELOCITY := 6.3
const GRAVITY := 17.0
const AIR_CONTROL := 0.55
const COYOTE := 0.12
const JUMP_BUFFER := 0.15
const FALL_Y := -4.5
const REGEN_DELAY := 0.6
const EXHAUST_RECOVER := 0.3     # бег снова доступен после восстановления 30%

var input_enabled := true
## Ниже этой высоты — гибель (над рекой выше, чем над пропастью).
var fall_y := FALL_Y
var rig: HeroRig
var stamina := 6.0
var max_stamina := 6.0
var exhausted := false
var dead := false
var sprinting := false
## Перегруз (вес больше переносимого): медленный шаг, бег недоступен.
var overloaded := false
var _gear_key := ""

var cam_root: Node3D
var camera: Camera3D
var _spring: SpringArm3D
var _pitch_node: Node3D
var cam_yaw := 0.0
var _cam_pitch := deg_to_rad(-48.0)
var _cam_dist := 8.0
var _cam_drag := false

var _coyote := 0.0
var _buffer := 0.0
var _regen_wait := 0.0
var _land_lock := 0.0
var _jumping := false
var _step := 0.0


func _ready() -> void:
	add_to_group("player")
	collision_layer = 1
	collision_mask = 1
	floor_snap_length = 0.35
	floor_max_angle = deg_to_rad(50)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.7
	shape.shape = capsule
	shape.position.y = 0.85
	add_child(shape)
	rig = HeroRig.new()
	add_child(rig)
	rig.apply_look(GameManager.player_data.get("look", Appearance.default_look()))
	refresh_gear()
	stamina = max_stamina
	_build_camera.call_deferred()
	# Фонарь героя: тёплый свет вокруг (в подземельях особенно важен)
	var lantern := OmniLight3D.new()
	lantern.position = Vector3(0, 2.2, 0.4)
	lantern.light_color = Color("#FFD9A0")
	lantern.light_energy = 0.9
	lantern.omni_range = 7.0
	lantern.omni_attenuation = 1.3
	lantern.name = "Lantern"
	add_child(lantern)


func _build_camera() -> void:
	cam_root = Node3D.new()
	cam_root.top_level = true
	add_child(cam_root)
	cam_root.global_position = global_position + Vector3(0, 1.4, 0)
	_pitch_node = Node3D.new()
	cam_root.add_child(_pitch_node)
	_spring = SpringArm3D.new()
	_spring.collision_mask = 4          # слой стен/скал: камера не проходит сквозь них
	_spring.margin = 0.3
	_spring.spring_length = _cam_dist
	_pitch_node.add_child(_spring)
	camera = Camera3D.new()
	camera.fov = 55
	camera.far = 260
	_spring.add_child(camera)
	camera.current = true
	_apply_camera()


## Вид снаряжения, запас бега и перегруз — после смены экипировки (инвентарь в вылазке).
func refresh_gear() -> void:
	var outfit := GameManager.hero_outfit()
	if str(outfit) != _gear_key:
		_gear_key = str(outfit)
		rig.apply_equipment(outfit)
	var attrs := GameManager.effective_attributes()
	max_stamina = XPCalculator.RUN_STAMINA + float(attrs.get("max_stamina", 5) - 5) * 0.25
	stamina = minf(stamina, max_stamina)
	overloaded = GameManager.is_overloaded()


func set_lantern(energy: float) -> void:
	var l: OmniLight3D = get_node_or_null("Lantern")
	if l:
		l.light_energy = energy


func face_yaw(yaw: float) -> void:
	rig.rotation.y = yaw
	cam_yaw = yaw + PI
	_apply_camera()


func face(point: Vector3) -> void:
	var d := point - global_position
	if Vector2(d.x, d.z).length() > 0.01:
		rig.rotation.y = atan2(d.x, d.z)


func _apply_camera() -> void:
	if cam_root == null:
		return
	cam_root.rotation.y = cam_yaw
	_pitch_node.rotation.x = _cam_pitch
	_spring.spring_length = _cam_dist


## Мышь для камеры (вызывает SortieWorld: герой живёт внутри SubViewport).
func handle_camera_input(event: InputEvent) -> void:
	if dead:
		return
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				_cam_drag = event.pressed
			MOUSE_BUTTON_WHEEL_UP:
				if event.pressed:
					_cam_dist = clampf(_cam_dist - 0.6, 3.0, 13.0)
					_apply_camera()
			MOUSE_BUTTON_WHEEL_DOWN:
				if event.pressed:
					_cam_dist = clampf(_cam_dist + 0.6, 3.0, 13.0)
					_apply_camera()
	elif event is InputEventMouseMotion and _cam_drag:
		var sens: float = float(Settings.get_value("mouse_sensitivity")) * 0.006
		cam_yaw -= event.relative.x * sens
		_cam_pitch = clampf(_cam_pitch - event.relative.y * sens, deg_to_rad(-75), deg_to_rad(-8))
		_apply_camera()


func _physics_process(delta: float) -> void:
	if cam_root and not dead:   # после падения камера остаётся на краю и смотрит вниз
		cam_root.global_position = cam_root.global_position.lerp(global_position + Vector3(0, 1.45, 0), minf(1.0, delta * 10.0))
		var turn := Input.get_axis("camera_right", "camera_left") if input_enabled else 0.0
		if turn != 0.0:
			cam_yaw += turn * 1.9 * delta
			_apply_camera()
	if dead:
		velocity.y -= GRAVITY * delta
		move_and_slide()
		return
	var on_floor := is_on_floor()
	# Ввод относительно камеры
	var dir := Vector3.ZERO
	if input_enabled:
		var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		dir = Vector3(v.x, 0, v.y).rotated(Vector3.UP, cam_yaw)
	var moving := dir.length() > 0.1
	# Бег и выносливость
	var want_sprint := input_enabled and moving and Input.is_action_pressed("sprint") and not overloaded
	sprinting = want_sprint and not exhausted and stamina > 0.0
	if sprinting:
		stamina = maxf(0.0, stamina - delta)
		_regen_wait = REGEN_DELAY
		if stamina <= 0.0:
			exhausted = true
	else:
		_regen_wait -= delta
		if _regen_wait <= 0.0:
			stamina = minf(max_stamina, stamina + XPCalculator.RUN_STAMINA_REGEN * delta)
		if exhausted and stamina >= max_stamina * EXHAUST_RECOVER:
			exhausted = false
	var speed := SPRINT_SPEED if sprinting else RUN_SPEED
	if exhausted and moving:
		speed = WALK_SPEED
	if overloaded:
		speed = RUN_SPEED * XPCalculator.OVERLOAD_SPEED
	# Горизонтальное движение (в воздухе — ограниченный контроль)
	var target := dir.normalized() * speed if moving else Vector3.ZERO
	var accel := 14.0 if on_floor else 14.0 * AIR_CONTROL
	velocity.x = move_toward(velocity.x, target.x, accel * speed * delta * 0.5)
	velocity.z = move_toward(velocity.z, target.z, accel * speed * delta * 0.5)
	if on_floor and not moving:
		velocity.x = move_toward(velocity.x, 0.0, 30.0 * delta)
		velocity.z = move_toward(velocity.z, 0.0, 30.0 * delta)
	# Прыжок: койот-тайм и буфер нажатия
	_coyote = COYOTE if on_floor else _coyote - delta
	if input_enabled and Input.is_action_just_pressed("jump"):
		_buffer = JUMP_BUFFER
	else:
		_buffer -= delta
	if _buffer > 0.0 and _coyote > 0.0:
		velocity.y = JUMP_VELOCITY
		_buffer = 0.0
		_coyote = 0.0
		_jumping = true
		rig.play_once("Jump_Start", 0.05, 1.4)
		Audio.play("whoosh", 0.1)
	elif not on_floor:
		velocity.y -= GRAVITY * delta
	var was_air := not on_floor
	move_and_slide()
	# Приземление
	if was_air and is_on_floor():
		if _jumping or velocity.y < -2.0:
			_land_lock = 0.18
			rig.play_once("Jump_Land", 0.05, 1.6)
			Audio.play_step()
		_jumping = false
	# Поворот модели и анимации
	if moving:
		var yaw := atan2(dir.x, dir.z)
		rig.rotation.y = lerp_angle(rig.rotation.y, yaw, minf(1.0, delta * 12.0))
	_land_lock -= delta
	if not is_on_floor():
		if rig.current_anim != "Jump_Start" or not rig.anim.is_playing():
			rig.play("Jump", 0.15)
	elif _land_lock <= 0.0:
		var hspeed := Vector2(velocity.x, velocity.z).length()
		if hspeed < 0.3:
			rig.play("Idle")
		elif sprinting:
			rig.play("Sprint")
		elif hspeed < 3.5:
			rig.play("Walk")
		else:
			rig.play("Jog_Fwd")
		if hspeed > 0.3:
			_step -= delta
			if _step <= 0.0:
				_step = 0.26 if sprinting else 0.36
				Audio.play_step()
	if global_position.y < fall_y and not dead:
		dead = true
		rig.play_once("Death01")
		fell.emit()


## Анимация «взаимодействия» (сундук, рычаг) или начала боя.
func act(anim_name: String = "Interact") -> void:
	rig.play_once(anim_name, 0.08, 1.2)
	_land_lock = 0.5
