@tool
class_name GrassField
extends Node3D

## Procedural grass field rendered with a single MultiMeshInstance3D (one draw
## call for all blades) + vertex-shader wind animation on the GPU.
##
## Godot-recommended vegetation technique (see "Optimization using MultiMeshes"
## and "Animating thousands of fish" docs): thousands of instances, one node,
## no per-instance CPU animation, custom_aabb for correct frustum culling.
##
## @tool so tuning the knobs below in the Inspector rebuilds live, in-editor
## or at runtime, without a scene restart — see _queue_rebuild().

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
@export var min_blade_height: float = 0.4:
	set(value):
		min_blade_height = value
		_queue_rebuild()
@export var max_blade_height: float = 1.0:
	set(value):
		max_blade_height = value
		_queue_rebuild()
@export var min_scale: float = 0.7:
	set(value):
		min_scale = value
		_queue_rebuild()
@export var max_scale: float = 1.4:
	set(value):
		max_scale = value
		_queue_rebuild()
@export var cast_shadows: bool = false:
	set(value):
		cast_shadows = value
		if _mmi:
			_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not value else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
## Which Blender-authored blade mesh to instance — swap this to compare blade
## variants (single crossed-leaf vs. tuft) without touching code. See
## tools/blender/generate_grass_blade_*.py.
@export_file("*.blend") var blade_asset_path: String = "res://art/blender/grass/grass_blade_single.blend":
	set(value):
		blade_asset_path = value
		_queue_rebuild()
## Overrides grass_blade.gdshader's blade_color uniform — lets several
## GrassField instances tell each other apart at a glance (e.g. comparing
## blade variants side by side) without editing the shader itself. Default
## matches the shader's own default, so leaving this untouched changes
## nothing.
@export var blade_color: Color = Color(0.22, 0.42, 0.18, 1.0):
	set(value):
		blade_color = value
		if _mmi:
			var mat: ShaderMaterial = _mmi.multimesh.mesh.surface_get_material(0)
			if mat:
				mat.set_shader_parameter("blade_color", blade_color)

var _mmi: MultiMeshInstance3D
var _blade_positions: Array[Vector2] = []
var _ready_done: bool = false
var _rebuild_queued: bool = false

func _ready() -> void:
	_build_field()
	_ready_done = true

## Debounces Inspector edits (Godot sets every exported var once while
## deserializing the scene, before _ready runs) into a single rebuild.
func _queue_rebuild() -> void:
	if not _ready_done or _rebuild_queued:
		return
	_rebuild_queued = true
	rebuild.call_deferred()

## Positions the generator computed for each blade (source of truth for the
## distribution). Readable under headless — MultiMesh buffers are not.
func get_blade_positions() -> Array[Vector2]:
	return _blade_positions

## Rebuilds the MultiMesh from current export values. Safe to call at runtime.
func rebuild() -> void:
	_rebuild_queued = false
	if _mmi:
		# remove_child first — queue_free alone leaves the old "Grass" node
		# in the tree until end-of-frame, so the new one collides and gets
		# renamed "Grass2", breaking get_node("Grass") lookups.
		remove_child(_mmi)
		_mmi.queue_free()
	_mmi = null
	_blade_positions.clear()
	_build_field()

func _build_field() -> void:
	var mesh := _build_blade_mesh()

	# Fixed seed so the field looks the same on every launch (deterministic
	# graybox); tweak or export if you want random variation per run.
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_custom_data = true
	mm.mesh = mesh
	mm.instance_count = blade_count

	# Clump centers — blades cluster near these for an organic look.
	var clumps: Array[Vector2] = []
	for c in clump_count:
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf() * field_radius
		clumps.append(Vector2(cos(angle) * dist, sin(angle) * dist))

	_blade_positions.clear()
	_blade_positions.resize(blade_count)
	for i in blade_count:
		# Pick a clump, then scatter around it with gaussian-ish falloff.
		var center: Vector2 = clumps[rng.randi_range(0, clumps.size() - 1)]
		var offset := Vector2(
			rng.randfn(0.0, clump_spread),
			rng.randfn(0.0, clump_spread)
		)
		var pos2d := center + offset
		pos2d = pos2d.limit_length(field_radius)  # keep blades inside the field
		_blade_positions[i] = pos2d

		var scale := rng.randf_range(min_scale, max_scale)
		var height_frac := (scale - min_scale) / maxf(max_scale - min_scale, 0.001)
		var rot_y := rng.randf_range(0.0, TAU)
		# Random tilt so blades aren't perfectly vertical.
		var tilt := rng.randf_range(-0.12, 0.12)

		var xform := Transform3D(
			Basis(Vector3(0, 1, 0), rot_y) * Basis(Vector3(1, 0, 0), tilt),
			Vector3(pos2d.x, 0.0, pos2d.y)
		).scaled(Vector3(scale, scale, scale))
		mm.set_instance_transform(i, xform)
		# INSTANCE_CUSTOM: x=phase, y=height mult, z=wind mult.
		mm.set_instance_custom_data(i, Color(
			rng.randf_range(0.0, 1.0),
			height_frac,
			rng.randf_range(0.0, 1.0),
			0.0
		))

	_mmi = MultiMeshInstance3D.new()
	_mmi.name = "Grass"
	_mmi.multimesh = mm
	_mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if not cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	# MultiMesh has all-or-none instance culling — a correct AABB makes the
	# whole field (and only the field) frustum-culled as one unit.
	_mmi.custom_aabb = AABB(Vector3(-field_radius, 0.0, -field_radius), Vector3(field_radius * 2.0, max_blade_height, field_radius * 2.0))
	add_child(_mmi)

## Blender-authored crossed-leaf blade (two crossed planes, pointed at tip and
## sunk base, waist row at 30% height — see tools/blender/generate_grass_blade_*.py
## and art/blender/grass/grass_blade_*.blend). Cached per-process and per-path
## (several GrassField instances can point at different blade_asset_path
## values, e.g. scenes/grass_comparison.tscn) since a given asset's base shape
## never changes between Inspector rebuilds — only max_blade_height does.
static var _cached_base_meshes: Dictionary = {}
static var _load_failed_paths: Dictionary = {}

func _build_blade_mesh() -> Mesh:
	var base := _load_base_blade_mesh()
	if base == null:
		return _build_fallback_blade_mesh()
	return _rescaled_blade_mesh(base, max_blade_height)

## Loads and caches the unit-height (1.0 m) blade mesh from blade_asset_path.
## Returns null (and warns once per path) if the asset can't be loaded — e.g.
## Blender's path isn't configured in Editor Settings > Filesystem > Import >
## Blender on this machine (see "Cómo trabajar en este repo" in docs/AHORA.md).
func _load_base_blade_mesh() -> ArrayMesh:
	if _cached_base_meshes.has(blade_asset_path):
		return _cached_base_meshes[blade_asset_path]
	if _load_failed_paths.has(blade_asset_path):
		return null
	var packed: PackedScene = load(blade_asset_path)
	if packed == null:
		_load_failed_paths[blade_asset_path] = true
		push_warning("could not load '%s' — falling back to the procedural blade (configure Editor Settings > Filesystem > Import > Blender > Blender Path, see docs/AHORA.md)" % blade_asset_path)
		return null
	var inst := packed.instantiate()
	var mesh_node := _find_mesh_instance(inst)
	if mesh_node == null or mesh_node.mesh == null:
		_load_failed_paths[blade_asset_path] = true
		push_warning("'%s' has no usable MeshInstance3D — falling back to the procedural blade" % blade_asset_path)
		inst.free()
		return null
	var mesh := mesh_node.mesh as ArrayMesh
	_cached_base_meshes[blade_asset_path] = mesh
	inst.free()
	return mesh

func _find_mesh_instance(node: Node) -> MeshInstance3D:
	if node is MeshInstance3D:
		return node
	for child in node.get_children():
		var found := _find_mesh_instance(child)
		if found:
			return found
	return null

## Rescales the unit-height base mesh's Y axis to max_blade_height and applies
## the wind ShaderMaterial — width/taper stay exactly as authored in Blender.
func _rescaled_blade_mesh(base: ArrayMesh, height: float) -> ArrayMesh:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/world/grass_blade.gdshader")
	mat.set_shader_parameter("blade_color", blade_color)
	var out := ArrayMesh.new()
	for i in base.get_surface_count():
		var arrays := base.surface_get_arrays(i)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for j in verts.size():
			verts[j] = Vector3(verts[j].x, verts[j].y * height, verts[j].z)
		arrays[Mesh.ARRAY_VERTEX] = verts
		out.add_surface_from_arrays(base.surface_get_primitive_type(i), arrays)
		out.surface_set_material(i, mat)
	return out

## Fallback used only when the Blender asset can't be loaded (see
## _load_base_blade_mesh) — the original flat-rectangle crossed quad, so a
## machine without Blender configured still gets a playable (if plainer) field
## instead of a crash.
func _build_fallback_blade_mesh() -> Mesh:
	var blade := ArrayMesh.new()
	var h := max_blade_height
	var w := 0.08
	var surfaces := []

	# Quad 1 along X.
	surfaces.append(_make_quad(
		Vector3(-w, 0, 0), Vector3(w, 0, 0), Vector3(w, h, 0), Vector3(-w, h, 0)
	))
	# Quad 2 along Z (crossed).
	surfaces.append(_make_quad(
		Vector3(0, 0, -w), Vector3(0, 0, w), Vector3(0, h, w), Vector3(0, h, -w)
	))

	for verts: Array in surfaces:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = PackedVector3Array(verts)
		# Two triangles per quad, counter-clockwise facing out.
		arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
		blade.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/world/grass_blade.gdshader")
	mat.set_shader_parameter("blade_color", blade_color)
	blade.surface_set_material(0, mat)
	if blade.get_surface_count() > 1:
		blade.surface_set_material(1, mat)
	return blade

func _make_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> Array:
	return [a, b, c, d]

func get_blade_count() -> int:
	var mm := _get_mm()
	return mm.instance_count if mm else 0

func get_custom_aabb() -> AABB:
	return _mmi.custom_aabb if _mmi else AABB()

func _get_mm() -> MultiMesh:
	return _mmi.multimesh if _mmi else null
