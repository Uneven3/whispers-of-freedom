extends "res://scripts/world/grass_terrain_instancer.gd"

## Variante instrumental de TerrainGrassInstancer que puede plantar el pasto
## con material OPACO, para poder medir dentro de terrain_base.tscn la
## técnica que docs/presupuesto_render.md identificó como la correcta para
## la capa densa. El instancer de producción sólo sabe construir el shader
## del atlas con alfa.
##
## HEREDA en vez de duplicar, a propósito. Copiar las ~220 líneas del
## original dejaría dos copias del algoritmo de dispersión en clumps que
## divergirían en silencio la primera vez que alguien toque una: mediríamos
## un campo de pasto que no es el que se shipea. Heredar tampoco modifica
## el archivo de producción -- la restricción se cumple igual.
##
## Sin class_name (no contamina el namespace global con algo instrumental;
## se carga por path, mismo patrón que test/unit/test_grass_terrain_instancer.gd)
## y sin @tool (el original lo necesita para tunearse en vivo en el editor;
## este no debe correr nunca en el editor, porque es justamente ahí donde
## Terrain3D hornea entradas en el terrain_assets.tres versionado).

const MATERIAL_ATLAS_ALPHA := 0
const MATERIAL_OPAQUE := 1

## atlas_alpha reproduce exactamente el material de producción (llama a
## super()); opaque usa tools/measure/grass_opaque_probe.gdshader.
@export_enum("atlas_alpha", "opaque") var material_mode: int = MATERIAL_OPAQUE

## Altura de la malla, para el gradiente base->punta del shader opaco. El
## shader de producción lo saca de UV.y, pero grass_blade_single no tiene UV.
@export var blade_height: float = 1.0

## Copia los @export del nodo de producción que este probe reemplaza.
##
## Sin esto el probe correría con los defaults de la clase
## (blade_count=10000, field_radius=40, clump_count=60, clump_spread=8) en
## vez de los overrides reales de terrain_base.tscn (4000 / 20 / 2000 / 1.0)
## -- 33x menos clumps y 8x más spread que la escena real, o sea una
## medición "dentro de terrain_base.tscn" que no representa a
## terrain_base.tscn. Se copian por get_property_list() y no a mano para que
## un @export nuevo en el original no quede silenciosamente sin copiar.
func copy_settings_from(source: Node) -> void:
	for property in source.get_property_list():
		if (property["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE) == 0:
			continue
		if (property["usage"] & PROPERTY_USAGE_STORAGE) == 0:
			continue
		var key: String = property["name"]
		if key in ["material_mode", "blade_height"]:
			continue
		set(key, source.get(key))

## Único punto de override. El padre llama a esto desde
## _register_mesh_asset() -> set_material_override(), y devolver un
## ShaderMaterial (no un StandardMaterial3D) es lo que deja respetar la
## firma del padre sin duplicar su lógica de registro, que tiene sutilezas
## reales (set_id() antes de set_mesh_asset(), no mutar entradas ya
## registradas -- ver los comentarios del original).
func _build_shader_material() -> ShaderMaterial:
	if material_mode == MATERIAL_ATLAS_ALPHA:
		return super()

	var mat := ShaderMaterial.new()
	mat.shader = load("res://tools/measure/grass_opaque_probe.gdshader")
	mat.set_shader_parameter("blade_color", blade_color)
	mat.set_shader_parameter("tip_color", tip_color)
	mat.set_shader_parameter("blade_height", blade_height)
	mat.set_shader_parameter("wind_speed", wind_speed)
	mat.set_shader_parameter("wind_strength", wind_strength)
	mat.set_shader_parameter("sway_frequency", sway_frequency)
	mat.set_shader_parameter("sway_amplitude", sway_amplitude)
	return mat
