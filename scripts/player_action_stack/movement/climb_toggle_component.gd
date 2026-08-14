class_name ClimbToggleComponent
extends Node

var _is_active: bool = false

func _ready() -> void:
	# Defer connection so MovementBroker._ready() has run and state_changed is wired up.
	call_deferred("_connect_to_broker")

func _connect_to_broker() -> void:
	var broker = get_node_or_null("../MovementBroker")
	if broker and broker.has_signal("state_changed"):
		broker.state_changed.connect(_on_locomotion_state_changed)

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("climb_debug"):
		_is_active = !_is_active

func _on_locomotion_state_changed(_old_mode: int, new_mode: int) -> void:
	# Reset climb toggle if we mantle, perform an edge leap, or auto-vault over an obstacle.
	# JUMP is intentionally excluded: a floor jump from a climbable wall should not erase
	# the player's climb intention — the toggle persists so ClimbMotor can re-engage
	# immediately on the next wall contact.
	if new_mode == LocomotionState.ID.MANTLE \
	or new_mode == LocomotionState.ID.EDGE_LEAP \
	or new_mode == LocomotionState.ID.AUTO_VAULT:
		_is_active = false
	
	# Conditional reset for Wall Jump:
	elif new_mode == LocomotionState.ID.WALL_JUMP:
		var brain = get_node_or_null("../PlayerBrain")
		if brain and brain.has_method("get_intents"):
			var intents: Intents = brain.get_intents()
			var is_jumping_to_stick: bool = intents.is_climbing_up or intents.is_climbing_left or intents.is_climbing_right
			if not is_jumping_to_stick:
				_is_active = false

func is_active() -> bool:
	return _is_active
