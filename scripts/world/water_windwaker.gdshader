shader_type spatial;
render_mode cull_disabled;

// Variante Wind Waker del agua. Archivo aparte y no un uniform del shader
// estilizado: la diferencia es de técnica, no de parámetro (mismo criterio
// que grass_blade_opaque.gdshader). Ver docs/SISTEMAS.md, sección "Agua".

uniform vec4 water_color : source_color = vec4(0.09, 0.42, 0.60, 1.0);
uniform vec4 water_color_shallow : source_color = vec4(0.30, 0.70, 0.78, 1.0);
uniform vec4 foam_color : source_color = vec4(0.97, 0.99, 1.0, 1.0);

uniform sampler2D foam_pattern : hint_default_white, repeat_enable, filter_linear_mipmap;

uniform vec2 uv_to_meters = vec2(40.0, 13.5);
uniform bool world_space_noise = false;

uniform float shore_meters : hint_range(0.5, 60.0) = 14.0;
// Bandas duras en vez de degradado: es lo que hace que se lea dibujado.
uniform float band_count : hint_range(1.0, 8.0) = 3.0;
uniform float shore_foam_meters : hint_range(0.0, 10.0) = 2.2;

uniform float patch_meters : hint_range(1.0, 60.0) = 9.0;
uniform float patch_threshold : hint_range(0.0, 1.0) = 0.66;
uniform float patch_softness : hint_range(0.001, 0.3) = 0.03;
uniform float patch_ring : hint_range(0.0, 0.3) = 0.08;

uniform vec2 flow_meters_per_second = vec2(0.0, 0.0);
uniform float drift_speed : hint_range(0.0, 2.0) = 0.10;
uniform float roughness_value : hint_range(0.0, 1.0) = 0.35;

varying vec2 v_uv;
varying vec3 v_world;

void vertex() {
	v_uv = UV;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 meters = world_space_noise ? v_world.xz : v_uv * uv_to_meters;
	meters -= flow_meters_per_second * TIME;

	float shore_dist = v_uv.y * uv_to_meters.y;

	// Profundidad cuantizada a bandas, no interpolada.
	float depth_t = clamp(shore_dist / shore_meters, 0.0, 1.0);
	float banded = floor(depth_t * band_count) / max(band_count - 1.0, 1.0);
	vec3 base = mix(water_color_shallow.rgb, water_color.rgb, clamp(banded, 0.0, 1.0));

	// Parches de espuma: el patrón celular recortado duro da manchas con
	// borde, que es la firma visual del Wind Waker.
	vec2 patch_uv = meters / patch_meters + vec2(TIME * drift_speed * 0.05, TIME * drift_speed * 0.03);
	float cell = texture(foam_pattern, patch_uv).r;
	float patch = smoothstep(patch_threshold, patch_threshold + patch_softness, cell);
	float patch_edge = smoothstep(patch_threshold - patch_ring, patch_threshold, cell) - patch;

	// Contorno de orilla, duro y del mismo blanco que los parches.
	float shore_foam = 1.0 - smoothstep(shore_foam_meters * 0.75, shore_foam_meters, shore_dist);

	float foam = clamp(max(max(patch, patch_edge), shore_foam), 0.0, 1.0);
	ALBEDO = mix(base, foam_color.rgb, foam);

	METALLIC = 0.0;
	ROUGHNESS = mix(roughness_value, 0.95, foam);
	SPECULAR = 0.5;
}
