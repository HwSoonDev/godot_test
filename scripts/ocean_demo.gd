@tool
extends Node3D

const OCEAN_SHADER := preload("res://shaders/realistic_ocean.gdshader")

var camera: Camera3D
var camera_angle := 0.0


func _ready() -> void:
	_rebuild_scene()
	set_process(not Engine.is_editor_hint())


func _process(delta: float) -> void:
	if camera == null:
		return

	camera_angle += delta * 0.045
	var radius := 42.0
	camera.global_position = Vector3(cos(camera_angle) * radius, 14.0, sin(camera_angle) * radius)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)


func _rebuild_scene() -> void:
	_clear_generated()
	_add_environment()
	_add_lighting()
	_add_ocean()
	_add_camera()


func _clear_generated() -> void:
	for child in get_children():
		if child.has_meta("generated_ocean"):
			child.free()


func _add_environment() -> void:
	var world := WorldEnvironment.new()
	world.name = "WorldEnvironment"
	_mark_generated(world)
	add_child(world)

	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color.html("#7fb8e8")
	sky_material.sky_horizon_color = Color.html("#c9e8ff")
	sky_material.ground_bottom_color = Color.html("#0d2033")
	sky_material.ground_horizon_color = Color.html("#6fa6bd")
	sky_material.sun_angle_max = 12.0
	sky_material.sun_curve = 0.08

	var sky := Sky.new()
	sky.sky_material = sky_material

	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_color = Color.html("#b8d9ff")
	environment.ambient_light_energy = 0.45
	environment.fog_enabled = true
	environment.fog_light_color = Color.html("#9ac7df")
	environment.fog_density = 0.006
	environment.glow_enabled = true
	environment.glow_intensity = 0.16
	world.environment = environment


func _add_lighting() -> void:
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	_mark_generated(sun)
	sun.rotation_degrees = Vector3(-34.0, -42.0, 0.0)
	sun.light_color = Color.html("#fff3d2")
	sun.light_energy = 3.2
	sun.shadow_enabled = true
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.name = "Cool Fill"
	_mark_generated(fill)
	fill.rotation_degrees = Vector3(-18.0, 130.0, 0.0)
	fill.light_color = Color.html("#8ebeff")
	fill.light_energy = 0.38
	add_child(fill)


func _add_ocean() -> void:
	var ocean := MeshInstance3D.new()
	ocean.name = "Shader Ocean"
	_mark_generated(ocean)
	add_child(ocean)

	var plane := PlaneMesh.new()
	plane.size = Vector2(520.0, 520.0)
	plane.subdivide_width = 420
	plane.subdivide_depth = 420
	ocean.mesh = plane

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.seed = 39142
	noise.frequency = 0.035
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = 5
	noise.fractal_lacunarity = 2.15
	noise.fractal_gain = 0.48

	var noise_texture := NoiseTexture2D.new()
	noise_texture.width = 1024
	noise_texture.height = 1024
	noise_texture.seamless = true
	noise_texture.noise = noise

	var material := ShaderMaterial.new()
	material.shader = OCEAN_SHADER
	material.set_shader_parameter("wave_noise", noise_texture)
	material.set_shader_parameter("wave_height", 0.98)
	material.set_shader_parameter("choppiness", 0.14)
	material.set_shader_parameter("foam_amount", 0.52)
	material.set_shader_parameter("fresnel_power", 4.2)
	material.set_shader_parameter("irregularity", 0.70)
	material.set_shader_parameter("geometry_fade_start", 58.0)
	material.set_shader_parameter("geometry_fade_end", 150.0)
	ocean.material_override = material


func _add_horizon_cards() -> void:
	var far_water := MeshInstance3D.new()
	far_water.name = "Distant Water Haze"
	_mark_generated(far_water)
	add_child(far_water)

	var mesh := PlaneMesh.new()
	mesh.size = Vector2(900.0, 900.0)
	far_water.mesh = mesh
	far_water.position = Vector3(0.0, -0.45, 0.0)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.025, 0.12, 0.18, 0.42)
	mat.roughness = 0.08
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	far_water.material_override = mat


func _add_camera() -> void:
	camera = Camera3D.new()
	camera.name = "Camera3D"
	_mark_generated(camera)
	camera.position = Vector3(34.0, 13.0, 28.0)
	camera.fov = 54.0
	camera.near = 0.05
	camera.far = 900.0
	camera.current = true
	add_child(camera)
	camera.look_at(Vector3(0.0, 0.0, 0.0), Vector3.UP)


func _mark_generated(node: Node) -> void:
	node.set_meta("generated_ocean", true)
