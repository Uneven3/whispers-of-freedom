shader_type spatial;
render_mode unshaded, cull_disabled;

// Pasto opaco, la técnica de la capa densa. Por qué opaco, por qué es un
// archivo aparte de grass_blade.gdshader y por qué el gradiente sale de
// VERTEX.y: docs/pasto_godot.md, "Referencia: los dos shaders y el instancer".

uniform vec4 blade_color : source_color = vec4(0.22, 0.42, 0.18, 1.0);
uniform vec4 tip_color : source_color = vec4(0.55, 0.68, 0.30, 1.0);
// Altura de la malla en metros. grass_blade_single mide 1,06.
uniform float blade_height = 1.0;
uniform float wind_speed = 1.6;
uniform float wind_strength = 0.35;
uniform float sway_frequency = 2.2;
uniform float sway_amplitude = 0.06;

varying float v_height_fraction;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * TAU;
	float height_mult = 0.7 + INSTANCE_CUSTOM.y * 0.6;
	float wind_mult = 0.6 + INSTANCE_CUSTOM.z * 0.8;

	v_height_fraction = clamp(VERTEX.y / max(blade_height, 0.0001), 0.0, 1.0);

	float sway = sin(TIME * wind_speed * sway_frequency + phase + VERTEX.x * 1.5 + VERTEX.z * 1.3);
	float bend = sway * sway_amplitude * wind_strength * wind_mult * VERTEX.y * height_mult;
	VERTEX.x += bend;
	VERTEX.z += bend * 0.35;
}

void fragment() {
	ALBEDO = mix(blade_color.rgb, tip_color.rgb, v_height_fraction);
}
