extends "res://addons/gut/test.gd"

## Unit tests for TerrainGrassInstancer's pure placement logic
## (_generate_instance_data). Terrain3DInstancer.add_transforms() itself
## cannot be exercised under GUT's headless dummy renderer -- confirmed
## while planning this: it fails with "Mesh ID out of range" even after
## registering the mesh asset and waiting several frames, because the dummy
## renderer never creates a MultiMeshInstance slot for a new mesh id. So
## these tests go through the real Terrain3DData (loaded from the actual
## sculpted regions in world_data/terrain/) for height sampling -- that part
## does work headless -- and stop short of touching the instancer.

const TerrainGrassInstancerScript = preload("res://scripts/world/grass_terrain_instancer.gd")

var _terrain: Node

## Loads the real terrain_base.tscn instead of a bare Terrain3D.new() --
## confirmed while writing this test that a standalone, minimally-configured
## Terrain3D node logs spurious errors under GUT (missing active camera,
## resource loading noise from unset material/assets) that a real scene
## already avoids. Same pattern as test_terrain_base.gd.
func before_each():
	var ps: PackedScene = load("res://scenes/terrain_base.tscn")
	var root := ps.instantiate()
	add_child_autofree(root)
	_terrain = root.get_node("Terrain3D")

## Same known, harmless Terrain3D warning test_terrain_base.gd already
## consumes (see its own comment) -- only prints once per process, so only
## whichever test in this file runs first actually sees it.
func _expect_known_terrain3d_warnings() -> void:
	for err in get_errors():
		if err.contains_text("instance_reset_physics_interpolation") or err.contains_text("Cannot find the active camera"):
			err.handled = true

func _build_instancer(blade_count: int = 500) -> Node3D:
	var inst := TerrainGrassInstancerScript.new()
	inst.blade_count = blade_count
	inst.field_radius = 10.0
	add_child_autofree(inst)
	return inst

## get_height() returns NAN for real, in-region points if called before any
## frame has processed (confirmed empirically while planning this) -- so
## every test here awaits a frame before calling _generate_instance_data(),
## matching what _build()'s call_deferred() achieves in the real scene.
func test_generated_positions_land_on_real_terrain_height():
	await get_tree().process_frame
	_expect_known_terrain3d_warnings()
	var data = _terrain.get_data()
	var inst := _build_instancer()
	var result: Dictionary = inst._generate_instance_data(data, Vector3.ZERO)
	var transforms: Array[Transform3D] = result.transforms
	assert_gt(transforms.size(), 0, "should place at least some instances near the origin region")
	for xf: Transform3D in transforms:
		assert_false(is_nan(xf.origin.y), "no instance should carry a NAN height")

func test_generated_positions_and_colors_match_in_count():
	await get_tree().process_frame
	_expect_known_terrain3d_warnings()
	var data = _terrain.get_data()
	var inst := _build_instancer()
	var result: Dictionary = inst._generate_instance_data(data, Vector3.ZERO)
	var transforms: Array[Transform3D] = result.transforms
	var colors: PackedColorArray = result.colors
	assert_eq(transforms.size(), colors.size(), "one instance-custom color per transform")

func test_positions_stay_within_field_radius_of_origin():
	await get_tree().process_frame
	_expect_known_terrain3d_warnings()
	var data = _terrain.get_data()
	var inst := _build_instancer()
	inst.field_radius = 5.0
	var origin := Vector3(3.0, 0.0, -2.0)
	var result: Dictionary = inst._generate_instance_data(data, origin)
	var transforms: Array[Transform3D] = result.transforms
	var all_in_bounds := true
	for xf: Transform3D in transforms:
		var flat := Vector2(xf.origin.x - origin.x, xf.origin.z - origin.z)
		if flat.length() > 5.01:
			all_in_bounds = false
			break
	assert_true(all_in_bounds, "all generated positions stay within field_radius of the given origin")

func test_points_far_outside_sculpted_regions_are_skipped_not_placed_at_bogus_height():
	await get_tree().process_frame
	_expect_known_terrain3d_warnings()
	var data = _terrain.get_data()
	var inst := _build_instancer()
	# Far enough outside the ~3x3 sculpted region grid (world_data/terrain/
	# has 8 .res files around the origin) that every sample should be NAN.
	var result: Dictionary = inst._generate_instance_data(data, Vector3(100000.0, 0.0, 100000.0))
	assert_eq(result.transforms.size(), 0, "no instances placed where terrain height is undefined")
