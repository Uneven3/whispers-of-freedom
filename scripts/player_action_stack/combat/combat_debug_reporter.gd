class_name CombatDebugReporter
extends Node

@onready var _broker: Node = get_parent()

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if _broker and _broker.has_signal("combat_state_changed"):
		_broker.connect("combat_state_changed", _on_combat_state_changed)
	if _broker and _broker.has_signal("hit_landed"):
		_broker.connect("hit_landed", _on_hit_landed)

func _on_combat_state_changed(state: StringName) -> void:
	_push({"combat": state})

func _on_hit_landed(event: RefCounted) -> void:
	_push({
		"combat": _broker.get_combat_state() if _broker and _broker.has_method("get_combat_state") else "-",
		"last_hit": "%s %.0f" % [event.damage_type, event.amount] if event else "-"
	})

func _push(data: Dictionary) -> void:
	if not OS.is_debug_build() or not has_node("/root/DebugOverlay"):
		return
	var overlay = get_node("/root/DebugOverlay")
	if overlay.has_method("push"):
		overlay.push(1, data)
