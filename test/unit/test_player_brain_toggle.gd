extends "res://addons/gut/test.gd"

var PlayerBrain = load("res://scripts/player_action_stack/movement/player_brain.gd")
var ClimbToggleComponent = load("res://scripts/player_action_stack/movement/climb_toggle_component.gd")
var LocomotionState = load("res://scripts/player_action_stack/movement/locomotion_state.gd")

func _setup_brain_and_toggle() -> Array:
	var controller = Node.new()
	controller.name = "EntityController"
	add_child_autofree(controller)
	
	var toggle = ClimbToggleComponent.new()
	toggle.name = "ClimbToggleComponent"
	controller.add_child(toggle)
	
	var brain = PlayerBrain.new()
	brain.name = "PlayerBrain"
	controller.add_child(brain)
	
	return [brain, toggle]

func test_climb_toggle():
	var setup = _setup_brain_and_toggle()
	var brain = setup[0]
	var toggle = setup[1]
	
	# Initial state: toggle OFF
	var intents = brain.get_intents()
	assert_false(intents.wants_climb, "Initially wants_climb should be false")
	
	# Simulate '1' press (climb_debug action)
	var event = InputEventAction.new()
	event.action = "climb_debug"
	event.pressed = true
	toggle._input(event)
	
	intents = brain.get_intents()
	assert_true(intents.wants_climb, "After press, wants_climb should be true (toggle ON)")
	
	# Simulate another '1' press
	toggle._input(event)
	intents = brain.get_intents()
	assert_false(intents.wants_climb, "After second press, wants_climb should be false (toggle OFF)")

func test_climb_reset_on_wall_jump_away():
	var setup = _setup_brain_and_toggle()
	var brain = setup[0]
	var toggle = setup[1]
	
	# Toggle ON
	var event = InputEventAction.new()
	event.action = "climb_debug"
	event.pressed = true
	toggle._input(event)
	assert_true(brain.get_intents().wants_climb)
	
	# Simulate state change to WALL_JUMP while Neutral (Away)
	toggle._on_locomotion_state_changed(LocomotionState.ID.CLIMB, LocomotionState.ID.WALL_JUMP)
	
	assert_false(brain.get_intents().wants_climb, "wants_climb should be reset to false on away wall jump")

func test_climb_stays_on_wall_jump_lateral():
	var setup = _setup_brain_and_toggle()
	var brain = setup[0]
	var toggle = setup[1]
	
	# Toggle ON
	var event = InputEventAction.new()
	event.action = "climb_debug"
	event.pressed = true
	toggle._input(event)
	
	# Simulate pressing LEFT (A)
	Input.action_press("move_left")
	assert_true(brain.get_intents().is_climbing_left)
	
	# Simulate state change to WALL_JUMP while holding LEFT
	toggle._on_locomotion_state_changed(LocomotionState.ID.CLIMB, LocomotionState.ID.WALL_JUMP)
	
	assert_true(brain.get_intents().wants_climb, "wants_climb should stay true on lateral wall jump")
	
	Input.action_release("move_left")

func test_climb_reset_on_wall_jump_back():
	var setup = _setup_brain_and_toggle()
	var brain = setup[0]
	var toggle = setup[1]
	
	# Toggle ON
	var event = InputEventAction.new()
	event.action = "climb_debug"
	event.pressed = true
	toggle._input(event)
	
	# Simulate pressing BACK (S)
	Input.action_press("move_backward")
	assert_true(brain.get_intents().is_climbing_down)
	
	# Simulate state change to WALL_JUMP while holding BACK
	toggle._on_locomotion_state_changed(LocomotionState.ID.CLIMB, LocomotionState.ID.WALL_JUMP)
	
	assert_false(brain.get_intents().wants_climb, "wants_climb should reset to false on backward wall jump")
	
	Input.action_release("move_backward")

func test_climb_reset_on_mantle():
	var setup = _setup_brain_and_toggle()
	var brain = setup[0]
	var toggle = setup[1]
	
	# Toggle ON
	var event = InputEventAction.new()
	event.action = "climb_debug"
	event.pressed = true
	toggle._input(event)
	
	# Simulate state change to MANTLE
	toggle._on_locomotion_state_changed(LocomotionState.ID.CLIMB, LocomotionState.ID.MANTLE)
	
	assert_false(brain.get_intents().wants_climb, "wants_climb should be reset to false on mantle")

func test_climb_reset_on_edge_leap():
	var setup = _setup_brain_and_toggle()
	var brain = setup[0]
	var toggle = setup[1]

	# Toggle ON
	var event = InputEventAction.new()
	event.action = "climb_debug"
	event.pressed = true
	toggle._input(event)

	# Simulate state change to EDGE_LEAP
	toggle._on_locomotion_state_changed(LocomotionState.ID.CLIMB, LocomotionState.ID.EDGE_LEAP)

	assert_false(brain.get_intents().wants_climb, "wants_climb should be reset to false on edge leap")

func test_climb_reset_on_auto_vault():
	var setup = _setup_brain_and_toggle()
	var brain = setup[0]
	var toggle = setup[1]

	# Toggle ON
	var event = InputEventAction.new()
	event.action = "climb_debug"
	event.pressed = true
	toggle._input(event)

	# Simulate state change to AUTO_VAULT
	toggle._on_locomotion_state_changed(LocomotionState.ID.CLIMB, LocomotionState.ID.AUTO_VAULT)

	assert_false(brain.get_intents().wants_climb, "wants_climb should be reset to false on auto vault")

func test_climb_stays_on_jump():
	var setup = _setup_brain_and_toggle()
	var brain = setup[0]
	var toggle = setup[1]

	# Toggle ON
	var event = InputEventAction.new()
	event.action = "climb_debug"
	event.pressed = true
	toggle._input(event)

	# JUMP should NOT clear the toggle — player may jump then grab a wall
	toggle._on_locomotion_state_changed(LocomotionState.ID.WALK, LocomotionState.ID.JUMP)

	assert_true(brain.get_intents().wants_climb, "wants_climb should stay true through a floor jump")
