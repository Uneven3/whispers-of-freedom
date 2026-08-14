extends "res://addons/gut/test.gd"

const FormComponentScript = preload("res://scripts/player_action_stack/form/form_component.gd")
const FormBrokerScript = preload("res://scripts/player_action_stack/form/form_broker.gd")

func _setup_form_broker() -> Array:
	var controller := Node.new()
	controller.name = "EntityController"
	add_child_autofree(controller)

	var component: Node = FormComponentScript.new()
	component.name = "FormComponent"
	controller.add_child(component)

	var broker: Node = FormBrokerScript.new()
	broker.name = "FormBroker"
	controller.add_child(broker)

	return [component, broker]

func test_tick_applies_requested_form_shift():
	var setup := _setup_form_broker()
	var component: Node = setup[0]
	var broker: Node = setup[1]
	await get_tree().process_frame

	var intents := Intents.new()
	intents.wants_form_shift = &"avian"

	watch_signals(broker)
	broker.tick(intents, 0.016)

	assert_eq(component.get_current_form(), &"avian")
	assert_signal_emitted(broker, "form_shifted")

func test_disabled_broker_ignores_shift_intent():
	var setup := _setup_form_broker()
	var component: Node = setup[0]
	var broker: Node = setup[1]
	await get_tree().process_frame

	var intents := Intents.new()
	intents.wants_form_shift = &"monkey"
	broker.set_shifts_enabled(false)
	broker.tick(intents, 0.016)

	assert_eq(component.get_current_form(), &"panther")

func test_motor_masks_differentiate_form_capabilities():
	var setup := _setup_form_broker()
	var broker: Node = setup[1]
	await get_tree().process_frame

	var panther_mask: Array[StringName] = broker.motor_mask_for(&"panther")
	var avian_mask: Array[StringName] = broker.motor_mask_for(&"avian")

	assert_true(panther_mask.has(&"SneakMotor"))
	assert_false(avian_mask.has(&"SneakMotor"))
	assert_true(avian_mask.has(&"GlideMotor"))
