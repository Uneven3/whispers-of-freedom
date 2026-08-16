@tool
class_name TerrainGrassInstancer
extends Node3D

## Places grass on real Terrain3D terrain via its native foliage instancer
## (Terrain3DInstancer/Terrain3DAssets), instead of GrassField's own
## standalone MultiMeshInstance3D. Reuses the same blade mesh + wind/gradient
## shader, and the same clump-scatter placement algorithm as
## scripts/world/grass_field.gd — only WHERE instances end up (fed to
## Terrain3D, which owns culling/LOD/regions) and their Y (sampled from real
## terrain height, not a flat y=0 plane) differ.
##
## Deliberately NOT a live-tunable @tool like GrassField: every export change
## would re-run Terrain3DInstancer.clear_by_mesh()+add_transforms(), and it's
## not yet confirmed that doesn't dirty world_data/terrain/*.res on an
## editor autosave. Rebuild only happens in _ready() (reload the scene to see
## changes) until that's verified safe.
##
## Known reduction vs. GrassField: no max_blade_height / blade_width_scale
## knobs. GrassField rescales the base mesh's vertices before building its
## MultiMesh; Terrain3DMeshAsset.set_scene_file() consumes the .blend's mesh
## as authored, with no pre-instancing rescale hook. Overall size still
## varies per-instance via min_scale/max_scale (uniform on all 3 axes, same
## as GrassField), just not independently on height vs. width. Revisit if
## that turns out to matter (e.g. pre-bake a rescaled mesh variant).

## Node implementing the Terrain3D class (has get_assets()/get_instancer()/get_data()).
@export var terrain_path: NodePath
@export_file("*.blend") var blade_asset_path: String = "res://art/blender/grass/grass_blade_single.blend"

@export var blade_count: int = 10000
@export var field_radius: float = 40.0
@export var clump_count: int = 60
@export var clump_spread: float = 8.0
@export var min_scale: float = 0.7
@export var max_scale: float = 1.4

@export var blade_color: Color = Color(0.22, 0.42, 0.18, 1.0)
@export var tip_color: Color = Color(0.55, 0.68, 0.30, 1.0)
@export var wind_speed: float = 1.6
@export var wind_strength: float = 0.35
@export var sway_frequency: float = 2.2
@export var sway_amplitude: float = 0.06

## Mesh matches the .blend's own authored height (see class doc — no
## max_blade_height knob here), so the shader's base-tip gradient normalizes
## against a fixed 1.0, same as the raw unit mesh GrassField loads before
## its own rescale.
const BLADE_HEIGHT := 1.0

func _ready() -> void:
	_build.call_deferred()

func _build() -> void:
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
	var mesh_asset = ClassDB.instantiate("Terrain3DMeshAsset")
	mesh_asset.set_name(mesh_name)
	mesh_asset.set_scene_file(base_scene)
	mesh_asset.set_material_override(_build_shader_material())
	mesh_asset.set_last_lod(0)

	# set_mesh_asset(id, ...) does NOT respect the id argument for a NEW
	# entry -- it always assigns the NEXT sequential slot and only
	# overwrites in place if id matches an EXISTING entry's own id
	# (verified against the running engine). Without hunting for an
	# existing entry first, every time this scene merely gets loaded in the
	# editor (not even played -- @tool runs _ready() on scene open too) a
	# fresh duplicate would pile up in terrain_assets.tres and get baked
	# into the region .res files right along with it. Reuse the slot by
	# name if one already exists; only append a new one the first time.
	var existing_list: Array = assets.get_mesh_list()
	var target_index: int = existing_list.size()
	for i in existing_list.size():
		if existing_list[i].get_name() == mesh_name:
			target_index = i
			break
	assets.set_mesh_asset(target_index, mesh_asset)
	# Read the real id back afterward; never assume it equals target_index.
	var mesh_id: int = mesh_asset.get_id()

	var generated := _generate_instance_data(data, global_position)
	# clear_by_mesh() first so reloading the scene (or re-running _build())
	# never accumulates duplicate instances on top of a previous run.
	instancer.clear_by_mesh(mesh_id)
	instancer.add_transforms(mesh_id, generated.transforms, generated.colors, true)

func _build_shader_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://scripts/world/grass_blade.gdshader")
	mat.set_shader_parameter("blade_color", blade_color)
	mat.set_shader_parameter("tip_color", tip_color)
	mat.set_shader_parameter("blade_height", BLADE_HEIGHT)
	mat.set_shader_parameter("wind_speed", wind_speed)
	mat.set_shader_parameter("wind_strength", wind_strength)
	mat.set_shader_parameter("sway_frequency", sway_frequency)
	mat.set_shader_parameter("sway_amplitude", sway_amplitude)
	return mat

## Pure and testable on purpose: Terrain3DInstancer.add_transforms() cannot
## be exercised under GUT's headless dummy renderer (confirmed: it fails
## with "Mesh ID out of range" even after registering the mesh asset and
## waiting several frames -- the renderer never creates the MultiMeshInstance
## slot for a new id). This function only depends on Terrain3DData.get_height()
## (works headless) so it's the actual placement logic under test.
##
## Same clump-scatter algorithm as GrassField._build_field(): clump centers
## sampled uniform-in-area (sqrt(randf()) * field_radius, not randf() *
## field_radius -- see grass_field.gd's own history for why that distinction
## matters), blades scattered around a random clump with gaussian falloff,
## clamped to field_radius. origin is added so the instancer's own position
## in the scene becomes the field's center (world space, since Terrain3DData
## height queries are in world coordinates).
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
		var pos2d: Vector2 = (center + offset).limit_length(field_radius)
		var world_x := origin.x + pos2d.x
		var world_z := origin.z + pos2d.y
		var h: float = terrain_data.get_height(Vector3(world_x, 0.0, world_z))
		if is_nan(h):
			continue  # outside sculpted regions -- skip rather than place at a bogus height

		var scale := rng.randf_range(min_scale, max_scale)
		var rot_y := rng.randf_range(0.0, TAU)
		var tilt := rng.randf_range(-0.12, 0.12)
		# scaled_local(), not scaled() -- Transform3D.scaled() multiplies the
		# ORIGIN too (confirmed against the engine: Transform3D(basis,
		# Vector3(3,0,4)).scaled(Vector3(2,2,2)).origin == (6,0,8)), which
		# would drift each blade's root position by up to +/- 40% (min/max
		# scale) instead of just resizing it in place. scaled_local() only
		# scales the basis, leaving world_x/h/world_z exactly where they
		# were placed.
		var xf := Transform3D(
			Basis(Vector3(0, 1, 0), rot_y) * Basis(Vector3(1, 0, 0), tilt),
			Vector3(world_x, h, world_z)
		).scaled_local(Vector3(scale, scale, scale))
		transforms.append(xf)

		var height_frac := (scale - min_scale) / maxf(max_scale - min_scale, 0.001)
		colors.append(Color(rng.randf_range(0.0, 1.0), height_frac, rng.randf_range(0.0, 1.0), 0.0))

	return {"transforms": transforms, "colors": colors}
