class_name FormDebugReporter
extends Node

@onready var _broker: Node = get_parent()

func _ready() -> void:
	set_process(false)
	set_physics_process(false)
	if _broker:
		_broker.connect("form_shifted", _on_form_shifted)

func _on_form_shifted(new_form: StringName) -> void:
	if not OS.is_debug_build() or not has_node("/root/DebugOverlay"):
		return
	var overlay = get_node("/root/DebugOverlay")
	if overlay.has_method("push"):
		overlay.push(1, {"form": new_form})
