shader_type canvas_item;
render_mode unshaded, blend_add;

instance uniform float phase_offset : hint_range(0.0, 1.0) = 0.0;
uniform vec4 shield_color : source_color = vec4(0.34, 0.86, 0.92, 1.0);
uniform vec4 sheen_color : source_color = vec4(0.92, 1.0, 0.98, 1.0);
uniform float pulse_speed : hint_range(0.1, 4.0, 0.05) = 1.15;
uniform float sheen_speed : hint_range(0.05, 1.0, 0.01) = 0.22;

varying vec2 guard_uv;


void vertex() {
	guard_uv = (VERTEX + vec2(19.0)) / 38.0;
}


void fragment() {
	vec2 centered = guard_uv * 2.0 - vec2(1.0);
	float radial_distance = length(centered);
	float disk_mask = 1.0 - smoothstep(0.92, 1.0, radial_distance);
	float stone_surface = 1.0 - smoothstep(0.72, 0.79, radial_distance);
	float center_clear = smoothstep(0.23, 0.38, radial_distance);
	float pulse = 0.72 + 0.28 * sin(
		TIME * pulse_speed + phase_offset * 6.28318530718
	);

	float rim = 1.0 - smoothstep(
		0.025,
		0.078,
		abs(radial_distance - 0.79)
	);
	float halo = (
		smoothstep(0.71, 0.79, radial_distance)
		- smoothstep(0.88, 0.99, radial_distance)
	);

	float diagonal_progress = fract(
		guard_uv.x * 0.82
		+ guard_uv.y * 1.18
		- TIME * sheen_speed
		+ phase_offset
	);
	float primary_sheen = 1.0 - smoothstep(
		0.035,
		0.115,
		abs(diagonal_progress - 0.5)
	);
	float secondary_progress = fract(diagonal_progress + 0.44);
	float secondary_sheen = 1.0 - smoothstep(
		0.025,
		0.075,
		abs(secondary_progress - 0.5)
	);
	float surface_sheen = (
		primary_sheen + secondary_sheen * 0.28
	) * stone_surface * center_clear;

	float alpha = disk_mask * (
		halo * (0.10 + pulse * 0.09)
		+ rim * (0.23 + pulse * 0.11)
		+ surface_sheen * 0.31
	);
	vec3 color = mix(
		shield_color.rgb,
		sheen_color.rgb,
		clamp(primary_sheen * 0.82 + rim * 0.20, 0.0, 1.0)
	);
	COLOR = vec4(color, alpha * shield_color.a);
}
