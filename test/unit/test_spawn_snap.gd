extends "res://addons/gut/test.gd"

## Tests for SpawnSnap: snaps its parent to ground height reported by a
## "terrain" group member, once, without a static Terrain3D type (that
## plugin isn't committed to the repo — see AHORA.md).

const SpawnSnapScript = preload("res://scripts/player_action_stack/spawn_snap.gd")

## Minimal duck-typed double: exposes `data` (an object with get_height()),
## same shape SpawnSnap expects from a real Terrain3D node.
class FakeTerrainData:
	var height: float
	func _init(h: float) -> void:
		height = h
	func get_height(_global_position: Vector3) -> float:
		return height

class FakeTerrain extends Node:
	var data: FakeTerrainData
	func _init(h: float) -> void:
		data = FakeTerrainData.new(h)

func test_noop_without_terrain_group_member():
	var player := Node3D.new()
	player.position = Vector3(0, 1.5, 0)
	var snap := SpawnSnapScript.new()
	player.add_child(snap)
	add_child_autofree(player)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(player.global_position.y, 1.5, "no terrain group member — position untouched")

func test_snaps_to_terrain_group_member_height():
	var terrain := FakeTerrain.new(12.0)
	terrain.add_to_group("terrain")
	add_child_autofree(terrain)

	var player := Node3D.new()
	player.position = Vector3(0, 1.5, 0)
	var snap := SpawnSnapScript.new()
	snap.height_offset = 0.1
	player.add_child(snap)
	add_child_autofree(player)

	await get_tree().process_frame
	await get_tree().process_frame
	assert_almost_eq(player.global_position.y, 12.1, 0.001, "snaps to terrain height + offset")

func test_noop_when_height_is_nan():
	var terrain := FakeTerrain.new(NAN)
	terrain.add_to_group("terrain")
	add_child_autofree(terrain)

	var player := Node3D.new()
	player.position = Vector3(0, 1.5, 0)
	var snap := SpawnSnapScript.new()
	player.add_child(snap)
	add_child_autofree(player)

	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(player.global_position.y, 1.5, "NAN height (outside regions/hole) — position untouched")
