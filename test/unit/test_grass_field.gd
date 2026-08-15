extends "res://addons/gut/test.gd"

## Tests for the grass field generator: MultiMesh with 10000 blades (configurable),
## correct custom_aabb for frustum culling, shadows off, transforms in bounds.

const GrassFieldScript = preload("res://scripts/world/grass_field.gd")

func _build_field(blade_count: int = 10000) -> Node:
	var field: Node = GrassFieldScript.new()
	field.blade_count = blade_count
	add_child_autofree(field)
	return field

func test_creates_expected_blade_count():
	var field := _build_field()
	var mmi: MultiMeshInstance3D = field.get_node("Grass")
	assert_not_null(mmi, "Grass MultiMeshInstance3D should exist")
	assert_eq(mmi.multimesh.instance_count, 10000, "default 10000 blades")

func test_blade_count_is_configurable():
	var field := _build_field(2500)
	var mmi: MultiMeshInstance3D = field.get_node("Grass")
	assert_eq(mmi.multimesh.instance_count, 2500, "configurable blade count")

func test_custom_aabb_set_for_culling():
	var field := _build_field()
	var mmi: MultiMeshInstance3D = field.get_node("Grass")
	var aabb: AABB = mmi.custom_aabb
	assert_gt(aabb.size.x, 0.0, "custom_aabb X set")
	assert_gt(aabb.size.z, 0.0, "custom_aabb Z set")

func test_grass_does_not_cast_shadows():
	var field := _build_field()
	var mmi: MultiMeshInstance3D = field.get_node("Grass")
	assert_eq(
		mmi.cast_shadow,
		GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
		"grass blades should not cast shadows"
	)

func test_transforms_inside_field_bounds():
	var field := _build_field()
	var mmi: MultiMeshInstance3D = field.get_node("Grass")
	var mm: MultiMesh = mmi.multimesh
	var all_in_bounds := true
	for i in mm.instance_count:
		var p: Vector3 = mm.get_instance_transform(i).origin
		if p.length() > 41.0 or p.y < -0.1 or p.y > 0.1:
			all_in_bounds = false
			break
	assert_true(all_in_bounds, "all blade transforms inside field radius + on ground")

func test_positions_vary_across_field():
	var field := _build_field()
	var positions: Array[Vector2] = field.get_blade_positions()
	assert_eq(positions.size(), 10000, "positions array matches blade count")
	# Distribution must not be a uniform grid — positions should differ.
	var unique: Dictionary = {}
	for i in range(0, 200):
		unique[positions[i]] = true
	assert_gt(unique.size(), 1, "blade positions vary (no uniform grid)")
	# And all within the field radius.
	var all_in_bounds := true
	for p: Vector2 in positions:
		if p.length() > 41.0:
			all_in_bounds = false
			break
	assert_true(all_in_bounds, "all computed positions inside field radius")

func test_uses_custom_instance_data_for_wind_variation():
	var field := _build_field()
	var mmi: MultiMeshInstance3D = field.get_node("Grass")
	var mm: MultiMesh = mmi.multimesh
	assert_true(mm.is_using_custom_data(), "INSTANCE_CUSTOM enabled for wind phase variation")
	# The wind shader must be bound to the blade material (GPU-side variation;
	# custom data buffers are not readable under the headless dummy renderer).
	var blade_mat: ShaderMaterial = mm.mesh.surface_get_material(0) as ShaderMaterial
	assert_not_null(blade_mat, "blade uses a ShaderMaterial")
	assert_not_null(blade_mat.shader, "blade shader assigned")

func test_blade_count_rebuilds_live_after_ready():
	var field := _build_field()
	await get_tree().process_frame
	field.blade_count = 500
	# _queue_rebuild() defers the rebuild — give the deferred call two frames
	# to land before asserting, matching how it behaves in the Inspector.
	await get_tree().process_frame
	await get_tree().process_frame
	var mmi: MultiMeshInstance3D = field.get_node("Grass")
	assert_eq(mmi.multimesh.instance_count, 500, "editing an export var after _ready rebuilds without a scene restart")

func test_blade_mesh_uses_the_blender_authored_asset():
	var field := _build_field()
	var mmi: MultiMeshInstance3D = field.get_node("Grass")
	var mesh: ArrayMesh = mmi.multimesh.mesh
	assert_eq(mesh.get_surface_count(), 1, "Blender asset is a single crossed-leaf mesh, not the 2-surface fallback")

func test_blade_height_scales_with_max_blade_height():
	var field := _build_field()
	field.max_blade_height = 2.0
	await get_tree().process_frame
	await get_tree().process_frame
	var mmi: MultiMeshInstance3D = field.get_node("Grass")
	var arrays := mmi.multimesh.mesh.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var max_y := 0.0
	for v: Vector3 in verts:
		max_y = maxf(max_y, v.y)
	assert_almost_eq(max_y, 2.0, 0.01, "blade tip height should follow max_blade_height")

func test_fallback_blade_mesh_is_still_valid_if_asset_missing():
	var field := _build_field()
	var mesh: ArrayMesh = field._build_fallback_blade_mesh()
	assert_eq(mesh.get_surface_count(), 2, "fallback is the flat crossed-quad, 2 surfaces")
	assert_not_null(mesh.surface_get_material(0), "fallback still carries the wind shader material")

func test_blade_asset_path_caching_does_not_leak_across_variants():
	var single := _build_field()
	single.blade_asset_path = "res://art/blender/grass/grass_blade_single.blend"
	await get_tree().process_frame
	await get_tree().process_frame
	var tuft := _build_field()
	tuft.blade_asset_path = "res://art/blender/grass/grass_blade_tuft.blend"
	await get_tree().process_frame
	await get_tree().process_frame

	var single_verts: PackedVector3Array = single.get_node("Grass").multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var tuft_verts: PackedVector3Array = tuft.get_node("Grass").multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(single_verts.size(), 8, "single variant keeps its own 2-leaf mesh (8 verts), not the tuft's cached one")
	assert_eq(tuft_verts.size(), 16, "tuft variant keeps its own 4-leaf mesh (16 verts), not the single's cached one")

func test_blade_asset_path_rebuilds_live_after_ready():
	var field := _build_field()
	await get_tree().process_frame
	field.blade_asset_path = "res://art/blender/grass/grass_blade_tuft.blend"
	await get_tree().process_frame
	await get_tree().process_frame
	var verts: PackedVector3Array = field.get_node("Grass").multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(verts.size(), 16, "editing blade_asset_path after _ready rebuilds without a scene restart")

func test_grass_comparison_scene_loads_both_variants():
	var ps: PackedScene = load("res://scenes/grass_comparison.tscn")
	assert_not_null(ps, "grass_comparison.tscn should load")
	var scene := ps.instantiate()
	add_child_autofree(scene)
	await get_tree().process_frame
	assert_not_null(scene.get_node_or_null("Player"), "player instanced in comparison scene")

	var single: Node = scene.get_node_or_null("GrassSingle")
	var tuft: Node = scene.get_node_or_null("GrassTuft")
	assert_not_null(single, "single-blade GrassField instanced")
	assert_not_null(tuft, "tuft-blade GrassField instanced")

	var single_verts: PackedVector3Array = single.get_node("Grass").multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var tuft_verts: PackedVector3Array = tuft.get_node("Grass").multimesh.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	assert_eq(single_verts.size(), 8, "GrassSingle really uses the single-leaf asset")
	assert_eq(tuft_verts.size(), 16, "GrassTuft really uses the tuft asset")

func test_grass_field_scene_loads_with_player():
	var ps: PackedScene = load("res://scenes/grass_field.tscn")
	assert_not_null(ps, "grass_field.tscn should load")
	var field := ps.instantiate()
	add_child_autofree(field)
	await get_tree().process_frame
	assert_not_null(field.get_node_or_null("Player"), "player instanced in grass field")
	var mmi: MultiMeshInstance3D = field.get_node_or_null("Grass")
	assert_not_null(mmi, "grass generated in scene")
	assert_eq(mmi.multimesh.instance_count, 10000, "scene field has 10000 blades")
