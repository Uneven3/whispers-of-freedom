extends "res://addons/gut/test.gd"

## Verifies the horse scene instantiates the shared entity stack with per-entity
## config: static ground-only motor mask, its own brain, distinct motor values,
## and a horizontal 2x capsule whose geometry is derived from the shape.

func test_horse_scene_configuration():
	var horse_ps: PackedScene = load("res://scenes/horse.tscn")
	assert_not_null(horse_ps, "horse.tscn should load")

	var horse := horse_ps.instantiate()
	add_child_autofree(horse)

	var controller: Node = horse.get_node("EntityController")
	var broker: MovementBroker = controller.get_node("MovementBroker")

	var mask: Array = controller.get("default_motor_mask")
	assert_has(mask, &"WalkMotor", "horse can walk")
	assert_has(mask, &"SprintMotor", "horse can sprint")
	assert_has(mask, &"JumpMotor", "horse can jump")
	assert_false(mask.has(&"ClimbMotor"), "horse cannot climb")
	assert_false(mask.has(&"SneakMotor"), "horse cannot sneak")
	assert_false(mask.has(&"GlideMotor"), "horse cannot glide")

	assert_eq(broker.get("brain_path"), NodePath("../HorseBrain"), "horse uses its own brain")

	assert_almost_eq(broker.get_node("WalkMotor").max_speed, 8.0, 0.001, "horse walk speed is faster")
	assert_almost_eq(broker.get_node("SprintMotor").sprint_speed, 14.0, 0.001, "horse sprint speed is faster")
	assert_almost_eq(controller.get_node("StaminaComponent").max_stamina, 150.0, 0.001, "horse has more stamina")

	var shape_node: CollisionShape3D = horse.get_node("EntityController/Body/CollisionShape3D")
	var capsule := shape_node.shape as CapsuleShape3D
	assert_not_null(capsule, "horse body is a capsule")
	assert_almost_eq(capsule.radius, 1.0, 0.001, "horse capsule radius 2x player")
	assert_almost_eq(capsule.height, 4.0, 0.001, "horse capsule height 2x player")

	await get_tree().process_frame

	assert_not_null(controller.get_node("HorseBrain"), "HorseBrain wired")
	assert_null(controller.get_node_or_null("CombatBroker"), "horse has no combat")
