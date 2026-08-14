extends "res://addons/gut/test.gd"

## Tests for the reusable entity stack: entity_base.tscn instanced without a
## CombatBroker (mount/enemy case) must apply a static motor mask and use a
## custom brain_path.

class DummyBrain extends Node:
	func get_intents() -> Intents:
		var intents := Intents.new()
		intents.move_dir = Vector2(1, 0)
		return intents

func test_entity_base_instances_with_static_mask_and_brain():
	var base_ps: PackedScene = load("res://scenes/entity_base.tscn")
	assert_not_null(base_ps, "entity_base.tscn should load")

	var controller := base_ps.instantiate()
	controller.name = "EntityController"

	var brain := DummyBrain.new()
	brain.name = "DummyBrain"
	controller.add_child(brain)

	var broker: MovementBroker = controller.get_node("MovementBroker")
	broker.brain_path = NodePath("../DummyBrain")
	var mask: Array[StringName] = [
		&"WalkMotor", &"SprintMotor", &"FallMotor", &"JumpMotor",
		&"StairsMotor", &"AutoVaultMotor", &"MantleMotor",
	]
	controller.default_motor_mask = mask

	add_child_autofree(controller)

	await get_tree().process_frame

	assert_eq(broker.get("_brain"), brain, "brain_path should resolve to DummyBrain")
	assert_true(broker.get("_allowed_motor_names").has(&"WalkMotor"), "WalkMotor allowed")
	assert_false(broker.get("_allowed_motor_names").has(&"SneakMotor"), "SneakMotor NOT allowed")
	assert_false(broker.get("_allowed_motor_names").has(&"ClimbMotor"), "ClimbMotor NOT allowed")
	assert_false(broker.get("_allowed_motor_names").has(&"GlideMotor"), "GlideMotor NOT allowed")

	# §19: these resolve via %UniqueName within entity_base.tscn's own owner —
	# confirm the migration off relative get_node_or_null("../X") actually works,
	# not just that _ready() didn't error (get_node_or_null fails silently).
	assert_not_null(broker.get("_body"), "%Body should resolve")
	assert_not_null(broker.get("_stamina"), "%StaminaComponent should resolve")
	assert_not_null(broker.get("_ground_service"), "%GroundService should resolve")
	assert_not_null(broker.get("_ledge_service"), "%LedgeService should resolve")
	assert_not_null(broker.get("_stairs_service"), "%StairsService should resolve")
	assert_not_null(broker.get("_ladder_service"), "%LadderService should resolve")
