shader_type spatial;
render_mode unshaded, cull_disabled;

// Graybox grass blade — vertex-animated wind on the GPU.
// Each MultiMesh instance carries per-instance data in INSTANCE_CUSTOM:
//   x = wind phase offset (0..2pi) — desyncs the sway so the field isn't uniform
//   y = height multiplier (0..1)  — some blades shorter, some taller
//   z = wind strength multiplier  — edges sway more/less

uniform vec4 blade_color : source_color = vec4(0.22, 0.42, 0.18, 1.0);
uniform float wind_speed = 1.6;
uniform float wind_strength = 0.35;
uniform float sway_frequency = 2.2;
uniform float sway_amplitude = 0.06;

void vertex() {
	// Per-instance variation.
	float phase = INSTANCE_CUSTOM.x * TAU;
	float height_mult = 0.7 + INSTANCE_CUSTOM.y * 0.6;
	float wind_mult = 0.6 + INSTANCE_CUSTOM.z * 0.8;

	// Sway grows toward the blade tip (VERTEX.y is the up axis, blade is a
	// vertical quad). Base on world position too so nearby blades stay coherent.
	float sway = sin(TIME * wind_speed * sway_frequency + phase + VERTEX.x * 1.5 + VERTEX.z * 1.3);
	float bend = sway * sway_amplitude * wind_strength * wind_mult * VERTEX.y * height_mult;

	VERTEX.x += bend;
	VERTEX.z += bend * 0.35;
}

void fragment() {
	ALBEDO = blade_color.rgb;
}
