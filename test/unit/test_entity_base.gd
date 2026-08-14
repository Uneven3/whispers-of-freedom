extends "res://addons/gut/test.gd"

## Tests for the reusable entity stack: entity_base.tscn instanced without a
## FormBroker/CombatBroker (mount/enemy case) must apply a static motor mask and
## use a custom brain_path.

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
