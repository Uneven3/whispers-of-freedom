extends "res://addons/gut/test.gd"

## Regression coverage for terrain_base.tscn's actual scene file, not a
## double: the real bug this caught was `groups=` written as a property
## line under [node ...] instead of an attribute on the [node ...] header
## itself — a silently-ignored no-op that test_spawn_snap.gd's doubles
## can't see, since those add_to_group() from code, bypassing .tscn
## parsing entirely.

## Loading terrain_base.tscn can log Terrain3D's known
## instance_reset_physics_interpolation() deprecation warning (its compiled
## binary re-teleports the clipmap mesh every frame; harmless per the
## maintainer, fixed upstream but not in our pinned v1.0.2-stable — see
## TokisanGames/Terrain3D#934/#771) — but Godot only prints a given
## deprecation warning once per process, so only whichever test in this
## file runs first actually sees it. Consume it if present instead of
## asserting a fixed count, and instead of letting GUT fail the test on an
## engine warning we already know about.
func _expect_terrain3d_interpolation_warning() -> void:
	for err in get_errors():
		if err.contains_text("instance_reset_physics_interpolation"):
			err.handled = true

func test_terrain_node_is_in_terrain_group():
	var ps: PackedScene = load("res://scenes/terrain_base.tscn")
	var root := ps.instantiate()
	add_child_autofree(root)
	await get_tree().process_frame
	var terrain: Node = get_tree().get_first_node_in_group("terrain")
	assert_not_null(terrain, "Terrain3D node must be in the \"terrain\" group for SpawnSnap to find it")
	assert_eq(terrain.name, "Terrain3D", "the terrain group member is the Terrain3D node")
	_expect_terrain3d_interpolation_warning()

## Forces the "wrong" starting Y itself rather than trusting whatever
## Player.position.y happens to be saved in terrain_base.tscn -- an earlier
## version of this test read the saved value and asserted SpawnSnap moved
## away from it, which broke (not from a real bug) the first time someone
## repositioned Player in the editor and saved a Y that happened to already
## coincide with what SpawnSnap computes (real incident, 2026-08-16,
## playtesting session). A deliberately absurd value (1000.0, nowhere near
## any sculpted region's height) keeps this test meaningful and immune to
## the Player's saved position changing for unrelated reasons.
func test_player_spawns_above_saved_placeholder_y():
	var ps: PackedScene = load("res://scenes/terrain_base.tscn")
	var root := ps.instantiate()
	add_child_autofree(root)
	var player: Node3D = root.get_node("Player")
	var placeholder_y := 1000.0
	player.global_position.y = placeholder_y
	await get_tree().process_frame
	await get_tree().process_frame
	await get_tree().process_frame
	assert_ne(player.global_position.y, placeholder_y, "SpawnSnap must move the player off an obviously-wrong Y")
	_expect_terrain3d_interpolation_warning()
