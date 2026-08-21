@tool
class_name GrassProbeField
extends Node3D

## Visor de pasto suelto para comparar mallas a ojo, sin Terrain3D, suelo
## plano en y=0. No es parte del juego que se shipea. Contexto:
## docs/pasto_godot.md.

@export_file("*.blend") var mesh_path: String = "res://art/blender/grass/grass_billboard_clump.blend":
	set(value):
		mesh_path = value
		_queue_rebuild()
## Material plano sin atlas: muestra la silueta real de la malla en vez de
## lo que un UV de atlas que no corresponde recortaría. Apagado usa el
## grass_blade.gdshader real.
@export var flat_material: bool = false:
	set(value):
		flat_material = value
		_queue_rebuild()
@export_file("*.png") var card_texture_path: String = "res://art/blender/grass/grass_card_atlas.png":
	set(value):
		card_texture_path = value
		_queue_rebuild()
@export var blade_count: int = 3000:
	set(value):
		blade_count = maxi(1, value)
		_queue_rebuild()
@export var field_radius: float = 6.0:
	set(value):
		field_radius = value
		_queue_rebuild()
@export var blade_color: Color = Color(0.26666668, 0.35686275, 0.02745098, 1.0):
	set(value):
		blade_color = value
		_queue_rebuild()
@export var tip_color: Color = Color(0.15294118, 0.27058825, 0.050980393, 1.0):
	set(value):
		tip_color = value
		_queue_rebuild()

var _mmi: MultiMeshInstance3D
var _ready_done := false
var _rebuild_queued := false

func _ready() -> void:
	_mmi = MultiMeshInstance3D.new()
	add_child(_mmi)
	rebuild.call_deferred()
	_ready_done = true

func _queue_rebuild() -> void:
	if not _ready_done or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()

func rebuild() -> void:
	_rebuild_queued = false
	if _mmi == null:
		return
	var mesh := _load_mesh_from_blend(mesh_path)
	if mesh == null:
		return

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = blade_count

	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	for i in blade_count:
		var angle := rng.randf_range(0.0, TAU)
		var dist := sqrt(rng.randf()) * field_radius
		var pos := Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var yaw := rng.randf_range(0.0, TAU)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, yaw), pos))

	_mmi.multimesh = mm
	_mmi.material_override = _build_material()

## Godot imports .blend natively as a PackedScene wrapping a MeshInstance3D
## -- instantiate once, grab the Mesh resource, discard the temp node.
func _load_mesh_from_blend(path: String) -> Mesh:
	var packed: PackedScene = load(path)
	if packed == null:
		return null
	var instance: Node = packed.instantiate()
	var mesh: Mesh = null
	var stack: Array[Node] = [instance]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and n.mesh != null:
			mesh = n.mesh
			break
		for child in n.get_children():
			stack.append(child)
	instance.queue_free()
	return mesh

func _build_material() -> Material:
	if flat_material:
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = blade_color
		return mat
	var shader_mat := ShaderMaterial.new()
	shader_mat.shader = load("res://scripts/world/grass_blade.gdshader")
	shader_mat.set_shader_parameter("card_texture", load(card_texture_path))
	shader_mat.set_shader_parameter("blade_color", blade_color)
	shader_mat.set_shader_parameter("tip_color", tip_color)
	shader_mat.set_shader_parameter("wind_speed", 0.0)
	shader_mat.set_shader_parameter("wind_strength", 0.0)
	shader_mat.set_shader_parameter("sway_frequency", 0.0)
	shader_mat.set_shader_parameter("sway_amplitude", 0.0)
	shader_mat.set_shader_parameter("base_fade_height", 0.2)
	return shader_mat
