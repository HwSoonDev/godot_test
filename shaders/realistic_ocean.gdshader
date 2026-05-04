shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 shallow_color : source_color = vec4(0.03, 0.42, 0.54, 1.0);
uniform vec4 deep_color : source_color = vec4(0.005, 0.045, 0.11, 1.0);
uniform vec4 underside_color : source_color = vec4(0.0, 0.018, 0.035, 1.0);
uniform vec4 foam_color : source_color = vec4(0.92, 0.98, 1.0, 1.0);
uniform sampler2D wave_noise : repeat_enable;
uniform float wave_height = 0.1;
uniform float choppiness = 0.38;
uniform float foam_amount = 0.55;
uniform float fresnel_power = 4.5;
uniform float time_scale = 0.72;
uniform float irregularity = 0.72;
uniform float geometry_fade_start = 70.0;
uniform float geometry_fade_end = 190.0;
uniform vec2 boat_position = vec2(0.0, 0.0);
uniform vec2 boat_forward = vec2(0.0, -1.0);
uniform float boat_speed = 0.0;
uniform float wake_strength = 0.0;
uniform float impact_foam = 0.0;
uniform float water_alpha = 0.74;
uniform float interaction_time = 0.0;
uniform vec4 mouse_ripple_0 = vec4(9999.0, 9999.0, -1000.0, 0.0);
uniform vec4 mouse_ripple_1 = vec4(9999.0, 9999.0, -1000.0, 0.0);
uniform vec4 mouse_ripple_2 = vec4(9999.0, 9999.0, -1000.0, 0.0);
uniform vec4 mouse_ripple_3 = vec4(9999.0, 9999.0, -1000.0, 0.0);
uniform vec4 mouse_ripple_4 = vec4(9999.0, 9999.0, -1000.0, 0.0);
uniform vec4 mouse_ripple_5 = vec4(9999.0, 9999.0, -1000.0, 0.0);
uniform vec4 mouse_ripple_6 = vec4(9999.0, 9999.0, -1000.0, 0.0);
uniform vec4 mouse_ripple_7 = vec4(9999.0, 9999.0, -1000.0, 0.0);

varying vec3 world_position;
varying float crest_value;
varying float slope_value;
varying float geometry_fade;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float value = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		value += value_noise(p) * amp;
		p = p * 2.03 + vec2(17.2, 9.4);
		amp *= 0.52;
	}
	return value;
}

vec2 rotate2(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

float wave_layer(vec2 p, vec2 dir, float wavelength, float speed, float amplitude, float phase_offset) {
	float k = 6.28318530718 / wavelength;
	float wind_noise = fbm(p * 0.018 + normalize(dir) * TIME * 0.018);
	float direction_warp = (wind_noise - 0.5) * irregularity * 0.9;
	vec2 warped_dir = normalize(rotate2(normalize(dir), direction_warp));
	vec2 warped_p = p;
	warped_p += vec2(
		fbm(p * 0.045 + vec2(2.1, 8.7)) - 0.5,
		fbm(p * 0.041 + vec2(11.5, 3.2)) - 0.5
	) * wavelength * 0.22 * irregularity;

	float local_wavelength = wavelength * mix(0.72, 1.35, fbm(p * 0.026 + phase_offset));
	float local_k = 6.28318530718 / local_wavelength;
	float local_amp = amplitude * mix(0.70, 1.18, fbm(p * 0.032 + phase_offset * 2.1));
	float phase = dot(warped_p, warped_dir) * local_k + TIME * speed * time_scale + phase_offset;
	float base_wave = sin(phase);
	float secondary_motion = sin(phase * 1.73 + phase_offset) * 0.16 + sin(phase * 2.37) * 0.07;
	float natural_wave = mix(base_wave, base_wave * 0.88 + secondary_motion, irregularity);
	return natural_wave * local_amp;
}

float mouse_ripple_event(vec2 p, vec4 ripple) {
	float age = interaction_time - ripple.z;
	if (age < 0.0 || age > 2.2 || ripple.w <= 0.0) {
		return 0.0;
	}

	float distance_to_touch = distance(p, ripple.xy);
	float progress = clamp(age / 2.2, 0.0, 1.0);
	float fade = pow(1.0 - progress, 1.35);
	float spread = mix(0.35, 2.6, progress);
	float rim_width = mix(0.28, 0.85, progress);
	float center_width = max(spread * 0.42, 0.08);
	float center_dip = -exp(-pow(distance_to_touch / center_width, 2.0)) * 0.12 * fade;
	float raised_rim = exp(-pow((distance_to_touch - spread) / rim_width, 2.0)) * 0.58 * fade;
	float outer_shoulder = exp(-pow((distance_to_touch - spread * 1.55) / (rim_width * 1.8), 2.0)) * 0.10 * fade;
	return (center_dip + raised_rim + outer_shoulder) * ripple.w;
}

float mouse_ripple_height(vec2 p) {
	float h = 0.0;
	h += mouse_ripple_event(p, mouse_ripple_0);
	h += mouse_ripple_event(p, mouse_ripple_1);
	h += mouse_ripple_event(p, mouse_ripple_2);
	h += mouse_ripple_event(p, mouse_ripple_3);
	h += mouse_ripple_event(p, mouse_ripple_4);
	h += mouse_ripple_event(p, mouse_ripple_5);
	h += mouse_ripple_event(p, mouse_ripple_6);
	h += mouse_ripple_event(p, mouse_ripple_7);
	return h;
}

float mouse_ripple_foam_event(vec2 p, vec4 ripple) {
	float age = interaction_time - ripple.z;
	if (age < 0.0 || age > 2.2 || ripple.w <= 0.0) {
		return 0.0;
	}

	float distance_to_touch = distance(p, ripple.xy);
	float progress = clamp(age / 2.2, 0.0, 1.0);
	float spread = mix(0.35, 2.6, progress);
	float rim_width = mix(0.28, 0.85, progress);
	float fade = pow(1.0 - progress, 1.6);
	float pushed_water = exp(-pow((distance_to_touch - spread) / rim_width, 2.0));
	return pushed_water * fade * ripple.w;
}

float mouse_ripple_foam(vec2 p) {
	float foam = 0.0;
	foam += mouse_ripple_foam_event(p, mouse_ripple_0);
	foam += mouse_ripple_foam_event(p, mouse_ripple_1);
	foam += mouse_ripple_foam_event(p, mouse_ripple_2);
	foam += mouse_ripple_foam_event(p, mouse_ripple_3);
	foam += mouse_ripple_foam_event(p, mouse_ripple_4);
	foam += mouse_ripple_foam_event(p, mouse_ripple_5);
	foam += mouse_ripple_foam_event(p, mouse_ripple_6);
	foam += mouse_ripple_foam_event(p, mouse_ripple_7);
	return clamp(foam, 0.0, 1.0);
}

float ocean_height(vec2 p) {
	float h = 0.0;
	h += wave_layer(p, vec2(1.0, 0.18), 16.0, 1.18, 0.72, 0.0);
	h += wave_layer(p, vec2(0.28, 1.0), 9.5, 1.72, 0.34, 1.7);
	h += wave_layer(p, vec2(-0.78, 0.62), 6.0, 2.25, 0.22, 3.1);
	h += wave_layer(p, vec2(0.86, -0.5), 3.1, 3.8, 0.08, 0.4);
	h += (fbm(p * 0.065 + vec2(TIME * 0.035, -TIME * 0.02)) - 0.5) * 0.28 * irregularity;
	h += (fbm(p * 0.19 + vec2(-TIME * 0.11, TIME * 0.07)) - 0.5) * 0.06 * irregularity;

	vec2 forward = normalize(boat_forward);
	vec2 right = vec2(forward.y, -forward.x);
	vec2 rel = p - boat_position;
	float behind = dot(rel, -forward);
	float side = dot(rel, right);
	float ahead = dot(rel, forward);
	float speed_factor = clamp(boat_speed / 22.0, 0.0, 1.0) * wake_strength;

	float bow_shape = exp(-abs(side) * 1.15) * exp(-abs(ahead - 3.4) * 0.55);
	float hull_cut = -exp(-abs(side) * 1.35) * exp(-abs(ahead) * 0.42) * 0.32;
	float bow_lift = exp(-abs(side) * 0.78) * exp(-abs(ahead - 4.0) * 0.55) * 0.28;
	float bow_wave = sin(ahead * 4.6 - abs(side) * 2.2 - TIME * 7.8) * 0.24 * bow_shape;
	bow_wave += sin(ahead * 8.0 - abs(side) * 4.7 - TIME * 12.5) * bow_shape * impact_foam * 0.13;

	float wake_back = smoothstep(0.0, 2.0, behind) * exp(-behind * 0.035);
	float wake_angle = abs(abs(side) - behind * 0.32);
	float v_wake = exp(-wake_angle * 2.8) * wake_back;
	float center_turbulence = exp(-abs(side) * 0.42) * exp(-behind * 0.075) * wake_back;
	float side_trough = -exp(-abs(abs(side) - 1.35) * 2.0) * exp(-abs(ahead) * 0.34) * 0.18;
	float wake_wave = sin(behind * 2.35 - abs(side) * 5.4 - TIME * 7.2) * v_wake * 0.42;
	wake_wave += sin(behind * 4.2 - abs(side) * 8.6 - TIME * 10.5) * v_wake * 0.12;
	wake_wave += (fbm(p * 0.7 + vec2(TIME * 0.8, -TIME * 0.35)) - 0.5) * center_turbulence * 0.28;
	h += (hull_cut + bow_lift + bow_wave + side_trough + wake_wave) * speed_factor;
	h += mouse_ripple_height(p);
	return h * wave_height;
}

void vertex() {
	vec2 p = VERTEX.xz;
	float h = ocean_height(p);

	float eps = 0.32;
	float hx = ocean_height(p + vec2(eps, 0.0)) - ocean_height(p - vec2(eps, 0.0));
	float hz = ocean_height(p + vec2(0.0, eps)) - ocean_height(p - vec2(0.0, eps));
	vec3 original_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float camera_distance = distance(original_world_position, CAMERA_POSITION_WORLD);
	geometry_fade = 1.0 - smoothstep(geometry_fade_start, geometry_fade_end, camera_distance);

	h *= geometry_fade;
	hx *= geometry_fade;
	hz *= geometry_fade;

	float side_push_x = clamp(hx * choppiness, -0.16, 0.16);
	float side_push_z = clamp(hz * choppiness, -0.16, 0.16);
	VERTEX.x += side_push_x;
	VERTEX.z += side_push_z;
	VERTEX.y += h;

	NORMAL = normalize(vec3(-hx, eps * 2.0, -hz));
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	crest_value = smoothstep(0.32, 0.92, h) * geometry_fade;
	slope_value = clamp(length(vec2(hx, hz)) * 0.9, 0.0, 1.0) * geometry_fade;
}

void fragment() {
	vec2 p = world_position.xz;
	vec2 ripple_warp = vec2(
		fbm(p * 0.035 + vec2(TIME * 0.018, 2.0)),
		fbm(p * 0.033 + vec2(7.0, -TIME * 0.014))
	) - vec2(0.5);
	ripple_warp *= 4.5 * irregularity;

	float large_ripples = texture(wave_noise, rotate2(p + ripple_warp, 0.25) * 0.025 + vec2(TIME * 0.018, -TIME * 0.014)).r;
	float small_ripples = texture(wave_noise, rotate2(p - ripple_warp * 0.6, -0.72) * 0.12 + vec2(-TIME * 0.045, TIME * 0.038)).r;
	float cross_ripples = texture(wave_noise, rotate2(p + ripple_warp * 0.35, 1.18) * 0.21 + vec2(TIME * 0.061, TIME * 0.024)).r;
	float micro_ripples = texture(wave_noise, rotate2(p, -1.9) * 0.48 + vec2(TIME * 0.12, TIME * 0.08)).r;

	vec3 normal_detail = normalize(vec3(
		(small_ripples - 0.5) * 0.16 + (cross_ripples - 0.5) * 0.09 + (micro_ripples - 0.5) * 0.055,
		1.0,
		(large_ripples - 0.5) * 0.16 + (cross_ripples - 0.5) * 0.08 + (micro_ripples - 0.5) * 0.055
	));
	NORMAL = normalize(mix(NORMAL, normal_detail, mix(0.48, 0.28, geometry_fade)));

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	float depth_mix = clamp((world_position.y + 1.25) * 0.28 + large_ripples * 0.22, 0.0, 1.0);
	vec3 water = mix(deep_color.rgb, shallow_color.rgb, depth_mix);
	water += vec3(0.06, 0.12, 0.14) * fresnel;

	float foam_mask = crest_value * slope_value;
	foam_mask += smoothstep(0.68, 0.94, small_ripples * 0.72 + cross_ripples * 0.28) * crest_value * 0.55;
	foam_mask *= mix(0.65, 1.25, fbm(p * 0.05 + vec2(9.4, TIME * 0.03))) * geometry_fade;

	vec2 forward = normalize(boat_forward);
	vec2 right = vec2(forward.y, -forward.x);
	vec2 rel = p - boat_position;
	float behind = dot(rel, -forward);
	float side = dot(rel, right);
	float ahead = dot(rel, forward);
	float speed_factor = clamp(boat_speed / 20.0, 0.0, 1.0) * wake_strength;
	float bow_foam = exp(-abs(side) * 1.65) * exp(-abs(ahead - 3.2) * 0.72);
	float impact_bow = exp(-abs(side) * 1.05) * exp(-abs(ahead - 2.35) * 0.85);
	float impact_spray = smoothstep(0.35, 0.95, fbm(p * 2.4 + vec2(TIME * 1.7, -TIME * 0.85)));
	float wake_back = smoothstep(0.0, 2.0, behind) * exp(-behind * 0.033);
	float wake_angle = abs(abs(side) - behind * 0.32);
	float v_foam = exp(-wake_angle * 4.2) * wake_back;
	float churn = exp(-abs(side) * 0.55) * exp(-behind * 0.068) * wake_back;
	float broken_water = smoothstep(0.42, 0.92, fbm(p * 1.15 + vec2(-TIME * 0.9, TIME * 0.48)));
	foam_mask += (bow_foam * 0.95 + v_foam * 0.85 + churn * broken_water * 0.7) * speed_factor;
	foam_mask += impact_bow * impact_spray * impact_foam * 1.35;
	foam_mask += exp(-abs(abs(side) - 1.15) * 2.6) * exp(-abs(ahead) * 0.42) * impact_foam * 0.55;
	foam_mask += mouse_ripple_foam(p) * 0.75;
	foam_mask = smoothstep(1.0 - foam_amount, 1.0, foam_mask);

	ALBEDO = mix(water, foam_color.rgb, foam_mask);
	ROUGHNESS = mix(0.015, 0.17, foam_mask);
	METALLIC = 0.0;
	SPECULAR = mix(1.0, 0.35, foam_mask);
	ALPHA = mix(water_alpha, 0.98, foam_mask);
}
