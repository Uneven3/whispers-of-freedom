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

## Regression test for a real bug the user found playtesting (2026-08-16,
## screenshot showed a bright ring of extra-dense grass right at the edge
## of the field): the old code used Vector2.limit_length(field_radius) to
## keep points in bounds, which PROJECTS any out-of-bounds point onto the
## exact boundary circle instead of discarding it -- every blade whose
## clump+offset would have landed outside field_radius piled up at exactly
## that radius. field_radius=5.0 with the default clump_spread=8.0 (spread
## wider than the field itself) reliably pushes many points out of bounds,
## so this setup would have produced a heavy artificial pileup at the
## boundary under the old behavior.
func test_positions_do_not_pile_up_at_the_field_radius_boundary():
	await get_tree().process_frame
	_expect_known_terrain3d_warnings()
	var data = _terrain.get_data()
	var inst := _build_instancer()
	inst.field_radius = 5.0
	var origin := Vector3(3.0, 0.0, -2.0)
	var result: Dictionary = inst._generate_instance_data(data, origin)
	var transforms: Array[Transform3D] = result.transforms

	assert_lt(transforms.size(), inst.blade_count,
		"with clump_spread wider than field_radius, some blades must be discarded, not all of them clamped onto the boundary")

	var boundary_count := 0
	for xf: Transform3D in transforms:
		var flat := Vector2(xf.origin.x - origin.x, xf.origin.z - origin.z)
		if flat.length() > 4.95:  # within 1% of field_radius = a pileup, not natural falloff
			boundary_count += 1
	var boundary_fraction := float(boundary_count) / maxf(float(transforms.size()), 1.0)
	assert_lt(boundary_fraction, 0.05,
		"no more than a small fraction of instances should land right at the boundary -- a large fraction would mean positions are still being clamped onto the edge instead of discarded")

## Covers the historical duplicate-entry bug (docs/AHORA.md, "Bug real
## encontrado por el usuario...") AND a second, worse bug caught while
## building this test: calling assets.set_mesh_asset() a second time with a
## freshly-instantiated object (even at the correct existing array index, or
## even the existing entry's own real id) does not reliably preserve that
## entry's id unless mesh_asset.set_id() is called on it first -- without
## that, it silently reassigns the new object to an unrelated, already-used
## id, corrupting a different entry (see _register_mesh_asset()'s doc
## comment for the empirical probes that found this and the fix). Both
## matter now that live Inspector tuning calls rebuild() (and therefore
## _register_mesh_asset()) many times per session instead of once per
## _ready(). Deliberately does not go through rebuild() itself or
## add_transforms() -- both require a real MultiMeshInstance slot that
## GUT's headless dummy renderer never creates for a new mesh id. inst is
## never added to the tree, so its own _ready()/@tool machinery never runs
## -- this test only exercises the pure registration method directly.
func test_register_mesh_asset_reuses_same_id_without_corrupting_others():
	await get_tree().process_frame
	_expect_known_terrain3d_warnings()
	var assets = _terrain.get_assets()
	var before_snapshot: Array = assets.get_mesh_list().map(func(m): return [m.get_name(), m.get_id()])
	var inst := TerrainGrassInstancerScript.new()
	var base_scene: PackedScene = load("res://art/blender/grass/grass_blade_single.blend")

	var id1: int = inst._register_mesh_asset(assets, "TestReuseAsset", base_scene)
	var count_after_first: int = assets.get_mesh_list().size()
	assert_eq(count_after_first, before_snapshot.size() + 1, "first call should append exactly one new slot")

	for i in 4:
		var next_id: int = inst._register_mesh_asset(assets, "TestReuseAsset", base_scene)
		assert_eq(assets.get_mesh_list().size(), count_after_first,
			"registering the same name again must reuse the id, never append a new slot")
		assert_eq(next_id, id1, "the reused id stays stable across repeated registrations")

	var after_snapshot: Array = []
	for m in assets.get_mesh_list():
		if m.get_name() != "TestReuseAsset":
			after_snapshot.append([m.get_name(), m.get_id()])
	assert_eq(after_snapshot, before_snapshot, "unrelated pre-existing entries must keep their own name/id untouched")

	inst.free()

## Regression test for 2026-08-16's shadow-off change: cast_shadows defaults
## to 1/"On" on a fresh Terrain3DMeshAsset (confirmed via reflection while
## planning this) and was never touched before -- _register_mesh_asset() must
## explicitly turn it off now, or every one of blade_count instances goes
## back to casting a full shadow pass for no visual payoff on thin blades.
func test_register_mesh_asset_disables_shadow_casting():
	var assets = _terrain.get_assets()
	var inst := TerrainGrassInstancerScript.new()
	var base_scene: PackedScene = load("res://art/blender/grass/grass_blade_single.blend")

	inst._register_mesh_asset(assets, "TestShadowOff", base_scene)
	var entry = null
	for m in assets.get_mesh_list():
		if m.get_name() == "TestShadowOff":
			entry = m
	assert_eq(entry.cast_shadows, 0, "grass must not cast shadows (0 = Off)")

	inst.free()

## Regression test for the classic-billboard pivot (2026-08-16): the
## registered asset must carry the real card shader as its material_override
## -- this lives on the Terrain3DMeshAsset/MultiMeshInstance3D, not baked
## onto the Mesh resource's own surface (that stays whatever Blender authored).
func test_register_mesh_asset_applies_the_card_shader_material():
	var assets = _terrain.get_assets()
	var inst := TerrainGrassInstancerScript.new()
	var base_scene: PackedScene = load("res://art/blender/grass/grass_billboard_clump.blend")

	inst._register_mesh_asset(assets, "TestCardMaterial", base_scene)
	var entry = null
	for m in assets.get_mesh_list():
		if m.get_name() == "TestCardMaterial":
			entry = m
	var mat: ShaderMaterial = entry.get_material_override()
	assert_eq(mat.shader, load("res://scripts/world/grass_blade.gdshader"), "must use the card shader")

	inst.free()

func test_points_far_outside_sculpted_regions_are_skipped_not_placed_at_bogus_height():
	await get_tree().process_frame
	_expect_known_terrain3d_warnings()
	var data = _terrain.get_data()
	var inst := _build_instancer()
	# Far enough outside the ~3x3 sculpted region grid (world_data/terrain/
	# has 8 .res files around the origin) that every sample should be NAN.
	var result: Dictionary = inst._generate_instance_data(data, Vector3(100000.0, 0.0, 100000.0))
	assert_eq(result.transforms.size(), 0, "no instances placed where terrain height is undefined")

## Regression test for a real bug found playtesting (2026-08-16): unticking
## "Visible" in the Inspector did nothing, because the grass lives in
## MultiMeshInstance3D nodes Terrain3D owns, not as children of this node --
## Node3D's own `visible` property was never wired to anything. Fix: _ready()
## connects visibility_changed to _queue_rebuild().
##
## Deliberately does NOT set terrain_path (same as _build_instancer()) --
## rebuild() returns early at "terrain_path does not resolve to a node"
## before ever reaching add_transforms(), which is the whole point: setting
## a real terrain_path here would let the deferred rebuild() actually run
## and hit the already-documented "Mesh ID out of range" failure under
## GUT's headless dummy renderer (see this file's header comment).
##
## No await needed: signal emission is synchronous while the node is in the
## tree (add_child_autofree already put it there), and _queue_rebuild()
## sets _rebuild_queued = true synchronously before scheduling the actual
## deferred rebuild() call -- the assertion only needs to observe that
## synchronous part, never the deferred rebuild() itself running.
func test_toggling_visible_queues_a_rebuild():
	var inst := TerrainGrassInstancerScript.new()
	add_child_autofree(inst)
	assert_true(inst._ready_done, "node should be past _ready() once added to the tree")

	inst.visible = false
	assert_true(inst._rebuild_queued, "hiding the node must queue a rebuild so the grass actually disappears")


## El shader del atlas usa tex.a como ALPHA. Una malla sin UV samplea en
## (0,0), obtiene alfa 0 y se descarta entera: el pasto se dibuja invisible
## sin un solo error en consola. Ya costó una sesión de mediciones falsas
## (docs/presupuesto_render.md) y reapareció apenas alguien cambió
## blade_asset_path desde el editor. Estos tests fijan el camino opaco y el
## aviso, que es lo que evita que vuelva a pasar en silencio.
##
## Sí corre headless: elegir y construir un ShaderMaterial no necesita
## rasterizar nada -- lo que no se puede headless es add_transforms(), ver
## el comentario de cabecera de este archivo.
func test_opaque_mode_builds_the_opaque_shader_not_the_atlas_one():
	var inst := TerrainGrassInstancerScript.new()
	add_child_autofree(inst)

	inst.material_mode = TerrainGrassInstancerScript.MATERIAL_OPAQUE
	var opaque: ShaderMaterial = inst._build_shader_material()
	assert_eq(opaque.shader.resource_path, "res://scripts/world/grass_blade_opaque.gdshader",
		"opaque mode must not fall back to the alpha_to_coverage shader")
	assert_null(opaque.get_shader_parameter("card_texture"),
		"the opaque path must not sample the atlas at all")

	inst.material_mode = TerrainGrassInstancerScript.MATERIAL_ATLAS_ALPHA
	var alpha: ShaderMaterial = inst._build_shader_material()
	assert_eq(alpha.shader.resource_path, "res://scripts/world/grass_blade.gdshader",
		"alpha mode must keep using the atlas shader")


## grass_blade_single perdió sus UV a propósito en la vigésima sesión. Si esa
## afirmación deja de ser cierta, el aviso de _warn_if_alpha_mode_on_uvless_mesh
## deja de tener sentido y este test avisa primero.
func test_the_single_blade_mesh_really_has_no_uvs():
	var inst := TerrainGrassInstancerScript.new()
	add_child_autofree(inst)

	var packed: PackedScene = load("res://art/blender/grass/grass_blade_single.blend")
	assert_not_null(packed, "grass_blade_single.blend must import (needs Blender Path configured)")
	var mesh: Mesh = inst._first_mesh_of(packed)
	assert_not_null(mesh, "the .blend must contain a MeshInstance3D with a mesh")
	assert_eq(mesh.surface_get_format(0) & Mesh.ARRAY_FORMAT_TEX_UV, 0,
		"single blade must stay UV-less -- if this fails, the atlas-alpha warning is now wrong")
