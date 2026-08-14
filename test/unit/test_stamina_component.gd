extends GutTest

# Tests for: StaminaComponent (scripts/player_action_stack/movement/stamina_component.gd)

var subject: StaminaComponent

func before_each():
	subject = StaminaComponent.new()
	add_child_autofree(subject)

func after_each():
	# subject is freed by add_child_autofree
	assert_no_new_orphans()

func test_default_values():
	assert_eq(subject.get_max(), 100.0)
	assert_eq(subject.get_current(), 100.0)
	assert_eq(subject.get_normalized(), 1.0)
	assert_false(subject.is_exhausted())

func test_drain_reduces_stamina():
	watch_signals(subject)
	subject.drain(20.0)
	
	assert_eq(subject.get_current(), 80.0)
	assert_signal_emitted_with_parameters(subject, "stamina_changed", [80.0, 100.0])

func test_drain_clamps_at_zero():
	subject.drain(150.0)
	
	assert_eq(subject.get_current(), 0.0)
	assert_true(subject.is_exhausted())

func test_recover_increases_stamina():
	subject.drain(50.0)
	watch_signals(subject)
	subject.recover(20.0)
	
	assert_eq(subject.get_current(), 70.0)
	assert_signal_emitted_with_parameters(subject, "stamina_changed", [70.0, 100.0])

func test_recover_clamps_at_max():
	subject.recover(50.0)
	
	assert_eq(subject.get_current(), 100.0)

func test_get_normalized():
	subject.drain(25.0)
	assert_eq(subject.get_normalized(), 0.75)
	
	subject.drain(75.0)
	assert_eq(subject.get_normalized(), 0.0)

func test_is_exhausted():
	assert_false(subject.is_exhausted())
	subject.drain(100.0)
	assert_true(subject.is_exhausted())
