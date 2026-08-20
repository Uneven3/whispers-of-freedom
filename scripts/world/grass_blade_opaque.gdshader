shader_type spatial;
render_mode unshaded, cull_disabled;

// Pasto OPACO: la técnica para la capa de mayor densidad.
// Par de scripts/world/grass_blade.gdshader (el de tarjeta con atlas y
// alfa), elegido desde TerrainGrassInstancer.material_mode.
//
// POR QUÉ SON DOS ARCHIVOS Y NO UN UNIFORM: `alpha_to_coverage` es un
// render_mode, o sea que se fija al compilar el shader. No hay forma de
// apagarlo por material en runtime, así que la variante opaca tiene que
// ser un shader aparte.
//
// POR QUÉ OPACO: medido en este proyecto, con la geometría fija y la misma
// cantidad de instancias, el alfa cuesta entre 18x y 25x más -- pierde
// Early-Z, así que cada capa superpuesta se sombrea igual. La versión
// opaca además cubre MÁS píxeles, porque no recorta nada. En la escena
// real: 5,01 ms contra 2,34 ms, y el overdraw baja de 12,92 capas
// promedio (con el 10% de la pantalla saturando el instrumento) a 1,40.
// Tablas completas en docs/presupuesto_render.md.
//
// EL GRADIENTE SALE DE VERTEX.y, NO DE UV, y eso no es una preferencia:
// grass_blade_single NO TIENE UV (medido: surface_get_format() sin
// ARRAY_FORMAT_TEX_UV). Renderizada con el shader del atlas samplea en
// (0,0), obtiene alfa 0 y descarta todo -- se dibuja invisible pagando el
// costo de vértices. La altura local del vértice es lo único que funciona
// para esa malla.
//
// La matemática de viento es idéntica a la de grass_blade.gdshader a
// propósito: así cambiar de material no cambia también el movimiento.

uniform vec4 blade_color : source_color = vec4(0.22, 0.42, 0.18, 1.0);
uniform vec4 tip_color : source_color = vec4(0.55, 0.68, 0.30, 1.0);
// Altura de la malla en metros, para normalizar el gradiente.
// grass_blade_single mide 1,06; grass_billboard_clump mide 1,04.
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
