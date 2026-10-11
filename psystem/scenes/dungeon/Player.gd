extends CharacterBody3D
## Игрок в экспедиции: WASD/стрелки — движение (относительно камеры сверху), Shift — бег.
## Модель — Kenney character-human (анимации idle/walk/sprint).

const SPEED := 3.2
const SPRINT := 5.0
const MODEL := preload("res://assets/models/dungeon/character-human.glb")

var input_enabled := true
var _model: Node3D
var _anim: AnimationPlayer
var _step_timer := 0.0
var _current_anim := ""


func _ready() -> void:
	add_to_group("player")
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.24
	capsule.height = 0.8
	shape.shape = capsule
	shape.position.y = 0.4
	add_child(shape)
	_model = MODEL.instantiate()
	add_child(_model)
	_anim = _model.find_child("AnimationPlayer", true, false)
	CharacterRig.setup_loops(_anim)
	CharacterRig.tint(_model, Color("#D8E6FF"))
	_play("idle")
	# Фонарь искателя
	var lantern := OmniLight3D.new()
	lantern.position = Vector3(0, 1.6, 0.3)
	lantern.light_color = Color("#FFD9A0")
	lantern.light_energy = 1.6
	lantern.omni_range = 6.5
	lantern.omni_attenuation = 1.2
	add_child(lantern)


func _physics_process(delta: float) -> void:
	var dir := Vector3.ZERO
	if input_enabled:
		var v := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
		dir = Vector3(v.x, 0, v.y)
	var sprint := input_enabled and Input.is_action_pressed("sprint")
	var speed := SPRINT if sprint else SPEED
	velocity.x = dir.x * speed
	velocity.z = dir.z * speed
	velocity.y = 0.0
	move_and_slide()
	if dir.length() > 0.1:
		var target_rot := atan2(dir.x, dir.z)
		_model.rotation.y = lerp_angle(_model.rotation.y, target_rot, minf(1.0, delta * 12.0))
		_play("sprint" if sprint else "walk")
		_step_timer -= delta
		if _step_timer <= 0.0:
			_step_timer = 0.26 if sprint else 0.38
			Audio.play_step()
	else:
		_play("idle")


func face(point: Vector3) -> void:
	var d := point - global_position
	_model.rotation.y = atan2(d.x, d.z)


func _play(anim_name: String) -> void:
	if _current_anim == anim_name or _anim == null or not _anim.has_animation(anim_name):
		return
	_current_anim = anim_name
	_anim.play(anim_name, 0.15)


func play_once(anim_name: String) -> void:
	if _anim and _anim.has_animation(anim_name):
		_current_anim = anim_name
		_anim.play(anim_name, 0.1)
