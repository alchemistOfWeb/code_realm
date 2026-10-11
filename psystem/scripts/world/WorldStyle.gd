class_name WorldStyle
extends RefCounted
## Общий визуальный стиль 3D-мира: материалы земли и воды, окружение по биому, костёр.

const GROUND := preload("res://shaders/ground.gdshader")
const WATER := preload("res://shaders/water.gdshader")

## Качество графики вылазок (Settings "graphics"): тени, густота растительности, MSAA, свечение,
## разрешение 3D, дальность прорисовки растительности, число деревьев-силуэтов за краем карты.
const QUALITY := {
	"low": {"shadows": false, "tree_shadows": false, "shadow_dist": 0.0, "veg": 0.55, "msaa": false, "glow": false, "scale_3d": 0.85, "lod": 4.0, "shadow_size": 1024, "view_dist": 40.0, "outer_trees": 30},
	"medium": {"shadows": true, "tree_shadows": false, "shadow_dist": 22.0, "veg": 0.8, "msaa": false, "glow": true, "scale_3d": 1.0, "lod": 2.5, "shadow_size": 2048, "view_dist": 55.0, "outer_trees": 60},
	"high": {"shadows": true, "tree_shadows": true, "shadow_dist": 38.0, "veg": 1.0, "msaa": true, "glow": true, "scale_3d": 1.0, "lod": 1.0, "shadow_size": 4096, "view_dist": 85.0, "outer_trees": 120},
}
const QUALITY_NAMES := {"low": "Низкое (для слабых ноутбуков)", "medium": "Среднее", "high": "Высокое (для дискретной видеокарты)"}


static func quality() -> Dictionary:
	var key: String = Settings.get_value("graphics")
	if key == "auto":
		key = auto_quality()
	return QUALITY.get(key, QUALITY.medium)


## «Авто»: встроенная графика (Intel, AMD Radeon Graphics/Vega в процессоре) — низкое, иначе среднее.
static func auto_quality() -> String:
	var gpu := RenderingServer.get_video_adapter_name().to_lower()
	if gpu == "" or "intel" in gpu or "radeon(tm) graphics" in gpu or "vega" in gpu or "llvmpipe" in gpu:
		return "low"
	return "medium"


## Круглая полупрозрачная тень-пятно под персонажем — когда настоящие тени выключены.
static func blob_shadow(radius: float = 0.45) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var quad := PlaneMesh.new()
	quad.size = Vector2.ONE * radius * 2.0
	mi.mesh = quad
	mi.position.y = 0.06
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _blob_material()
	return mi


static var _blob_mat: StandardMaterial3D


static func _blob_material() -> StandardMaterial3D:
	if _blob_mat:
		return _blob_mat
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.45, 1.0])
	g.colors = PackedColorArray([Color(0, 0, 0, 0.55), Color(0, 0, 0, 0.45), Color(0, 0, 0, 0)])
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(0.5, 0.0)
	tex.width = 64
	tex.height = 64
	_blob_mat = StandardMaterial3D.new()
	_blob_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_blob_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_blob_mat.albedo_texture = tex
	_blob_mat.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_DISABLED
	_blob_mat.render_priority = 1
	return _blob_mat


## Палитры земли по биому: [a, b, c, тропа].
const GROUND_PALETTES := {
	"forest": ["#447A26", "#5C9430", "#36661F", "#7A5A36"],
	"meadow": ["#5E9C32", "#76AE40", "#4F8A2A", "#86684A"],
	"riverside": ["#468A33", "#5F9D40", "#386F28", "#76664A"],
	"ruins": ["#6E7F40", "#83924F", "#5A6A33", "#857A68"],
	"cave": ["#5B5047", "#6D6055", "#4A4039", "#7E705F"],
	"tomb": ["#57524E", "#68625C", "#47423E", "#7A6E62"],
	"dungeon": ["#5E5248", "#6E6156", "#4E443C", "#82705E"],
	"swamp": ["#4B6332", "#5D7A3B", "#3D522A", "#6E6040"],
}

## Освещение и небо по биому.
const SKIES := {
	"day": {"top": "#3E7FD6", "horizon": "#BFE2F2", "ground": "#3B4A2A", "sun": "#FFF1D6", "sun_energy": 1.05,
		"sun_rot": Vector3(-48, 35, 0), "ambient": 0.55, "fog": "#BFD9E6", "fog_density": 0.006},
	"sunset": {"top": "#3F6FB8", "horizon": "#F2B27A", "ground": "#2D3A22", "sun": "#FFD2A0", "sun_energy": 1.15,
		"sun_rot": Vector3(-24, 52, 0), "ambient": 0.6, "fog": "#E9B98A", "fog_density": 0.01},
	"gloom": {"top": "#2B3A5A", "horizon": "#7E8FA8", "ground": "#22281C", "sun": "#C9D6FF", "sun_energy": 0.8,
		"sun_rot": Vector3(-40, -30, 0), "ambient": 0.7, "fog": "#7E8FA8", "fog_density": 0.02},
	"cave": {"bg": "#07060A", "ambient_color": "#6A5A4A", "ambient": 0.75, "fog": "#140F0C", "fog_density": 0.03,
		"sun": "#8FA8D9", "sun_energy": 0.25, "sun_rot": Vector3(-62, 35, 0)},
}


static func ground_material(biome: String = "forest") -> ShaderMaterial:
	var pal: Array = GROUND_PALETTES.get(biome, GROUND_PALETTES.forest)
	var m := ShaderMaterial.new()
	m.shader = GROUND
	m.set_shader_parameter("color_a", Color(pal[0]))
	m.set_shader_parameter("color_b", Color(pal[1]))
	m.set_shader_parameter("color_c", Color(pal[2]))
	m.set_shader_parameter("path_color", Color(pal[3]))
	if biome in ["cave", "tomb", "dungeon"]:
		m.set_shader_parameter("scale", 0.15)
		m.set_shader_parameter("roughness_value", 0.85)
	return m


static func grass_material() -> ShaderMaterial:
	return ground_material("meadow")


static func water_material() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = WATER
	return m


static func environment(preset: String) -> Array:
	var s: Dictionary = SKIES.get(preset, SKIES.day)
	var env := Environment.new()
	if s.has("bg"):
		env.background_mode = Environment.BG_COLOR
		env.background_color = Color(s.bg)
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color(s.ambient_color)
	else:
		var sky_mat := ProceduralSkyMaterial.new()
		sky_mat.sky_top_color = Color(s.top)
		sky_mat.sky_horizon_color = Color(s.horizon)
		sky_mat.ground_bottom_color = Color(s.ground)
		sky_mat.ground_horizon_color = Color(s.horizon).darkened(0.25)
		var sky := Sky.new()
		sky.sky_material = sky_mat
		env.background_mode = Environment.BG_SKY
		env.sky = sky
		env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = s.ambient
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.05
	env.fog_enabled = true
	env.fog_light_color = Color(s.fog)
	env.fog_density = s.fog_density
	env.fog_sky_affect = 0.25
	var q := quality()
	env.glow_enabled = q.glow
	env.glow_intensity = 0.45
	env.glow_bloom = 0.04
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = s.sun_rot
	sun.light_color = Color(s.sun)
	sun.light_energy = s.sun_energy
	sun.shadow_enabled = q.shadows
	sun.shadow_blur = 1.5
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS if q.shadow_dist > 30.0 else DirectionalLight3D.SHADOW_ORTHOGONAL
	sun.directional_shadow_max_distance = maxf(q.shadow_dist, 10.0)
	return [env, sun]


## Костёр: кольцо камней, поленья, частицы огня и искр.
static func make_campfire(parent: Node3D, pos: Vector3) -> Node3D:
	var root := Node3D.new()
	root.position = pos
	parent.add_child(root)
	var stone_mat := StandardMaterial3D.new()
	stone_mat.albedo_color = Color("#7D7A73")
	stone_mat.roughness = 0.9
	for i in 9:
		var a := TAU * i / 9.0
		var st := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.13
		sm.height = 0.18
		sm.radial_segments = 7
		sm.rings = 4
		st.mesh = sm
		st.material_override = stone_mat
		st.position = Vector3(cos(a) * 0.48, 0.05, sin(a) * 0.48)
		st.rotation.y = a
		root.add_child(st)
	var log_mat := StandardMaterial3D.new()
	log_mat.albedo_color = Color("#5A3A22")
	for i in 4:
		var lg := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.06
		cm.bottom_radius = 0.07
		cm.height = 0.7
		cm.radial_segments = 7
		lg.mesh = cm
		lg.material_override = log_mat
		lg.rotation = Vector3(deg_to_rad(70), TAU * i / 4.0, 0)
		lg.position = Vector3(0, 0.15, 0)
		root.add_child(lg)
	fire_particles(root, Vector3(0, 0.15, 0), 1.0)
	return root


static func fire_particles(parent: Node3D, pos: Vector3, size: float) -> CPUParticles3D:
	var fire := CPUParticles3D.new()
	fire.position = pos
	fire.amount = 28
	fire.lifetime = 0.8
	fire.direction = Vector3.UP
	fire.spread = 12
	fire.initial_velocity_min = 0.6 * size
	fire.initial_velocity_max = 1.3 * size
	fire.gravity = Vector3(0, 0.6, 0)
	fire.emission_shape = CPUParticles3D.EMISSION_SHAPE_SPHERE
	fire.emission_sphere_radius = 0.18 * size
	fire.scale_amount_min = 0.5 * size
	fire.scale_amount_max = 1.0 * size
	var curve := Curve.new()
	curve.add_point(Vector2(0, 0.6))
	curve.add_point(Vector2(0.3, 1.0))
	curve.add_point(Vector2(1, 0.0))
	fire.scale_amount_curve = curve
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1.0, 0.85, 0.35, 1))
	ramp.set_color(1, Color(0.9, 0.2, 0.05, 0))
	fire.color_ramp = ramp
	var quad := QuadMesh.new()
	quad.size = Vector2(0.35, 0.35)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = _soft_dot()
	quad.material = mat
	fire.mesh = quad
	parent.add_child(fire)
	return fire


static var _dot_tex: Texture2D

## Мягкая круглая текстура для частиц.
static func _soft_dot() -> Texture2D:
	if _dot_tex == null:
		var g := Gradient.new()
		g.set_color(0, Color(1, 1, 1, 1))
		g.set_color(1, Color(1, 1, 1, 0))
		var gt := GradientTexture2D.new()
		gt.gradient = g
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 64
		gt.height = 64
		_dot_tex = gt
	return _dot_tex
