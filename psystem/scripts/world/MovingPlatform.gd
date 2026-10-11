class_name MovingPlatform
extends AnimatableBody3D
## Платформа над пропастью/рекой: ездит между точками a и b (пинг-понг с плавным разгоном) или
## стоит на месте и слегка покачивается. Игрок, стоящий на ней, едет вместе с ней (sync_to_physics).

var point_a := Vector3.ZERO
var point_b := Vector3.ZERO
var period := 4.0          # секунд на путь туда-обратно
var phase := 0.0
var bob := 0.06            # покачивание по высоте (плот на воде)
var _t := 0.0


static func create(a: Vector3, b: Vector3, size: Vector3, mat: Material, travel_time: float, phase_offset: float, visual: Node3D = null) -> MovingPlatform:
	var p := MovingPlatform.new()
	p.point_a = a
	p.point_b = b
	p.period = maxf(travel_time, 0.5)
	p.phase = phase_offset
	p.position = a
	p.sync_to_physics = true
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	cs.position.y = -size.y * 0.5
	p.add_child(cs)
	if visual:
		p.add_child(visual)
	else:
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = size
		mi.mesh = bm
		mi.material_override = mat
		mi.position.y = -size.y * 0.5
		p.add_child(mi)
	return p


func _physics_process(delta: float) -> void:
	_t += delta
	var k := 0.0
	if point_a != point_b:
		var x := fposmod(_t / period + phase, 1.0)
		k = 0.5 - 0.5 * cos(x * TAU)        # 0 → 1 → 0, плавно у концов
	var pos := point_a.lerp(point_b, k)
	pos.y += sin((_t + phase * 7.0) * 2.2) * bob
	position = pos
