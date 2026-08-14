class_name LocomotionStateReader
extends RefCounted

## Read-only view of the active locomotion mode.
## Constructed by MovementBroker and distributed to external consumers
## (Camera, Combat, UI). Never exposes set_state().

signal state_changed(old_mode: int, new_mode: int)

var _state: LocomotionState

func _init(state: LocomotionState) -> void:
	assert(state is LocomotionState, "LocomotionStateReader requires a LocomotionState")
	_state = state
	_state.state_changed.connect(_on_state_changed)

func get_current_mode() -> int:
	return _state.get_active_mode()

func _on_state_changed(old_mode: int, new_mode: int) -> void:
	state_changed.emit(old_mode, new_mode)
