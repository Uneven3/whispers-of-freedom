extends "res://addons/gut/test.gd"

## Tests for SpawnSnap: snaps its parent to ground height reported by a
## "terrain" group member, once, without a static Terrain3D type (that
## plugin isn't committed to the repo — see AHORA.md). Also adds the Body's
## half-height (via BodyReader) so the capsule's feet land on the surface
## instead of its center — landing the origin directly on the terrain
## buries half the capsule in the mesh ("stuck in the ground").

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

## Stands in for MovementBroker: only the get_body_reader() surface SpawnSnap
## actually calls.
class FakeBroker extends Node:
	var reader: BodyReader
	func get_body_reader() -> BodyReader:
		return reader

func test_noop_without_terrain_group_member():
	var player := Node3D.new()
	player.position = Vector3(0, 1.5, 0)
	var snap := SpawnSnapScript.new()
	player.add_child(snap)
	add_child_autofree(player)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(player.global_position.y, 1.5, "no terrain group member — position untouched")

func test_snaps_to_terrain_height_using_fallback_half_height():
	var terrain := FakeTerrain.new(12.0)
	terrain.add_to_group("terrain")
	add_child_autofree(terrain)

	var player := Node3D.new()
	player.position = Vector3(0, 1.5, 0)
	var snap := SpawnSnapScript.new()
	player.add_child(snap)
	add_child_autofree(player)

	await get_tree().process_frame
	await get_tree().process_frame
	# No MovementBroker in this tree, so SpawnSnap falls back to its default
	# half-height (1.0) + default clearance (0.5).
	assert_almost_eq(player.global_position.y, 13.5, 0.001, "terrain height + fallback half-height + clearance")

func test_snaps_using_body_half_height_from_broker():
	var player := Node3D.new()
	player.position = Vector3(0, 1.5, 0)

	var entity_controller := Node.new()
	entity_controller.name = "EntityController"
	player.add_child(entity_controller)

	var body := CharacterBody3D.new()
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	var capsule := CapsuleShape3D.new()
	capsule.height = 4.0
	capsule.radius = 0.5
	shape_node.shape = capsule
	body.add_child(shape_node)
	entity_controller.add_child(body)

	var broker := FakeBroker.new()
	broker.name = "MovementBroker"
	broker.reader = BodyReader.new(body)
	entity_controller.add_child(broker)

	var terrain := FakeTerrain.new(0.0)
	terrain.add_to_group("terrain")
	add_child_autofree(terrain)

	var snap := SpawnSnapScript.new()
	snap.clearance = 0.0
	player.add_child(snap)
	add_child_autofree(player)

	await get_tree().process_frame
	await get_tree().process_frame
	# capsule.height 4.0 -> half-height 2.0, not the 1.0 fallback.
	assert_almost_eq(player.global_position.y, 2.0, 0.001, "uses BodyReader.get_body_half_height(), not the fallback")

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
