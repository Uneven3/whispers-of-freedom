shader_type spatial;
render_mode cull_disabled;

// Rationale y por qué es opaca: docs/SISTEMAS.md, sección "Agua".

uniform vec4 shallow_color : source_color = vec4(0.29, 0.61, 0.62, 1.0);
uniform vec4 deep_color : source_color = vec4(0.06, 0.20, 0.31, 1.0);
uniform vec4 foam_color : source_color = vec4(0.90, 0.95, 0.97, 1.0);
uniform vec4 sky_color : source_color = vec4(0.55, 0.72, 0.92, 1.0);

// La normal viene GUARDADA en la textura, no derivada por diferencia central:
// eso saca 4 de las 5 evaluaciones de ruido por píxel, y evita que un paso
// fijo en metros caiga bajo un texel y aplane el relieve.
uniform sampler2D wave_normal_map : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D foam_pattern : hint_default_white, repeat_enable, filter_linear_mipmap;

// Metros que abarca cada eje UV en esta malla. Sin esto una banda en UV mide
// 9x más en el lago que en el río, que comparten shader.
uniform vec2 uv_to_meters = vec2(40.0, 13.5);
uniform bool world_space_noise = false;

uniform float shore_meters : hint_range(0.5, 40.0) = 6.0;
uniform float foam_meters : hint_range(0.0, 10.0) = 1.1;
uniform float foam_jitter_meters : hint_range(0.0, 10.0) = 1.6;
uniform float foam_detail_meters : hint_range(0.5, 40.0) = 4.0;

uniform float wave_meters : hint_range(0.2, 40.0) = 2.6;
uniform float wave_strength : hint_range(0.0, 3.0) = 1.0;
uniform float wave_speed : hint_range(0.0, 4.0) = 0.5;
uniform vec2 flow_meters_per_second = vec2(0.0, 0.0);

uniform float roughness_value : hint_range(0.0, 1.0) = 0.10;
uniform float fresnel_power : hint_range(0.5, 8.0) = 4.0;
uniform float fresnel_strength : hint_range(0.0, 1.0) = 0.5;
uniform float glint_strength : hint_range(0.0, 1.0) = 0.10;

varying vec2 v_uv;
varying vec3 v_world;

void vertex() {
	v_uv = UV;
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 meters = world_space_noise ? v_world.xz : v_uv * uv_to_meters;
	meters -= flow_meters_per_second * TIME;

	// Dos capas a escalas distintas: una sola se lee como una textura
	// deslizándose. Los mipmaps las aplanan solos con la distancia, así que
	// no hace falta apagar el detalle a mano.
	vec2 uv_a = meters / wave_meters + vec2(TIME * wave_speed * 0.05, TIME * wave_speed * 0.02);
	vec2 uv_b = meters / (wave_meters * 2.7) - vec2(TIME * wave_speed * 0.03, TIME * wave_speed * 0.06);
	vec3 normal_a = texture(wave_normal_map, uv_a).rgb * 2.0 - 1.0;
	vec3 normal_b = texture(wave_normal_map, uv_b).rgb * 2.0 - 1.0;
	vec3 wave_normal = normalize(vec3((normal_a.xy + normal_b.xy) * wave_strength, 1.0));
	NORMAL_MAP = wave_normal * 0.5 + 0.5;

	float shore_dist = v_uv.y * uv_to_meters.y;
	vec3 base = mix(shallow_color.rgb, deep_color.rgb, smoothstep(0.0, shore_meters, shore_dist));

	float jitter = texture(foam_pattern, meters / foam_detail_meters).r - 0.5;
	float foam_edge = max(foam_meters + jitter * foam_jitter_meters, 0.01);
	float foam = 1.0 - smoothstep(foam_edge * 0.4, foam_edge, shore_dist);

	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0), fresnel_power);
	vec3 albedo = mix(base, sky_color.rgb, fresnel * fresnel_strength);
	// Cresta = cuánto se inclinó la normal. Se apaga sola al mipmapear.
	albedo += smoothstep(0.55, 0.95, 1.0 - wave_normal.z) * glint_strength;
	ALBEDO = mix(albedo, foam_color.rgb, foam);

	METALLIC = 0.0;
	ROUGHNESS = mix(roughness_value, 0.9, foam);
	SPECULAR = mix(0.6, 0.2, foam);
}
