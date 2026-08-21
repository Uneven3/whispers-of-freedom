shader_type spatial;
render_mode unshaded, cull_disabled, alpha_to_coverage;

// alpha_to_coverage necesita MSAA activo (project.godot) para antialiasar
// el recorte. INSTANCE_CUSTOM: x = fase, y = altura, z = fuerza de viento.
// Contexto: docs/pasto_godot.md.

uniform sampler2D card_texture : source_color;
uniform vec4 blade_color : source_color = vec4(0.22, 0.42, 0.18, 1.0);
uniform vec4 tip_color : source_color = vec4(0.55, 0.68, 0.30, 1.0);
uniform float wind_speed = 1.6;
uniform float wind_strength = 0.35;
uniform float sway_frequency = 2.2;
uniform float sway_amplitude = 0.06;
uniform float base_fade_height : hint_range(0.0, 0.5) = 0.12;

varying float v_height_fraction;

void vertex() {
	float phase = INSTANCE_CUSTOM.x * TAU;
	float height_mult = 0.7 + INSTANCE_CUSTOM.y * 0.6;
	float wind_mult = 0.6 + INSTANCE_CUSTOM.z * 0.8;

	// Godot's .blend importer flips V on import (confirmed empirically,
	// authored base=0/tip=1 comes back as base=1/tip=0).
	v_height_fraction = clamp(1.0 - UV.y, 0.0, 1.0);

	float sway = sin(TIME * wind_speed * sway_frequency + phase + VERTEX.x * 1.5 + VERTEX.z * 1.3);
	float bend = sway * sway_amplitude * wind_strength * wind_mult * VERTEX.y * height_mult;
	VERTEX.x += bend;
	VERTEX.z += bend * 0.35;
}

void fragment() {
	vec4 tex = texture(card_texture, UV);
	ALBEDO = mix(blade_color.rgb, tip_color.rgb, v_height_fraction);
	ALPHA = tex.a * smoothstep(0.0, base_fade_height, v_height_fraction);
}
