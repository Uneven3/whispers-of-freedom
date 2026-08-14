extends "res://addons/gut/test.gd"

## §19 regression: PlayerBrain resolves %CameraRig/%Camera3D across the
## entity_base.tscn instance boundary. This only works because both PlayerBrain
## and CameraRig are authored directly in player.tscn (same owner) even though
## PlayerBrain hangs off the instanced EntityController — confirmed against
## real Godot semantics, not assumed. get_node_or_null fails silently, so this
## has to assert non-null, not just "no error on load".

func test_player_brain_resolves_camera_via_unique_name():
	var player_ps: PackedScene = load("res://scenes/player.tscn")
	assert_not_null(player_ps, "player.tscn should load")

	var player := player_ps.instantiate()
	add_child_autofree(player)
	await get_tree().process_frame

	var brain := player.get_node("EntityController/PlayerBrain")
	assert_not_null(brain.get("_camera_rig"), "%CameraRig should resolve from PlayerBrain")
	assert_not_null(brain.get("_camera_3d"), "%Camera3D should resolve from PlayerBrain")
	assert_eq(brain.get("_camera_rig"), player.get_node("CameraRig"), "%CameraRig should be the real CameraRig node")
