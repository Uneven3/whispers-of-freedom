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
