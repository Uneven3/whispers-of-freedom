extends "res://addons/gut/test.gd"

## BodyReader geometry derives half-height and radius from the entity's
## CollisionShape3D, accounting for the shape's rotation (horizontal vs vertical
## capsule).

func _make_body(capsule: CapsuleShape3D, rotation: Vector3) -> CharacterBody3D:
	var body := CharacterBody3D.new()
	var shape_node := CollisionShape3D.new()
	shape_node.name = "CollisionShape3D"
	shape_node.shape = capsule
	shape_node.rotation = rotation
	body.add_child(shape_node)
	add_child_autofree(body)
	return body

func test_vertical_capsule_player_defaults():
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.5
	capsule.height = 2.0
	var reader := BodyReader.new(_make_body(capsule, Vector3.ZERO))
	assert_almost_eq(reader.get_body_half_height(), 1.0, 0.001, "player half-height = height/2")
	assert_almost_eq(reader.get_body_radius(), 0.5, 0.001, "player radius = capsule radius")

func test_horizontal_capsule_mount():
	var capsule := CapsuleShape3D.new()
	capsule.radius = 1.0
	capsule.height = 4.0
	# 90 deg around X lays the capsule on its side — long axis along Z.
	var reader := BodyReader.new(_make_body(capsule, Vector3(PI / 2.0, 0, 0)))
	assert_almost_eq(reader.get_body_half_height(), 1.0, 0.001, "horizontal mount half-height = radius")
	assert_almost_eq(reader.get_body_radius(), 2.0, 0.001, "horizontal mount radius = height/2")

func test_missing_shape_falls_back_to_player_defaults():
	var body := CharacterBody3D.new()
	add_child_autofree(body)
	var reader := BodyReader.new(body)
	assert_almost_eq(reader.get_body_half_height(), 1.0, 0.001, "fallback half-height")
	assert_almost_eq(reader.get_body_radius(), 0.5, 0.001, "fallback radius")
