@tool
class_name TerrainGrassInstancer
extends Node3D

## Planta pasto en Terrain3D vía su instancer nativo (docs/pasto_godot.md).
## `visible` va a rebuild() directo: el pasto vive en nodos de Terrain3D, no
## como hijos de acá, así que la visibilidad de este Node3D no lo afecta.

const MATERIAL_ATLAS_ALPHA := 0
const MATERIAL_OPAQUE := 1

@export var terrain_path: NodePath:
	set(value):
		terrain_path = value
		_queue_rebuild()
@export_file("*.blend") var blade_asset_path: String = "res://art/blender/grass/grass_billboard_clump.blend":
	set(value):
		blade_asset_path = value
		_queue_rebuild()
@export_file("*.png") var card_texture_path: String = "res://art/blender/grass/grass_card_atlas.png":
	set(value):
		card_texture_path = value
		_queue_rebuild()

## OPAQUE es la técnica de la capa densa: el alfa cuesta 18x-25x más.
## ATLAS_ALPHA sólo sirve para mallas CON UV; sobre una sin UV el pasto se
## renderiza invisible. Medidas y detalle: docs/pasto_godot.md.
@export_enum("atlas_alpha", "opaque") var material_mode: int = MATERIAL_ATLAS_ALPHA:
	set(value):
		material_mode = value
		_queue_rebuild()

## Altura de la malla en metros. Sólo la usa el shader opaco, para
## normalizar el gradiente base->punta (el shader del atlas lo saca de UV.y,
## que la brizna no tiene). grass_blade_single mide 1,06.
@export var blade_height: float = 1.0:
	set(value):
		blade_height = value
		_queue_rebuild()

@export var blade_count: int = 10000:
	set(value):
		blade_count = maxi(1, value)
		_queue_rebuild()
@export var field_radius: float = 40.0:
	set(value):
		field_radius = value
		_queue_rebuild()
@export var clump_count: int = 60:
	set(value):
		clump_count = maxi(1, value)
		_queue_rebuild()
@export var clump_spread: float = 8.0:
	set(value):
		clump_spread = value
		_queue_rebuild()
@export var min_scale: float = 0.7:
	set(value):
		min_scale = value
		_queue_rebuild()
@export var max_scale: float = 1.4:
	set(value):
		max_scale = value
		_queue_rebuild()

@export var blade_color: Color = Color(0.22, 0.42, 0.18, 1.0):
	set(value):
		blade_color = value
		_queue_rebuild()
@export var tip_color: Color = Color(0.55, 0.68, 0.30, 1.0):
	set(value):
		tip_color = value
		_queue_rebuild()
@export var wind_speed: float = 1.6:
	set(value):
		wind_speed = value
		_queue_rebuild()
@export var wind_strength: float = 0.35:
	set(value):
		wind_strength = value
		_queue_rebuild()
@export var sway_frequency: float = 2.2:
	set(value):
		sway_frequency = value
		_queue_rebuild()
@export var sway_amplitude: float = 0.06:
	set(value):
		sway_amplitude = value
		_queue_rebuild()
@export var base_fade_height: float = 0.12:
	set(value):
		base_fade_height = value
		_queue_rebuild()

var _ready_done: bool = false
var _rebuild_queued: bool = false

func _ready() -> void:
	visibility_changed.connect(_queue_rebuild)
	rebuild.call_deferred()
	_ready_done = true

## Debounces Inspector edits (Godot sets every exported var once while
## deserializing the scene, before _ready runs) into a single rebuild.
func _queue_rebuild() -> void:
	if not _ready_done or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()

func rebuild() -> void:
	_rebuild_queued = false
	var terrain: Node = get_node_or_null(terrain_path)
	if terrain == null:
		push_warning("TerrainGrassInstancer: terrain_path does not resolve to a node")
		return
	if not (terrain.has_method("get_assets") and terrain.has_method("get_instancer") and terrain.has_method("get_data")):
		push_warning("TerrainGrassInstancer: node at terrain_path is not a Terrain3D")
		return
	var assets = terrain.get_assets()
	var instancer = terrain.get_instancer()
	var data = terrain.get_data()
	if assets == null or instancer == null or data == null:
		push_warning("TerrainGrassInstancer: terrain node missing assets/instancer/data")
		return

	var base_scene: PackedScene = load(blade_asset_path)
	if base_scene == null:
		push_warning("TerrainGrassInstancer: could not load '%s'" % blade_asset_path)
		return

	_warn_if_alpha_mode_on_uvless_mesh(base_scene)

	var mesh_name := "TerrainGrassInstancer_%s" % name
	var mesh_id: int = _register_mesh_asset(assets, mesh_name, base_scene)

	# Always clear first, even before an early "stay hidden" return -- safe
	# no-op on an untouched mesh_id, and keeps retuning/toggling visible from
	# ever accumulating stale instances.
	instancer.clear_by_mesh(mesh_id)
	if not visible:
		return
	var generated := _generate_instance_data(data, global_position)
	instancer.add_transforms(mesh_id, generated.transforms, generated.colors, true)

## Nunca muta una entrada ya registrada en el lugar, y pisar un id existente
## exige set_id() antes o set_mesh_asset() corrompe otra entrada en silencio.
## Las dos trampas, con las sondas que las encontraron: docs/pasto_godot.md.
func _register_mesh_asset(assets, mesh_name: String, base_scene: PackedScene) -> int:
	var mesh_asset = ClassDB.instantiate("Terrain3DMeshAsset")
	mesh_asset.set_name(mesh_name)
	mesh_asset.set_scene_file(base_scene)
	mesh_asset.set_material_override(_build_shader_material())
	const SHADOWS_OFF := 0
	mesh_asset.set_cast_shadows(SHADOWS_OFF)

	var existing_id: int = -1
	for existing in assets.get_mesh_list():
		if existing.get_name() == mesh_name:
			existing_id = existing.get_id()
			break

	if existing_id != -1:
		mesh_asset.set_id(existing_id)
		assets.set_mesh_asset(existing_id, mesh_asset)
	else:
		assets.set_mesh_asset(assets.get_mesh_list().size(), mesh_asset)
	return mesh_asset.get_id()

func _build_shader_material() -> ShaderMaterial:
	if material_mode == MATERIAL_OPAQUE:
		return _build_opaque_material()
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/world/grass_blade.gdshader")
	mat.set_shader_parameter("card_texture", load(card_texture_path))
	mat.set_shader_parameter("blade_color", blade_color)
	mat.set_shader_parameter("tip_color", tip_color)
	mat.set_shader_parameter("wind_speed", wind_speed)
	mat.set_shader_parameter("wind_strength", wind_strength)
	mat.set_shader_parameter("sway_frequency", sway_frequency)
	mat.set_shader_parameter("sway_amplitude", sway_amplitude)
	mat.set_shader_parameter("base_fade_height", base_fade_height)
	return mat

## Centros de mata uniformes EN ÁREA (sqrt(randf()), no randf()) o se
## amontonarían hacia el origen. Testeable: sólo depende de get_height().
func _generate_instance_data(terrain_data, origin: Vector3) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var clumps: Array[Vector2] = []
	for c in clump_count:
		var angle := rng.randf_range(0.0, TAU)
		var dist := sqrt(rng.randf()) * field_radius
		clumps.append(Vector2(cos(angle) * dist, sin(angle) * dist))

	var transforms: Array[Transform3D] = []
	var colors := PackedColorArray()
	for i in blade_count:
		var center: Vector2 = clumps[rng.randi_range(0, clumps.size() - 1)]
		var offset := Vector2(rng.randfn(0.0, clump_spread), rng.randfn(0.0, clump_spread))
		var offset_from_center: Vector2 = center + offset
		if offset_from_center.length() > field_radius:
			# Discard rather than limit_length() onto the boundary, which
			# would pile every out-of-bounds point exactly onto the edge.
			continue
		var world_x := origin.x + offset_from_center.x
		var world_z := origin.z + offset_from_center.y
		var ground_height: float = terrain_data.get_height(Vector3(world_x, 0.0, world_z))
		if is_nan(ground_height):
			continue  # outside sculpted regions

		var blade_scale := rng.randf_range(min_scale, max_scale)
		var rot_y := rng.randf_range(0.0, TAU)
		var tilt := rng.randf_range(-0.12, 0.12)
		# scaled_local(), not scaled() -- the latter also scales the origin,
		# drifting each blade's root position off its sampled ground point.
		var blade_transform := Transform3D(
			Basis(Vector3(0, 1, 0), rot_y) * Basis(Vector3(1, 0, 0), tilt),
			Vector3(world_x, ground_height, world_z)
		).scaled_local(Vector3(blade_scale, blade_scale, blade_scale))
		transforms.append(blade_transform)

		var height_frac := (blade_scale - min_scale) / maxf(max_scale - min_scale, 0.001)
		colors.append(Color(rng.randf_range(0.0, 1.0), height_frac, rng.randf_range(0.0, 1.0), 0.0))

	return {"transforms": transforms, "colors": colors}


func _build_opaque_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/world/grass_blade_opaque.gdshader")
	mat.set_shader_parameter("blade_color", blade_color)
	mat.set_shader_parameter("tip_color", tip_color)
	mat.set_shader_parameter("blade_height", blade_height)
	mat.set_shader_parameter("wind_speed", wind_speed)
	mat.set_shader_parameter("wind_strength", wind_strength)
	mat.set_shader_parameter("sway_frequency", sway_frequency)
	mat.set_shader_parameter("sway_amplitude", sway_amplitude)
	return mat


## Una malla sin UV con el shader del atlas se dibuja INVISIBLE, pagando
## igual el costo de vértices y sin un solo error en consola.
## push_warning y no assert (§5): lo dispara un dato del Inspector.
func _warn_if_alpha_mode_on_uvless_mesh(base_scene: PackedScene) -> void:
	if material_mode != MATERIAL_ATLAS_ALPHA:
		return
	var mesh := _first_mesh_of(base_scene)
	if mesh == null or mesh.get_surface_count() == 0:
		return
	if (mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV) != 0:
		return
	push_warning(("TerrainGrassInstancer: '%s' no tiene UV y material_mode es "
		+ "atlas_alpha, asi que se va a renderizar invisible. Usar "
		+ "material_mode = opaque para esta malla.") % blade_asset_path)


func _first_mesh_of(packed: PackedScene) -> Mesh:
	var instance: Node = packed.instantiate()
	var mesh: Mesh = null
	var stack: Array[Node] = [instance]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			mesh = (node as MeshInstance3D).mesh
			break
		for child in node.get_children():
			stack.append(child)
	instance.queue_free()
	return mesh
