@tool
class_name TerrainGrassInstancer
extends Node3D

## Places textured billboard grass on Terrain3D via its native foliage
## instancer (Terrain3DInstancer/Terrain3DAssets). Full history and the
## empirical findings behind each decision below: docs/pasto_godot.md.
##
## Live-tunable @tool: each @export debounces into one deferred rebuild(),
## guarded by _ready_done so scene deserialization doesn't fire N rebuilds.
## visible wires into rebuild() directly -- the grass lives in Terrain3D's
## own MultiMeshInstance3D nodes, not as children here, so Node3D's own
## visibility has no effect otherwise.

## Node implementing the Terrain3D class (has get_assets()/get_instancer()/get_data()).
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

## Pure/testable on purpose: Terrain3DInstancer.add_transforms() can't run
## under GUT's headless dummy renderer, but assets.set_mesh_asset() can.
##
## Builds a brand-new Terrain3DMeshAsset and sets its properties before
## registering it, never mutates an already-registered entry in place --
## that path triggers Terrain3D's Asset Dock thumbnail regen, which needs a
## real viewport and errors under any headless context. Overwriting an
## existing id requires mesh_asset.set_id(existing_id) first, or
## set_mesh_asset() silently reassigns id 0 and corrupts an unrelated entry.
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

## Pure/testable, same reasoning as _register_mesh_asset(): only depends on
## Terrain3DData.get_height(), which works headless.
##
## Clump centers sampled uniform-in-area (sqrt(randf()) * field_radius, not
## randf() * field_radius, or centers would bunch toward the origin).
## Blades scatter around a random clump with gaussian falloff, clamped to
## field_radius. origin is added so the instancer's own scene position
## becomes the field's center.
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
		var pos2d: Vector2 = center + offset
		if pos2d.length() > field_radius:
			# Discard rather than limit_length() onto the boundary, which
			# would pile every out-of-bounds point exactly onto the edge.
			continue
		var world_x := origin.x + pos2d.x
		var world_z := origin.z + pos2d.y
		var h: float = terrain_data.get_height(Vector3(world_x, 0.0, world_z))
		if is_nan(h):
			continue  # outside sculpted regions

		var blade_scale := rng.randf_range(min_scale, max_scale)
		var rot_y := rng.randf_range(0.0, TAU)
		var tilt := rng.randf_range(-0.12, 0.12)
		# scaled_local(), not scaled() -- the latter also scales the origin,
		# drifting each blade's root position off its sampled ground point.
		var xf := Transform3D(
			Basis(Vector3(0, 1, 0), rot_y) * Basis(Vector3(1, 0, 0), tilt),
			Vector3(world_x, h, world_z)
		).scaled_local(Vector3(blade_scale, blade_scale, blade_scale))
		transforms.append(xf)

		var height_frac := (blade_scale - min_scale) / maxf(max_scale - min_scale, 0.001)
		colors.append(Color(rng.randf_range(0.0, 1.0), height_frac, rng.randf_range(0.0, 1.0), 0.0))

	return {"transforms": transforms, "colors": colors}
