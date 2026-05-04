shader_type spatial;
render_mode unshaded, depth_draw_never, depth_test_disabled, cull_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear_mipmap;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float focus_distance = 15.0;
uniform float focus_range = 4.0;
uniform float max_radius_px = 7.0;
uniform float near_blur_strength = 0.58;
uniform float far_blur_strength = 0.92;
uniform float bokeh_bias = 0.16;
uniform vec2 viewport_size = vec2(1280.0, 720.0);

const int SAMPLE_COUNT = 24;
const vec2 SAMPLE_OFFSETS[SAMPLE_COUNT] = vec2[](
	vec2(0.000, 0.000),
	vec2(0.408, 0.000), vec2(0.204, 0.353), vec2(-0.204, 0.353), vec2(-0.408, 0.000), vec2(-0.204, -0.353), vec2(0.204, -0.353),
	vec2(0.816, 0.000), vec2(0.577, 0.577), vec2(0.000, 0.816), vec2(-0.577, 0.577), vec2(-0.816, 0.000), vec2(-0.577, -0.577), vec2(0.000, -0.816), vec2(0.577, -0.577),
	vec2(1.000, 0.000), vec2(0.707, 0.707), vec2(0.000, 1.000), vec2(-0.707, 0.707), vec2(-1.000, 0.000), vec2(-0.707, -0.707), vec2(0.000, -1.000), vec2(0.707, -0.707),
	vec2(0.383, 0.924)
);

float linear_depth(vec2 uv) {
	float depth = texture(depth_texture, uv).x;
	vec3 ndc = vec3(uv * 2.0 - 1.0, depth);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return -view.z;
}

float circle_of_confusion(float depth) {
	float far_coc = smoothstep(focus_distance, focus_distance + focus_range * 7.0, depth) * far_blur_strength;
	float near_limit = max(focus_distance - focus_range * 5.0, 0.1);
	float near_coc = (1.0 - smoothstep(near_limit, focus_distance, depth)) * near_blur_strength;
	return clamp(max(far_coc, near_coc), 0.0, 1.0);
}

void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float depth = linear_depth(uv);
	float coc = circle_of_confusion(depth);
	vec3 sharp = texture(screen_texture, uv).rgb;

	if (coc < 0.01 || depth > 890.0) {
		ALBEDO = sharp;
		ALPHA = 1.0;
		return;
	}

	vec2 texel = 1.0 / viewport_size;
	vec2 radius = texel * max_radius_px * coc;
	vec3 color_sum = vec3(0.0);
	float weight_sum = 0.0;

	for (int i = 0; i < SAMPLE_COUNT; i++) {
		vec2 offset_uv = uv + SAMPLE_OFFSETS[i] * radius;
		vec3 sample_color = textureLod(screen_texture, offset_uv, coc * 1.4).rgb;
		float sample_depth = linear_depth(offset_uv);
		float sample_coc = circle_of_confusion(sample_depth);
		float edge_guard = step(depth - focus_range * 0.7, sample_depth);
		float luma = dot(sample_color, vec3(0.2126, 0.7152, 0.0722));
		float bokeh_weight = 1.0 + max(luma - 0.62, 0.0) * bokeh_bias * 4.0;
		float weight = mix(0.55, 1.0, sample_coc) * bokeh_weight * edge_guard;
		color_sum += sample_color * weight;
		weight_sum += weight;
	}

	vec3 blurred = color_sum / max(weight_sum, 0.001);
	ALBEDO = mix(sharp, blurred, coc);
	ALPHA = 1.0;
}
