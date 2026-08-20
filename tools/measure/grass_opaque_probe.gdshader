shader_type spatial;
render_mode unshaded, cull_disabled;

// Variante OPACA de scripts/world/grass_blade.gdshader, sólo para medir.
// No es código de juego -- vive en tools/ a propósito.
//
// Diferencias contra el shader de producción, todas deliberadas:
//   - Sin sampler de atlas y sin escritura de ALPHA. Ese es el punto: el
//     shader real usa alpha_to_coverage, que pierde Early-Z, y medimos que
//     eso cuesta entre 18x y 25x con la geometría fija
//     (docs/presupuesto_render.md). Acá no hay alfa en absoluto, así que la
//     malla queda opaca y el depth pre-pass de Forward+ la aprovecha.
//   - El gradiente base->punta sale de VERTEX.y, no de UV. grass_blade_single
//     NO TIENE UV (se le sacaron a propósito en la vigésima sesión), y
//     justamente por eso el shader de producción la renderiza invisible:
//     samplea el atlas en (0,0), obtiene alfa 0 y descarta todo. Usar la
//     altura local del vértice es lo único que funciona para esa malla.
//
// La matemática de viento se copia tal cual del shader real para que la
// comparación no mezcle variables.

uniform vec4 blade_color : source_color = vec4(0.22, 0.42, 0.18, 1.0);
uniform vec4 tip_color : source_color = vec4(0.55, 0.68, 0.30, 1.0);
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
