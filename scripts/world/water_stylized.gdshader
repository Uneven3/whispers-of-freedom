shader_type spatial;
render_mode cull_disabled;

// Agua OPACA con reflejo estilizado.
//
// POR QUÉ OPACA: medido en este proyecto, sobre la misma superficie, el agua
// transparente cuesta 1,98x y con refracción 2,26x (docs/presupuesto_render.md).
// La transparencia pierde Early-Z y la refracción además fuerza una copia de
// la pantalla por frame. Y a diferencia del pasto, el agua no se puede ralear
// ni alejar: un lago cubre lo que cubre. Es el peor caso del proyecto, así
// que se paga la técnica barata.
//
// POR QUÉ NO `unshaded`, que es la excepción a la regla del resto del
// proyecto: el reflejo del cielo ES la iluminación especular estándar contra
// el radiance map que Godot genera del Sky. Sin evaluación de luz no hay
// reflejo, y el reflejo es justamente lo que hace que el agua se lea como
// agua. No hace falta ReflectionProbe para el cielo.
//
// LO QUE NO HACE, A PROPÓSITO: no lee DEPTH_TEXTURE ni SCREEN_TEXTURE. El
// gradiente de orilla y la espuma salen de UV.y, que la geometría define:
// las mallas se generan sabiendo dónde está la orilla (el lago es un disco
// con UV radial, el río una cinta con UV.y transversal al cauce), así que la
// distancia a la orilla es dato de generación, no algo que haya que
// descubrir leyendo el buffer de profundidad.

uniform vec4 shallow_color : source_color = vec4(0.29, 0.61, 0.62, 1.0);
uniform vec4 deep_color : source_color = vec4(0.06, 0.20, 0.31, 1.0);
uniform vec4 foam_color : source_color = vec4(0.85, 0.94, 0.96, 1.0);

uniform float roughness_value : hint_range(0.0, 1.0) = 0.06;
uniform float metallic_value : hint_range(0.0, 1.0) = 0.35;

// UV.y = 0 en la orilla, 1 en el centro. La geometría lo garantiza.
uniform float shore_band : hint_range(0.0, 0.5) = 0.22;
uniform float foam_band : hint_range(0.0, 0.3) = 0.07;
uniform float foam_speed = 0.6;
uniform float foam_scale = 26.0;

uniform float wave_speed = 0.35;
uniform float wave_scale = 5.0;
uniform float wave_strength : hint_range(0.0, 1.0) = 0.22;
// Empuje de la superficie a lo largo de UV.x, para que el río se lea
// corriendo hacia abajo en vez de quieto.
uniform float flow_speed = 0.25;

varying vec2 v_uv;

// Ruido de valor barato: dos octavas alcanzan para ondas y espuma, y evita
// depender de una textura (una menos que cargar y muestrear).
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void vertex() {
	v_uv = UV;
}

void fragment() {
	vec2 flow = vec2(TIME * flow_speed, 0.0);

	// Dos capas de ondas en direcciones distintas: una sola se lee como una
	// textura deslizándose, dos se leen como agua.
	vec2 p = v_uv * wave_scale + flow;
	float n1 = value_noise(p + vec2(TIME * wave_speed, TIME * wave_speed * 0.3));
	float n2 = value_noise(p * 1.9 - vec2(TIME * wave_speed * 0.7, TIME * wave_speed));
	float waves = (n1 + n2) * 0.5;

	// Perturbar la normal en espacio tangente, sin mover vértices: así el
	// reflejo tiembla sin depender de que la malla esté subdividida.
	vec2 grad = vec2(
		value_noise(p + vec2(0.06, 0.0)) - n1,
		value_noise(p + vec2(0.0, 0.06)) - n1);
	NORMAL_MAP = normalize(vec3(grad * wave_strength * 8.0, 1.0)) * 0.5 + 0.5;

	float depth_t = smoothstep(0.0, shore_band, v_uv.y);
	vec3 base = mix(shallow_color.rgb, deep_color.rgb, depth_t);

	// Espuma en la orilla, rota con ruido para que no sea un anillo perfecto.
	float foam_edge = foam_band * (0.6 + 0.8 * value_noise(
		v_uv * foam_scale + vec2(TIME * foam_speed, 0.0)));
	float foam = 1.0 - smoothstep(0.0, foam_edge, v_uv.y);

	ALBEDO = mix(base, foam_color.rgb, foam);
	// La espuma es blanca y mate; el agua abierta es lisa y reflectante.
	ROUGHNESS = mix(roughness_value, 0.85, foam);
	METALLIC = mix(metallic_value, 0.0, foam);
	SPECULAR = 0.6;
	// Un toque de brillo en las crestas, para que se lea el movimiento
	// incluso cuando el cielo reflejado es plano.
	ALBEDO += vec3(smoothstep(0.75, 1.0, waves) * 0.06);
}
