class_name TransitionProposal
extends RefCounted

enum Priority {
    DEFAULT = 0,
    PLAYER_REQUESTED = 1,
    OPPORTUNISTIC = 2,
    FORCED = 3
}

var target_state: int
var category: int
var override_weight: int
var source_id: StringName

func _init(p_target_state: int, p_category: int = Priority.DEFAULT, p_override_weight: int = 0, p_source_id: StringName = &"") -> void:
    target_state = p_target_state
    category = p_category
    override_weight = p_override_weight
    source_id = p_source_id
