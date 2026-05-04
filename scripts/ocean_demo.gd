@tool
extends Node3D

const OCEAN_SHADER_PATH := "res://shaders/realistic_ocean.gdshader"

const BOAT_ACCELERATION := 18.0
const BOAT_REVERSE_ACCELERATION := 8.0
const BOAT_DRAG := 1.15
const BOAT_TURN_RATE := 1.65
const BOAT_FLOAT_OFFSET := 0.10
const BOAT_BUOYANCY := 18.0
const BOAT_HEAVE_DAMPING := 5.2
const BOAT_SIDE_DRAG := 5.8
const WAVE_HEIGHT := 0.98
const WAVE_TIME_SCALE := 0.72
const IRREGULARITY := 0.70
const MOUSE_RIPPLE_COUNT := 8
const MOUSE_RIPPLE_MIN_DISTANCE := 1.15
const MOUSE_RIPPLE_FORCE := 1.0
const MOUSE_RIPPLE_LIFETIME := 2.2

var camera: Camera3D
var boat: Node3D
var ocean_material: ShaderMaterial
var dof_material: ShaderMaterial
var boat_velocity := Vector3.ZERO
var boat_vertical_velocity: float = 0.0
var boat_heading: float = 0.0
var boat_pitch: float = 0.0
var boat_roll: float = 0.0
var wake_power: float = 0.0
var impact_foam: float = 0.0
var mouse_ripples: Array[Vector4] = []
var mouse_ripple_slot: int = 0
var is_dragging_water := false
var last_mouse_water_position := Vector2.ZERO
var has_mouse_water_position := false


func _ready() -> void:
	_rebuild_scene()
	set_process(true)


func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		_float_boat_on_waves(delta)
		_update_ocean_wake()
		return

	_update_boat_controls(delta)
	_update_mouse_ripple_input()
	_float_boat_on_waves(delta)
	_update_ocean_wake()
	_update_camera(delta)


func _input(event: InputEvent) -> void:
	if Engine.is_editor_hint():
		return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		is_dragging_water = event.pressed
		has_mouse_water_position = false
		if is_dragging_water:
			_update_mouse_ripple_input(true)

	if event is InputEventMouseMotion and is_dragging_water:
		_update_mouse_ripple_input()


func _rebuild_scene() -> void:
	_clear_generated()
	_reset_mouse_ripples()
	_register_input()
	_add_environment()
	_add_lighting()
	_add_ocean()
	_add_boat()
	_add_camera()
	_add_ui()
	_float_boat_on_waves()
	_update_ocean_wake()


func _clear_generated() -> void:
	for child in get_children():
		if child.has_meta("generated_ocean"):
			child.free()


func _register_input() -> void:
	if Engine.is_editor_hint():
		return

	_add_key_action("boat_throttle", [KEY_W, KEY_UP])
	_add_key_action("boat_brake", [KEY_S, KEY_DOWN])
	_add_key_action("boat_left", [KEY_A, KEY_LEFT])
	_add_key_action("boat_right", [KEY_D, KEY_RIGHT])
	_add_key_action("boat_reset", [KEY_R])


func _add_key_action(action: StringName, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)

	for key in keys:
		var exists := false
		for event in InputMap.action_get_events(action):
			if event is InputEventKey and event.physical_keycode == key:
				exists = true
				break

		if not exists:
			var input := InputEventKey.new()
			input.physical_keycode = key
			InputMap.action_add_event(action, input)


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
	if get_node_or_null("Sun") == null:
		push_warning("OceanDemo expects a scene-owned Sun DirectionalLight3D.")
	if get_node_or_null("Cool Fill") == null:
		push_warning("OceanDemo expects a scene-owned Cool Fill DirectionalLight3D.")


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

	ocean_material = ShaderMaterial.new()
	var shader: Resource = load(OCEAN_SHADER_PATH)
	if shader is Shader:
		ocean_material.shader = shader
	ocean_material.set_shader_parameter("wave_noise", noise_texture)
	ocean_material.set_shader_parameter("wave_height", WAVE_HEIGHT)
	ocean_material.set_shader_parameter("choppiness", 0.08)
	ocean_material.set_shader_parameter("foam_amount", 0.50)
	ocean_material.set_shader_parameter("fresnel_power", 4.2)
	ocean_material.set_shader_parameter("irregularity", IRREGULARITY)
	ocean_material.set_shader_parameter("geometry_fade_start", 58.0)
	ocean_material.set_shader_parameter("geometry_fade_end", 150.0)
	ocean_material.set_shader_parameter("water_alpha", 0.74)
	ocean_material.set_shader_parameter("impact_foam", 0.0)
	_push_mouse_ripples_to_shader()
	ocean.material_override = ocean_material


func _add_boat() -> void:
	boat = Node3D.new()
	boat.name = "Controllable Boat"
	_mark_generated(boat)
	boat.position = Vector3(0.0, 1.0, 0.0)
	add_child(boat)

	var hull_material := StandardMaterial3D.new()
	hull_material.albedo_color = Color.html("#9a2f24")
	hull_material.roughness = 0.48

	var deck_material := StandardMaterial3D.new()
	deck_material.albedo_color = Color.html("#e8d4ad")
	deck_material.roughness = 0.62

	var cabin_material := StandardMaterial3D.new()
	cabin_material.albedo_color = Color.html("#f2f4ec")
	cabin_material.roughness = 0.35

	var hull := MeshInstance3D.new()
	hull.name = "Hull"
	hull.mesh = _create_v_hull_mesh()
	hull.position = Vector3(0.0, 0.0, 0.0)
	hull.material_override = hull_material
	boat.add_child(hull)

	var bow := MeshInstance3D.new()
	bow.name = "Bow"
	var bow_mesh := BoxMesh.new()
	bow_mesh.size = Vector3(1.55, 0.5, 1.05)
	bow.mesh = bow_mesh
	bow.rotation_degrees = Vector3(0.0, 45.0, 0.0)
	bow.position = Vector3(0.0, -0.07, -2.88)
	bow.material_override = hull_material
	boat.add_child(bow)

	var keel := MeshInstance3D.new()
	keel.name = "V Keel"
	var keel_mesh := BoxMesh.new()
	keel_mesh.size = Vector3(0.18, 0.24, 4.15)
	keel.mesh = keel_mesh
	keel.position = Vector3(0.0, -0.63, -0.2)
	keel.material_override = hull_material
	boat.add_child(keel)

	var deck := MeshInstance3D.new()
	deck.name = "Deck"
	var deck_mesh := BoxMesh.new()
	deck_mesh.size = Vector3(2.15, 0.18, 3.35)
	deck.mesh = deck_mesh
	deck.position = Vector3(0.0, 0.47, -0.35)
	deck.material_override = deck_material
	boat.add_child(deck)

	var cabin := MeshInstance3D.new()
	cabin.name = "Cabin"
	var cabin_mesh := BoxMesh.new()
	cabin_mesh.size = Vector3(1.35, 0.92, 1.28)
	cabin.mesh = cabin_mesh
	cabin.position = Vector3(0.0, 1.03, 0.95)
	cabin.material_override = cabin_material
	boat.add_child(cabin)

	var mast := MeshInstance3D.new()
	mast.name = "Antenna"
	var mast_mesh := CylinderMesh.new()
	mast_mesh.top_radius = 0.025
	mast_mesh.bottom_radius = 0.035
	mast_mesh.height = 1.35
	mast.mesh = mast_mesh
	mast.position = Vector3(0.0, 1.98, 1.0)
	mast.material_override = cabin_material
	boat.add_child(mast)


func _add_camera() -> void:
	camera = get_node_or_null("Follow Camera") as Camera3D
	if camera == null:
		push_warning("OceanDemo expects a scene-owned Follow Camera Camera3D.")
		return

	camera.current = true
	if camera.attributes != null:
		camera.attributes.set("dof_blur_far_enabled", false)
		camera.attributes.set("dof_blur_near_enabled", false)

	var dof_quad := camera.get_node_or_null("Cinematic DOF") as MeshInstance3D
	if dof_quad != null:
		dof_material = dof_quad.material_override as ShaderMaterial
	else:
		push_warning("Follow Camera expects a Cinematic DOF MeshInstance3D child.")

	_update_camera(1.0)


func _create_v_hull_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	var top_left_front := Vector3(-1.35, 0.30, -2.55)
	var top_right_front := Vector3(1.35, 0.30, -2.55)
	var top_left_back := Vector3(-1.35, 0.30, 2.55)
	var top_right_back := Vector3(1.35, 0.30, 2.55)
	var chine_left_front := Vector3(-0.95, -0.28, -2.55)
	var chine_right_front := Vector3(0.95, -0.28, -2.55)
	var chine_left_back := Vector3(-1.05, -0.28, 2.55)
	var chine_right_back := Vector3(1.05, -0.28, 2.55)
	var keel_front := Vector3(0.0, -0.82, -2.28)
	var keel_back := Vector3(0.0, -0.82, 2.35)

	_add_quad(st, top_left_front, top_left_back, chine_left_back, chine_left_front)
	_add_quad(st, chine_left_front, chine_left_back, keel_back, keel_front)
	_add_quad(st, chine_right_front, keel_front, keel_back, chine_right_back)
	_add_quad(st, top_right_front, chine_right_front, chine_right_back, top_right_back)
	_add_quad(st, top_left_back, top_right_back, chine_right_back, chine_left_back)
	_add_triangle(st, top_left_front, chine_left_front, keel_front)
	_add_triangle(st, top_left_front, keel_front, top_right_front)
	_add_triangle(st, top_right_front, keel_front, chine_right_front)
	_add_quad(st, top_left_front, top_right_front, top_right_back, top_left_back)

	st.generate_normals()
	return st.commit()


func _add_quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_add_triangle(st, a, b, c)
	_add_triangle(st, a, c, d)


func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


func _add_ui() -> void:
	if Engine.is_editor_hint():
		return

	var canvas := CanvasLayer.new()
	canvas.name = "UI"
	_mark_generated(canvas)
	add_child(canvas)

	var label := Label.new()
	label.text = "W/S throttle  |  A/D steer  |  R reset  |  Left-drag water for ripples"
	label.position = Vector2(24, 22)
	label.add_theme_font_size_override("font_size", 20)
	canvas.add_child(label)


func _update_boat_controls(delta: float) -> void:
	if boat == null:
		return

	if Input.is_action_just_pressed("boat_reset"):
		boat.position = Vector3.ZERO
		boat_velocity = Vector3.ZERO
		boat_vertical_velocity = 0.0
		boat_heading = 0.0

	var throttle: float = Input.get_action_strength("boat_throttle") - Input.get_action_strength("boat_brake")
	var steer: float = Input.get_action_strength("boat_left") - Input.get_action_strength("boat_right")
	var forward: Vector3 = _boat_forward()
	var right: Vector3 = Vector3(forward.z, 0.0, -forward.x)
	var speed: float = boat_velocity.length()
	var steer_power: float = clampf(speed / 8.0, 0.25, 1.0)

	boat_heading += steer * BOAT_TURN_RATE * steer_power * delta
	var acceleration: float = BOAT_ACCELERATION
	if throttle < 0.0:
		acceleration = BOAT_REVERSE_ACCELERATION
	boat_velocity += forward * throttle * acceleration * delta

	var forward_speed: float = boat_velocity.dot(forward)
	var side_speed: float = boat_velocity.dot(right)
	var water_drag: float = BOAT_DRAG + abs(forward_speed) * 0.035
	forward_speed = move_toward(forward_speed, 0.0, water_drag * delta)
	side_speed = move_toward(side_speed, 0.0, BOAT_SIDE_DRAG * delta)
	boat_velocity = forward * forward_speed + right * side_speed

	var wave_push: Vector3 = _sample_wave_push(Vector2(boat.position.x, boat.position.z), Time.get_ticks_msec() / 1000.0)
	boat_velocity += wave_push * delta * 1.35
	boat_velocity = boat_velocity.limit_length(24.0)
	boat.position += boat_velocity * delta

	var distance_from_center: float = Vector2(boat.position.x, boat.position.z).length()
	if distance_from_center > 230.0:
		var pull: Vector3 = Vector3(-boat.position.x, 0.0, -boat.position.z).normalized()
		boat_velocity += pull * delta * 7.0

	var wake_blend: float = 1.0 - pow(0.04, delta)
	wake_power = lerpf(wake_power, clampf(boat_velocity.length() / 14.0, 0.0, 1.0), wake_blend)


func _float_boat_on_waves(delta: float = 0.016) -> void:
	if boat == null:
		return

	var forward: Vector3 = _boat_forward()
	var right: Vector3 = Vector3(forward.z, 0.0, -forward.x)
	var center: Vector2 = Vector2(boat.position.x, boat.position.z)
	var time: float = Time.get_ticks_msec() / 1000.0

	var center_height: float = _sample_ocean_height(center, time)
	var bow_height: float = _sample_ocean_height(center + Vector2(forward.x, forward.z) * 2.6, time)
	var stern_height: float = _sample_ocean_height(center - Vector2(forward.x, forward.z) * 2.3, time)
	var port_height: float = _sample_ocean_height(center - Vector2(right.x, right.z) * 1.25, time)
	var starboard_height: float = _sample_ocean_height(center + Vector2(right.x, right.z) * 1.25, time)
	var forward_speed: float = maxf(0.0, boat_velocity.dot(forward))
	var bow_slope_hit: float = maxf(0.0, bow_height - center_height)
	var bow_slap: float = maxf(0.0, -boat_vertical_velocity) * 0.35
	var impact_target: float = clampf((bow_slope_hit * 2.2 + bow_slap) * forward_speed / 8.0, 0.0, 1.0)
	impact_foam = lerpf(impact_foam, impact_target, 1.0 - pow(0.018, delta))

	var target_height: float = center_height + BOAT_FLOAT_OFFSET
	var displacement: float = target_height - boat.position.y
	boat_vertical_velocity += displacement * BOAT_BUOYANCY * delta
	boat_vertical_velocity = move_toward(boat_vertical_velocity, 0.0, BOAT_HEAVE_DAMPING * delta)
	boat.position.y += boat_vertical_velocity * delta

	var pitch: float = clampf((stern_height - bow_height) * 0.22, -0.26, 0.26)
	var roll: float = clampf((port_height - starboard_height) * 0.32, -0.32, 0.32)
	var turn_lean: float = clampf(boat_velocity.length() / 24.0, 0.0, 1.0) * 0.12
	var local_turn: float = 0.0
	if boat_velocity.length() > 0.2:
		local_turn = boat_velocity.normalized().cross(forward).y

	var pose_blend: float = 1.0 - pow(0.02, delta)
	boat_pitch = lerpf(boat_pitch, pitch, pose_blend)
	boat_roll = lerpf(boat_roll, roll + local_turn * turn_lean, pose_blend)
	boat.rotation = Vector3(boat_pitch, boat_heading, boat_roll)


func _update_ocean_wake() -> void:
	if ocean_material == null or boat == null:
		return

	var forward: Vector3 = _boat_forward()
	ocean_material.set_shader_parameter("boat_position", Vector2(boat.position.x, boat.position.z))
	ocean_material.set_shader_parameter("boat_forward", Vector2(forward.x, forward.z).normalized())
	ocean_material.set_shader_parameter("boat_speed", boat_velocity.length())
	ocean_material.set_shader_parameter("wake_strength", wake_power)
	ocean_material.set_shader_parameter("impact_foam", impact_foam)
	ocean_material.set_shader_parameter("interaction_time", Time.get_ticks_msec() / 1000.0)
	_push_mouse_ripples_to_shader()


func _update_camera(delta: float) -> void:
	if camera == null or boat == null:
		return

	var forward: Vector3 = _boat_forward()
	var target_position: Vector3 = boat.position - forward * 13.0 + Vector3.UP * 7.0
	var camera_blend: float = 1.0 - pow(0.025, delta)
	camera.global_position = camera.global_position.lerp(target_position, camera_blend)
	camera.look_at(boat.position + forward * 5.0 + Vector3.UP * 1.1, Vector3.UP)
	_update_camera_depth_of_field(camera.global_position.distance_to(boat.position))


func _update_camera_depth_of_field(focus_distance: float) -> void:
	if dof_material == null:
		return

	dof_material.set_shader_parameter("focus_distance", focus_distance)
	dof_material.set_shader_parameter("focus_range", 3.6)
	dof_material.set_shader_parameter("max_radius_px", 7.5)
	dof_material.set_shader_parameter("viewport_size", get_viewport().get_visible_rect().size)


func _boat_forward() -> Vector3:
	return Vector3(-sin(boat_heading), 0.0, -cos(boat_heading)).normalized()


func _sample_ocean_height(p: Vector2, time: float) -> float:
	var h: float = 0.0
	h += _wave_layer(p, Vector2(1.0, 0.18), 16.0, 1.18, 0.72, 0.0, time)
	h += _wave_layer(p, Vector2(0.28, 1.0), 9.5, 1.72, 0.34, 1.7, time)
	h += _wave_layer(p, Vector2(-0.78, 0.62), 6.0, 2.25, 0.22, 3.1, time)
	h += _wave_layer(p, Vector2(0.86, -0.5), 3.1, 3.8, 0.08, 0.4, time)
	h += (sin(p.x * 0.31 + time * 0.9) + cos(p.y * 0.27 - time * 0.6)) * 0.035 * IRREGULARITY
	return (h + _sample_mouse_displacement_height(p, time)) * WAVE_HEIGHT


func _reset_mouse_ripples() -> void:
	mouse_ripples.clear()
	for i in range(MOUSE_RIPPLE_COUNT):
		mouse_ripples.append(Vector4(9999.0, 9999.0, -1000.0, 0.0))
	mouse_ripple_slot = 0
	has_mouse_water_position = false


func _update_mouse_ripple_input(force_ripple: bool = false) -> void:
	if camera == null or not is_dragging_water:
		return

	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	if absf(direction.y) < 0.001:
		return

	var ray_distance := -origin.y / direction.y
	if ray_distance < 0.0:
		return

	var hit := origin + direction * ray_distance
	var water_position := Vector2(hit.x, hit.z)
	if water_position.length() > 245.0:
		return

	var should_spawn := force_ripple or not has_mouse_water_position
	if has_mouse_water_position:
		should_spawn = should_spawn or water_position.distance_to(last_mouse_water_position) >= MOUSE_RIPPLE_MIN_DISTANCE

	if should_spawn:
		var strength := MOUSE_RIPPLE_FORCE
		if has_mouse_water_position:
			strength += clampf(water_position.distance_to(last_mouse_water_position) * 0.18, 0.0, 0.9)
		_add_mouse_ripple(water_position, strength)
		last_mouse_water_position = water_position
		has_mouse_water_position = true


func _add_mouse_ripple(position: Vector2, strength: float) -> void:
	if mouse_ripples.size() != MOUSE_RIPPLE_COUNT:
		_reset_mouse_ripples()

	mouse_ripples[mouse_ripple_slot] = Vector4(position.x, position.y, Time.get_ticks_msec() / 1000.0, strength)
	mouse_ripple_slot = (mouse_ripple_slot + 1) % MOUSE_RIPPLE_COUNT


func _push_mouse_ripples_to_shader() -> void:
	if ocean_material == null:
		return

	if mouse_ripples.size() != MOUSE_RIPPLE_COUNT:
		_reset_mouse_ripples()

	for i in range(MOUSE_RIPPLE_COUNT):
		ocean_material.set_shader_parameter("mouse_ripple_%d" % i, mouse_ripples[i])


func _sample_mouse_displacement_height(p: Vector2, time: float) -> float:
	var total := 0.0
	for ripple in mouse_ripples:
		var age := time - ripple.z
		if age < 0.0 or age > MOUSE_RIPPLE_LIFETIME:
			continue

		var distance := p.distance_to(Vector2(ripple.x, ripple.y))
		var progress := clampf(age / MOUSE_RIPPLE_LIFETIME, 0.0, 1.0)
		var fade := pow(1.0 - progress, 1.35)
		var spread := lerpf(0.35, 2.6, progress)
		var rim_width := lerpf(0.28, 0.85, progress)
		var center_width := spread * 0.42
		var center_dip := -exp(-pow(distance / maxf(center_width, 0.08), 2.0)) * 0.12 * fade
		var raised_rim := exp(-pow((distance - spread) / rim_width, 2.0)) * 0.58 * fade
		var outer_shoulder := exp(-pow((distance - spread * 1.55) / (rim_width * 1.8), 2.0)) * 0.10 * fade
		total += (center_dip + raised_rim + outer_shoulder) * ripple.w

	return total


func _sample_wave_push(p: Vector2, time: float) -> Vector3:
	var eps: float = 0.75
	var hx: float = _sample_ocean_height(p + Vector2(eps, 0.0), time) - _sample_ocean_height(p - Vector2(eps, 0.0), time)
	var hz: float = _sample_ocean_height(p + Vector2(0.0, eps), time) - _sample_ocean_height(p - Vector2(0.0, eps), time)
	return Vector3(-hx, 0.0, -hz)


func _wave_layer(p: Vector2, direction: Vector2, wavelength: float, speed: float, amplitude: float, phase_offset: float, time: float) -> float:
	var normalized_direction: Vector2 = direction.normalized()
	var local_wavelength: float = wavelength * (0.96 + 0.12 * sin(p.x * 0.043 + p.y * 0.031 + phase_offset))
	var local_amp: float = amplitude * (0.92 + 0.12 * cos(p.x * 0.037 - p.y * 0.029 + phase_offset * 2.1))
	var k: float = TAU / local_wavelength
	var phase: float = p.dot(normalized_direction) * k + time * speed * WAVE_TIME_SCALE + phase_offset
	var base_wave: float = sin(phase)
	var secondary_motion: float = sin(phase * 1.73 + phase_offset) * 0.16 + sin(phase * 2.37) * 0.07
	return lerpf(base_wave, base_wave * 0.88 + secondary_motion, IRREGULARITY) * local_amp


func _mark_generated(node: Node) -> void:
	node.set_meta("generated_ocean", true)
