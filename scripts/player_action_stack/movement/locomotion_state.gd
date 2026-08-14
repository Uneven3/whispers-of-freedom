class_name LocomotionState
extends Node

## The Single Source of Truth for active locomotion mode.
## Only MovementBroker is permitted to call set_state().
## External consumers (Camera, Combat, UI) receive a LocomotionStateReader.

signal state_changed(old_mode: int, new_mode: int)

enum ID {
	IDLE = 0,
	WALK = 1,
	SPRINT = 2,
	FALL = 3,
	JUMP = 4,
	AUTO_VAULT = 5,
	CLIMB = 6,
	MANTLE = 7,
	STAIRS = 8,
	LADDER = 9,
	GLIDE = 10,
	SNEAK = 11,
	WALL_JUMP = 12,
	EDGE_LEAP = 13,
	STRIKE = 14
}

var _mode: ID = ID.FALL

func _ready() -> void:
	set_process(false)
	set_physics_process(false)

## Called exclusively by MovementBroker.
func set_state(new_mode: ID) -> void:
	if new_mode == _mode:
		return
	var old_mode: ID = _mode
	_mode = new_mode
	state_changed.emit(old_mode, new_mode)

func get_active_mode() -> int:
	return _mode
