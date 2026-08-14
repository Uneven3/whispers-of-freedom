extends "res://addons/gut/test.gd"

const FormComponentScript = preload("res://scripts/player_action_stack/form/form_component.gd")

func test_default_form_is_panther():
	var component: Node = FormComponentScript.new()
	add_child_autofree(component)
	await get_tree().process_frame

	assert_eq(component.get_current_form(), &"panther")
	assert_true(component.can_shift_to(&"monkey"))
	assert_true(component.can_shift_to(&"avian"))

func test_set_form_emits_and_changes_state():
	var component: Node = FormComponentScript.new()
	add_child_autofree(component)
	await get_tree().process_frame

	watch_signals(component)
	var changed: bool = component.set_form(&"monkey")

	assert_true(changed)
	assert_eq(component.get_current_form(), &"monkey")
	assert_signal_emitted(component, "form_changed")

func test_same_form_is_noop():
	var component: Node = FormComponentScript.new()
	add_child_autofree(component)
	await get_tree().process_frame

	watch_signals(component)
	var changed: bool = component.set_form(&"panther")

	assert_false(changed)
	assert_signal_not_emitted(component, "form_changed")

func test_invalid_form_is_rejected():
	var component: Node = FormComponentScript.new()
	add_child_autofree(component)
	await get_tree().process_frame

	var changed: bool = component.set_form(&"wolf")

	assert_false(changed)
	assert_eq(component.get_current_form(), &"panther")
	assert_push_error("Invalid form shift requested")
